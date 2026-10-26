const HELPER = "/data/adb/modules/native_tailscale/webui.sh";
const $ = (q) => document.querySelector(q);
const $$ = (q) => [...document.querySelectorAll(q)];

/* 所有面客文案统一走 I18N；词典缺失时回退 key，避免直接抛错。 */
function t(key, params) {
  return window.I18N ? window.I18N.t(key, params) : key;
}

/* 显示映射：比较/判定逻辑一律使用英文原值，仅显示层翻译（契约规则 8）。 */
const STATE_KEYS = {
  Running: "state.Running",
  Stopped: "state.Stopped",
  Starting: "state.Starting",
  NeedsLogin: "state.NeedsLogin",
  NoState: "state.NoState",
  NeedsMachineAuth: "state.NeedsMachineAuth",
  Unavailable: "state.Unavailable",
};

const INTEGRITY_KEYS = {
  verified: "integrity.verified",
  modified: "integrity.modified",
  recorded: "integrity.recorded",
  unrecorded: "integrity.unrecorded",
  unknown: "integrity.unknown",
};

const INTERFACE_KEYS = { up: "interface.up", down: "interface.down" };

/* 操作标题：按钮点击 → 忙碌遮罩 → 结果弹窗复用同一份文案。 */
const ACTION_TITLE_KEYS = {
  start: "action.starting_service",
  stop: "action.stopping_service",
  restart: "action.restarting_service",
  login: "action.tailscale_signin",
  verify: "action.verifying_binaries",
  "binary-update": "action.updating_binaries",
  "open-admin": "action.opening_admin",
  "clear-logs": "action.clearing_log",
  diagnostics: "action.diagnostics",
};

function displayState(value) {
  if (!value) return t("state.Unavailable");
  const key = STATE_KEYS[value];
  return key ? t(key) : value;
}

function displayIntegrity(value) {
  if (!value) return t("integrity.unknown");
  const key = INTEGRITY_KEYS[value];
  return key ? t(key) : value;
}

function displayInterface(value) {
  const normalized = String(value || "down").toLowerCase();
  const key = INTERFACE_KEYS[normalized];
  return key ? t(key) : normalized;
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

let callbackId = 0;
let sessionRestoreUntil = 0;
let lastStatus = null;
let logsLoaded = false;
let lastDialog = null;
window.__nativeTailscaleCallbacks = {};

function execHelper(args) {
  if (!window.ksu || typeof window.ksu.exec !== "function") {
    return Promise.reject(new Error(t("error.bridge_unavailable")));
  }
  return new Promise((resolve, reject) => {
    const id = `callback${++callbackId}`;
    const timer = setTimeout(() => {
      delete window.__nativeTailscaleCallbacks[id];
      reject(new Error(t("error.timeout")));
    }, 240000);
    window.__nativeTailscaleCallbacks[id] = (code, stdout, stderr) => {
      clearTimeout(timer);
      delete window.__nativeTailscaleCallbacks[id];
      if (code === 0) resolve(stdout);
      else reject(new Error(stderr || stdout || t("error.command_failed", { code })));
    };
    window.ksu.exec(`${HELPER} ${args}`, null, `window.__nativeTailscaleCallbacks.${id}`);
  });
}

function parseFields(output) {
  return Object.fromEntries(String(output).split(/\r?\n/).filter(Boolean).map((line) => {
    const index = line.indexOf("=");
    return index < 0 ? [line, ""] : [line.slice(0, index), line.slice(index + 1)];
  }));
}

function bool(value) { return value === "true"; }
function setText(id, value, fallback = "—") { $(id).textContent = value || fallback; }

function showAlert(message, type = "warn") {
  const box = $("#alertBox");
  box.textContent = message;
  box.classList.toggle("hidden", !message);
  box.dataset.type = type;
}

/* 语言切换按钮显示「切换到什么语言」：en 时显示「中文」，zh-CN 时显示「EN」。 */
function renderLanguageToggle() {
  const button = $("#langToggle");
  if (!button) return;
  button.textContent = window.I18N && window.I18N.lang === "zh-CN"
    ? t("header.language_target_en")
    : t("header.language_target_zh");
}

function renderStatus(data) {
  if (!data) return;
  lastStatus = data;

  const state = data.backend_state || "Unavailable";
  setText("#backendState", displayState(data.backend_state));
  setText("#ipAddress", data.ipv4 || data.ipv6, bool(data.running) ? t("status.no_ip") : t("status.daemon_stopped"));
  setText("#interfaceState", `TUN ${displayInterface(data.interface)}`);
  setText("#commit", data.upstream_commit);
  setText("#tailscaleVersion", data.tailscale_version);
  setText("#moduleVersion", data.module_version);
  setText("#pid", data.pid, t("status.not_running"));

  const orb = $("#statusOrb");
  orb.className = "status-orb " + (state === "Running" ? "good" : /Needs|Starting/.test(state) ? "warn" : "bad");
  const integrity = $("#integrityState");
  integrity.textContent = displayIntegrity(data.integrity);
  integrity.className = "integrity " + (data.integrity === "verified" ? "good" : data.integrity === "modified" ? "bad" : "");

  $$('[data-setting]').forEach((input) => {
    const key = input.dataset.setting.replace(/-([a-z])/g, (_, c) => "_" + c);
    if (data[key] !== "") input.checked = bool(data[key]);
    input.disabled = !bool(data.running);
  });
  if (document.activeElement !== $("#hostname")) $("#hostname").value = data.hostname || "";

  const loginButton = $("#loginButton");
  const restoringSession = bool(data.running) && /Starting|NeedsLogin|NoState/.test(state) && Date.now() < sessionRestoreUntil;
  const signedIn = bool(data.running) && state === "Running";
  $("#loginButtonLabel").textContent = signedIn ? t("action.signed_in") : restoringSession ? t("action.restoring") : t("action.sign_in");
  $("#loginButtonIcon").setAttribute("d", signedIn ? "m5 12 4 4L19 6" : "M10 17 15 12 10 7M15 12H3M14 4h6v16h-6");
  loginButton.classList.toggle("signed-in", signedIn);
  loginButton.disabled = signedIn || restoringSession || !bool(data.running) || state === "Starting";

  if (bool(data.official_vpn)) showAlert(t("alert.official_vpn"));
  else if (data.integrity === "modified") showAlert(t("alert.integrity_modified"), "bad");
  else if (/NeedsLogin|NoState/.test(state) && Date.now() < sessionRestoreUntil) showAlert(t("alert.restoring_session"));
  else if (/NeedsLogin|NoState/.test(state)) showAlert(t("alert.needs_login"));
  else showAlert("");
}

/* 以 root 侧 status 的 ui_language 为权威语言（WebView 存储可能被清空）。 */
function syncLanguageFromStatus(data) {
  if (!data || !window.I18N) return false;
  const authoritative = window.I18N.normalize ? window.I18N.normalize(data.ui_language) : null;
  if (!authoritative || authoritative === window.I18N.lang) return false;
  window.I18N.setLang(authoritative, { persist: false });
  return true;
}

async function refreshStatus(force = false, scheduleFollowup = force) {
  try {
    const data = parseFields(await execHelper(force ? "status refresh" : "status"));
    renderStatus(data);
    syncLanguageFromStatus(data);
    if (scheduleFollowup) setTimeout(() => refreshStatus(false), 1200);
    return data;
  } catch (error) {
    showAlert(error.message, "bad");
    setText("#backendState", displayState("Unavailable"));
    return null;
  }
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function refreshAfterServiceStart() {
  sessionRestoreUntil = Date.now() + 20000;
  // A new daemon can briefly report NeedsLogin until it receives a fresh
  // network map. This is the same recovery request as the header refresh.
  let data = await refreshStatus(true, false);

  while (data && bool(data.running) && /Starting|NeedsLogin|NoState/.test(data.backend_state || "") && Date.now() < sessionRestoreUntil) {
    await delay(1200);
    data = await refreshStatus(true, false);
  }

  sessionRestoreUntil = 0;
  if (data && /NeedsLogin|NoState/.test(data.backend_state || "")) renderStatus(data);
}

function setBusy(enabled, text = t("busy.working")) {
  $("#busyText").textContent = text;
  $("#busy").classList.toggle("hidden", !enabled);
}

/* 弹窗标题保留 key，语言切换时可在原位置重新翻译。 */
function showOutput(titleKey, output, params) {
  lastDialog = { titleKey, params };
  $("#dialogTitle").textContent = t(titleKey, params);
  $("#dialogOutput").textContent = output || t("dialog.completed");
  $("#loginLink").classList.add("hidden");
  $("#loginLink").removeAttribute("href");
  $("#loginUrlBox").classList.add("hidden");
  $("#loginUrlText").textContent = "";
  $("#outputDialog").showModal();
}

function showLoginOutput(output) {
  const match = String(output).match(/^login_url=(https:\/\/\S+)/m);
  if (!match) {
    showOutput("action.tailscale_signin", output);
    return;
  }
  const message = String(output).replace(/^login_url=.*(?:\r?\n)?/m, "").trim();
  showOutput("action.tailscale_signin", message || t("dialog.login_instructions"));
  $("#loginLink").href = match[1];
  $("#loginLink").classList.remove("hidden");
  $("#loginUrlText").textContent = match[1];
  $("#loginUrlBox").classList.remove("hidden");
}

async function runAction(action, titleKey, params) {
  const title = t(titleKey, params);
  setBusy(true, `${title}…`);
  try {
    const output = await execHelper(action);
    if (action === "login") showLoginOutput(output);
    else if (action === "open-admin") { /* Browser opened by the allowlisted helper. */ }
    else showOutput(titleKey, output, params);
  } catch (error) {
    showOutput("dialog.failed", error.message, { name: title });
  } finally {
    setBusy(false);
    if (action === "start" || action === "restart") await refreshAfterServiceStart();
    else refreshStatus(false);
    if (action === "clear-logs") loadLogs();
  }
}

/* 语言切换：立即切换界面 → 通知 helper 持久化（失败静默忽略）→ 用缓存数据重渲染。 */
$("#langToggle").addEventListener("click", async () => {
  if (!window.I18N) return;
  const next = window.I18N.lang === "zh-CN" ? "en" : "zh-CN";
  window.I18N.setLang(next);
  renderLanguageToggle();
  if (lastStatus) renderStatus(lastStatus);
  try {
    await execHelper(`set-language ${next}`);
  } catch (error) {
    /* 持久化失败不影响当前会话的语言切换 */
  }
});

/* i18n:change 由 I18N.setLang 派发：静态区域已由 apply() 处理，这里刷新动态区域。 */
document.addEventListener("i18n:change", () => {
  renderLanguageToggle();
  if (lastStatus) renderStatus(lastStatus);
  if (lastDialog && $("#outputDialog").open) $("#dialogTitle").textContent = t(lastDialog.titleKey, lastDialog.params);
  if (logsLoaded) loadLogs();
});

$("#refresh").addEventListener("click", () => refreshStatus(true));
$("#closeDialog").addEventListener("click", () => $("#outputDialog").close());
$$('[data-action]').forEach((button) => button.addEventListener("click", () => {
  runAction(button.dataset.action, ACTION_TITLE_KEYS[button.dataset.action] || "action.diagnostics");
}));

$$('[data-setting]').forEach((input) => input.addEventListener("change", () => {
  const title = input.closest("label").querySelector("strong").textContent;
  runAction(`set ${input.dataset.setting} ${input.checked}`, "dialog.updating", { name: title });
}));

$("#saveHostname").addEventListener("click", () => {
  const hostname = $("#hostname").value.trim();
  if (!/^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,61}[A-Za-z0-9])?$/.test(hostname) || hostname.includes("..")) {
    showOutput("dialog.invalid_hostname", t("dialog.hostname_hint"));
    return;
  }
  runAction(`set hostname ${shellQuote(hostname)}`, "action.updating_hostname");
});

async function loadLogs() {
  try {
    $("#logs").textContent = await execHelper("logs") || t("logs.empty");
    logsLoaded = true;
  } catch (error) {
    $("#logs").textContent = error.message;
  }
}
$("#loadLogs").addEventListener("click", loadLogs);
$(".logs-card").addEventListener("toggle", (event) => { if (event.target.open) loadLogs(); });

/* 初始化顺序：先本地化静态界面，再拉取状态并用 ui_language 对齐权威语言。 */
if (window.I18N) window.I18N.init();
renderLanguageToggle();

refreshStatus(false).then(() => {
  const integrityValue = lastStatus ? lastStatus.integrity : "";
  if (integrityValue === "recorded") {
    execHelper("verify").catch(() => {}).finally(() => refreshStatus(false));
  }
});
