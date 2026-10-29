#!/usr/bin/env node
/**
 * check-i18n.js — Native Tailscale TUN 双语一致性校验
 *
 * 用法：
 *   node tools/check-i18n.js                    # 全量校验
 *   node tools/check-i18n.js --only web,shell   # 只看指定领域
 *   node tools/check-i18n.js --verbose          # 打印通过项
 *
 * 领域：text / web / shell / meta / docs / release
 * 退出码：0 = 无 error（warning 允许），1 = 有 error
 *
 * 依据：I18N-CONTRACT.md v1。修改本脚本前请先确认契约。
 */
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const zlib = require("zlib");
const crypto = require("crypto");

const ROOT = path.resolve(__dirname, "..");
const LANG_EN = "en";
const LANG_ZH = "zh-CN";
const SUPPORTED = [LANG_EN, LANG_ZH];

const EXPECTED = {
  version: "0.5.7-zh",
  versionCode: "507",
  tag: "v0.5.7-zh",
  zipName: "native-tailscale-magisk-bootstrap-v0.5.7-zh.zip",
  forkRepo: "Strbit/Tailscale-native-magisk",
  forkRaw: "https://raw.githubusercontent.com/Strbit/Tailscale-native-magisk/main",
  releaseBase: "https://github.com/Strbit/Tailscale-native-magisk/releases/download",
};

const argv = process.argv.slice(2);
const only = (() => {
  const i = argv.indexOf("--only");
  if (i < 0) return null;
  return new Set((argv[i + 1] || "").split(",").map((s) => s.trim()).filter(Boolean));
})();
const verbose = argv.includes("--verbose");

let currentArea = "text";
const results = [];

function record(level, scope, message) {
  results.push({ level, scope, area: currentArea, message });
}

const error = (scope, message) => record("error", scope, message);
const warn = (scope, message) => record("warn", scope, message);
const pass = (scope, message) => record("ok", scope, message);

function area(name, label, fn) {
  currentArea = name;
  const start = results.length;
  try {
    fn();
  } catch (e) {
    error(label, `校验过程抛出异常：${e && e.stack ? e.stack.split("\n")[0] : e}`);
  }
  const added = results.slice(start);
  if (!added.some((r) => r.level !== "ok")) pass(label, "通过");
}

/* ------------------------------------------------------------------ */
/* 通用工具                                                            */
/* ------------------------------------------------------------------ */

function p(rel) {
  return path.join(ROOT, rel);
}
function exists(rel) {
  return fs.existsSync(p(rel));
}
function readText(rel) {
  return fs.readFileSync(p(rel), "utf8");
}
function readBytes(rel) {
  return fs.readFileSync(p(rel));
}
function listFiles(rel, filter) {
  const abs = p(rel);
  if (!fs.existsSync(abs)) return [];
  const out = [];
  const stack = [abs];
  while (stack.length) {
    const dir = stack.pop();
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === ".git") continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) stack.push(full);
      else if (!filter || filter(full)) out.push(full);
    }
  }
  return out.sort();
}
function rel(abs) {
  return path.relative(ROOT, abs).split(path.sep).join("/");
}
function hasCJK(text) {
  return /[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]/.test(text);
}
function sha256(relPath) {
  return crypto.createHash("sha256").update(readBytes(relPath)).digest("hex");
}
function placeholders(text) {
  const set = new Set();
  const re = /\{([A-Za-z0-9_]+)\}/g;
  let m;
  while ((m = re.exec(text))) set.add(m[1]);
  return set;
}
function sameSet(a, b) {
  if (a.size !== b.size) return false;
  for (const v of a) if (!b.has(v)) return false;
  return true;
}
function diffSet(a, b) {
  const onlyA = [...a].filter((v) => !b.has(v));
  const onlyB = [...b].filter((v) => !a.has(v));
  return { onlyA, onlyB };
}

/* ------------------------------------------------------------------ */
/* 1. 文本编码：LF / BOM                                               */
/* ------------------------------------------------------------------ */

const TEXT_EXTS = new Set([
  ".sh", ".prop", ".txt", ".js", ".html", ".css", ".md", ".json", ".yml", ".yaml",
]);

function checkTextEncoding() {
  const targets = [
    ...listFiles("module"),
    ...listFiles(".github"),
    "README.md", "README.zh-CN.md", "CHANGELOG.md", "RELEASE_NOTES.md",
    "SHA256SUMS", "update.json", "LICENSE", "SECURITY.md", "THIRD_PARTY_NOTICES.md",
  ].filter((x) => typeof x === "string" && exists(x));

  const unique = [...new Set(targets)];
  let crlf = 0;
  let bom = 0;

  for (const file of unique) {
    const abs = path.isAbsolute(file) ? file : p(file);
    let stat;
    try {
      stat = fs.statSync(abs);
    } catch {
      continue;
    }
    if (!stat.isFile()) continue;
    const name = rel(abs);
    if (name.endsWith(".zip")) continue;
    if (!TEXT_EXTS.has(path.extname(name)) && name !== "SHA256SUMS") continue;

    const buf = fs.readFileSync(abs);
    if (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf) {
      error(name, "文件含 UTF-8 BOM（shell/prop 会被破坏）");
      bom += 1;
    }
    let found = 0;
    for (let i = 0; i < buf.length; i += 1) {
      if (buf[i] === 0x0a && i > 0 && buf[i - 1] === 0x0d) found += 1;
    }
    if (found > 0) {
      error(name, `含 CRLF 行尾 ${found} 处，必须为 LF`);
      crlf += 1;
    }
  }

  if (crlf === 0 && bom === 0) pass("编码", `${unique.length} 个文本文件均为 LF 且无 BOM`);
}

/* ------------------------------------------------------------------ */
/* 2. Web 层                                                           */
/* ------------------------------------------------------------------ */

function loadWebI18n() {
  const code = readText("module/webroot/i18n.js");
  const stubDocument = {
    documentElement: { lang: "" },
    querySelectorAll: () => [],
    querySelector: () => null,
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => {},
    createElement: () => ({ dataset: {}, style: {}, classList: { add() {}, remove() {} }, appendChild() {} }),
    readyState: "complete",
  };
  const store = new Map();
  const localStorage = {
    getItem: (k) => (store.has(k) ? store.get(k) : null),
    setItem: (k, v) => store.set(k, String(v)),
    removeItem: (k) => store.delete(k),
  };
  const sandbox = {
    console,
    setTimeout: (fn) => 0,
    clearTimeout: () => {},
    CustomEvent: class CustomEvent {
      constructor(type, init) {
        this.type = type;
        this.detail = init && init.detail;
      }
    },
    navigator: { language: "en-US" },
    document: stubDocument,
    localStorage,
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: "module/webroot/i18n.js", timeout: 5000 });

  const I18N = sandbox.window.I18N;
  if (!I18N || typeof I18N !== "object") {
    error("module/webroot/i18n.js", "未挂载 window.I18N");
    return null;
  }
  return { I18N, sandbox };
}

function checkWeb() {
  const html = exists("module/webroot/index.html") ? readText("module/webroot/index.html") : "";
  const appJs = exists("module/webroot/app.js") ? readText("module/webroot/app.js") : "";
  const styles = exists("module/webroot/styles.css") ? readText("module/webroot/styles.css") : "";

  if (!exists("module/webroot/i18n.js")) {
    error("module/webroot/i18n.js", "文件不存在（必需）");
    return;
  }
  if (!html) {
    error("module/webroot/index.html", "文件不存在");
    return;
  }
  if (!appJs) {
    error("module/webroot/app.js", "文件不存在");
    return;
  }

  /* --- 2.1 API --- */
  let loaded;
  try {
    loaded = loadWebI18n();
  } catch (e) {
    error("module/webroot/i18n.js", `加载失败（不得在顶层访问 DOM）：${e.message}`);
    loaded = null;
  }
  if (!loaded) return;

  const { I18N } = loaded;
  const apiChecks = [
    ["supported", "array"],
    ["dict", "object"],
    ["t", "function"],
    ["setLang", "function"],
    ["detectLanguage", "function"],
    ["apply", "function"],
    ["init", "function"],
  ];
  for (const [name, kind] of apiChecks) {
    const value = I18N[name];
    const ok =
      kind === "function"
        ? typeof value === "function"
        : kind === "array"
        ? Array.isArray(value)
        : typeof value === kind;
    if (!ok) {
      error("i18n.js API", `缺少 window.I18N.${name}（应为 ${kind}）`);
    }
  }
  if (!sameSet(new Set(I18N.supported || []), new Set(SUPPORTED))) {
    error("i18n.js API", `supported 必须为 ${JSON.stringify(SUPPORTED)}，实际 ${JSON.stringify(I18N.supported)}`);
  }
  if (typeof I18N.lang !== "string" || !SUPPORTED.includes(I18N.lang)) {
    error("i18n.js API", `lang 初值应为受支持语言之一，实际 ${JSON.stringify(I18N.lang)}`);
  }

  /* --- 2.2 词典 --- */
  const dict = I18N.dict || {};
  for (const lang of SUPPORTED) {
    if (!dict[lang] || typeof dict[lang] !== "object") {
      error("i18n.js 词典", `缺少语言 ${lang}`);
      return;
    }
  }
  const enKeys = new Set(Object.keys(dict.en));
  const zhKeys = new Set(Object.keys(dict[LANG_ZH]));
  const { onlyA: enOnly, onlyB: zhOnly } = diffSet(enKeys, zhKeys);
  if (enOnly.length) error("i18n.js 词典", `zh-CN 缺少 ${enOnly.length} 个键：${enOnly.slice(0, 12).join(", ")}${enOnly.length > 12 ? " …" : ""}`);
  if (zhOnly.length) error("i18n.js 词典", `en 缺少 ${zhOnly.length} 个键：${zhOnly.slice(0, 12).join(", ")}${zhOnly.length > 12 ? " …" : ""}`);

  const identical = [];
  for (const key of enKeys) {
    if (!zhKeys.has(key)) continue;
    const en = dict.en[key];
    const zh = dict[LANG_ZH][key];
    if (typeof en !== "string" || typeof zh !== "string") {
      error("i18n.js 词典", `键 ${key} 的值必须为字符串`);
      continue;
    }
    if (!en.trim()) error("i18n.js 词典", `键 ${key} 的 en 值为空`);
    if (!zh.trim()) error("i18n.js 词典", `键 ${key} 的 zh-CN 值为空`);
    if (!sameSet(placeholders(en), placeholders(zh))) {
      const { onlyA, onlyB } = diffSet(placeholders(en), placeholders(zh));
      error("i18n.js 词典", `键 ${key} 占位符不一致：仅 en 有 [${onlyA.join(",")}]，仅 zh 有 [${onlyB.join(",")}]`);
    }
    if (en === zh && /[A-Za-z]{4,}/.test(en) && !hasCJK(en)) identical.push(key);
  }
  if (identical.length) {
    warn("i18n.js 词典", `${identical.length} 个键中英完全相同（确认是否为专名）：${identical.slice(0, 10).join(", ")}${identical.length > 10 ? " …" : ""}`);
  }
  pass("i18n.js 词典", `en ${enKeys.size} 键 / zh-CN ${zhKeys.size} 键`);

  /* --- 2.3 状态映射必需键 --- */
  const requiredKeys = [
    "state.Running", "state.Stopped", "state.Starting", "state.NeedsLogin",
    "state.NoState", "state.NeedsMachineAuth",
    "integrity.verified", "integrity.modified", "integrity.recorded",
    "integrity.unrecorded", "integrity.unknown",
    "interface.up", "interface.down",
  ];
  const missingRequired = requiredKeys.filter((k) => !enKeys.has(k) || !zhKeys.has(k));
  if (missingRequired.length) {
    error("i18n.js 词典", `缺少契约要求的显示映射键：${missingRequired.join(", ")}`);
  }

  /* --- 2.4 HTML --- */
  const attrRe = /data-i18n(?:-html|-placeholder|-aria|-title)?="([^"]+)"/g;
  const htmlKeys = new Set();
  let m;
  while ((m = attrRe.exec(html))) htmlKeys.add(m[1]);
  const missingHtml = [...htmlKeys].filter((k) => !enKeys.has(k) || !zhKeys.has(k));
  if (missingHtml.length) error("index.html", `引用了词典中不存在的键：${missingHtml.join(", ")}`);
  if (htmlKeys.size === 0) error("index.html", "未发现任何 data-i18n 属性（静态文案未本地化）");

  const i18nTag = html.indexOf('src="i18n.js"');
  const appTag = html.indexOf('src="app.js"');
  if (i18nTag < 0) error("index.html", "未引入 i18n.js");
  else if (appTag >= 0 && i18nTag > appTag) error("index.html", "i18n.js 必须在 app.js 之前加载");
  if (!/id="langToggle"/.test(html)) error("index.html", "缺少语言切换按钮 #langToggle");
  if (!/data-i18n-aria="[^"]*"/.test(html)) warn("index.html", "未发现 data-i18n-aria 用法（aria-label 需本地化）");
  if (!/<header[\s\S]*id="langToggle"[\s\S]*<\/header>/.test(html)) warn("index.html", "#langToggle 建议放在 <header> 内");

  /* --- 2.5 app.js --- */
  const literalKeys = new Set();
  const callRe = /\bt\(\s*(["'])([A-Za-z0-9_.]+)\1/g;
  while ((m = callRe.exec(appJs))) literalKeys.add(m[2]);
  const missingJs = [...literalKeys].filter((k) => !enKeys.has(k) || !zhKeys.has(k));
  if (missingJs.length) error("app.js", `引用了词典中不存在的键：${missingJs.join(", ")}`);
  if (!/I18N\.init\(\)/.test(appJs)) error("app.js", "未调用 I18N.init()");
  if (!/ui_language/.test(appJs)) error("app.js", "未使用 status 的 ui_language 字段对齐权威语言");
  if (!/set-language/.test(appJs)) error("app.js", "语言切换未调用 helper 的 set-language 持久化");

  const hardcoded = [];
  const suspicious = /\b(showAlert|showOutput|setBusy)\(\s*"(?!\s*$)([A-Z][^"]{6,})"/g;
  while ((m = suspicious.exec(appJs))) hardcoded.push(m[2]);
  if (hardcoded.length) {
    error("app.js", `疑似未本地化的硬编码文案 ${hardcoded.length} 处：${hardcoded.slice(0, 6).map((s) => `"${s}"`).join(", ")}`);
  }

  if (styles && !/#langToggle|\.lang-toggle/.test(styles)) {
    warn("styles.css", "未发现 #langToggle / .lang-toggle 样式");
  }

  pass("web", `HTML ${htmlKeys.size} 个键，JS ${literalKeys.size} 个键`);
}

/* ------------------------------------------------------------------ */
/* 3. Shell 层                                                         */
/* ------------------------------------------------------------------ */

function parseShellDict(source, fnName, fileLabel) {
  const startRe = new RegExp(`${fnName}\\s*\\(\\)\\s*\\{`);
  const startMatch = startRe.exec(source);
  if (!startMatch) {
    error(fileLabel, `缺少函数 ${fnName}()`);
    return null;
  }
  const rest = source.slice(startMatch.index);
  const endMatch = /\n\}/.exec(rest);
  const body = endMatch ? rest.slice(0, endMatch.index + 2) : rest;

  const entries = new Map();
  const entryRe = /^\s*([A-Za-z0-9_.]+)\)\s+printf\s+'%s'\s+"([^"]*)"\s+;;\s*$/gm;
  let m;
  while ((m = entryRe.exec(body))) {
    if (entries.has(m[1])) error(fileLabel, `${fnName} 中键 ${m[1]} 重复`);
    entries.set(m[1], m[2]);
  }
  if (entries.size === 0) error(fileLabel, `${fnName} 未解析到任何条目（格式需为单行：key) printf '%s' "文本" ;;）`);
  return entries;
}

function checkShell() {
  const files = [
    "module/i18n.sh", "module/webui.sh", "module/action.sh", "module/customize.sh",
    "module/service.sh", "module/watchdog.sh", "module/uninstall.sh",
  ];
  for (const f of files) if (!exists(f)) error(f, "文件不存在");

  if (!exists("module/i18n.sh")) return;
  const src = readText("module/i18n.sh");

  for (const fn of ["i18n_lang", "i18n_set_lang", "i18n_text_en", "i18n_text_zh", "msg", "msgf"]) {
    if (!new RegExp(`${fn}\\s*\\(\\)`).test(src)) error("module/i18n.sh", `缺少函数 ${fn}()`);
  }
  if (/common\.sh/.test(src)) error("module/i18n.sh", "i18n.sh 必须自包含，不得 source common.sh");
  if (/\bmkdir\b/.test(src)) error("module/i18n.sh", "i18n.sh 不得创建目录（无副作用）");
  if (/\[\[|\blocal\s+\w|\bdeclare\s|\bfunction\s+\w+\s*\(|pipefail/.test(src)) {
    error("module/i18n.sh", "检测到 bash 专有语法（[[ ]] / local / declare / function / pipefail），Android sh 不可用");
  }
  if (!/I18N_LANG_FILE/.test(src)) error("module/i18n.sh", "未定义 I18N_LANG_FILE");
  if (!/persist\.sys\.locale|ro\.product\.locale/.test(src)) {
    error("module/i18n.sh", "未实现系统语言检测（getprop persist.sys.locale / ro.product.locale）");
  }

  const en = parseShellDict(src, "i18n_text_en", "module/i18n.sh");
  const zh = parseShellDict(src, "i18n_text_zh", "module/i18n.sh");
  if (!en || !zh) return;

  const { onlyA: enOnly, onlyB: zhOnly } = diffSet(new Set(en.keys()), new Set(zh.keys()));
  if (enOnly.length) error("module/i18n.sh", `zh 缺少 ${enOnly.length} 个键：${enOnly.slice(0, 12).join(", ")}`);
  if (zhOnly.length) error("module/i18n.sh", `en 缺少 ${zhOnly.length} 个键：${zhOnly.slice(0, 12).join(", ")}`);

  for (const [key, value] of en) {
    const problems = [];
    if (value.includes("'")) problems.push("含单引号");
    const pct = (value.match(/%/g) || []).length;
    const ps = (value.match(/%s/g) || []).length;
    if (pct !== ps) problems.push("含非法 %（只允许 %s）");
    if (problems.length) error("module/i18n.sh", `en 键 ${key} ${problems.join("、")}`);
  }

  const untranslated = [];
  for (const [key, value] of zh) {
    const problems = [];
    if (value.includes("'")) problems.push("含单引号");
    const pct = (value.match(/%/g) || []).length;
    const ps = (value.match(/%s/g) || []).length;
    if (pct !== ps) problems.push("含非法 %（只允许 %s）");
    if (problems.length) error("module/i18n.sh", `zh 键 ${key} ${problems.join("、")}`);

    const enValue = en.get(key);
    if (enValue !== undefined) {
      const enPlace = (enValue.match(/%s/g) || []).length;
      if (ps !== enPlace) error("module/i18n.sh", `键 ${key} 的 %s 数量 en=${enPlace} / zh=${ps} 不一致`);
      if (!hasCJK(value) && /[A-Za-z]{4,}/.test(value)) untranslated.push(key);
    }
  }
  if (untranslated.length) {
    warn("module/i18n.sh", `${untranslated.length} 个键的 zh 值不含中文（确认是否为专名）：${untranslated.slice(0, 10).join(", ")}`);
  }
  pass("module/i18n.sh", `en ${en.size} 键 / zh ${zh.size} 键`);

  /* --- 3.1 各脚本加载 i18n.sh --- */
  const callers = {
    "module/webui.sh": /\$MODDIR\/i18n\.sh/,
    "module/action.sh": /\$MODDIR\/i18n\.sh/,
    "module/service.sh": /\$MODDIR\/i18n\.sh/,
    "module/watchdog.sh": /\$MODDIR\/i18n\.sh/,
    "module/customize.sh": /\$MODPATH\/i18n\.sh/,
  };
  for (const [file, re] of Object.entries(callers)) {
    if (!exists(file)) continue;
    const text = readText(file);
    if (!re.test(text)) error(file, "未加载 i18n.sh");
  }

  /* --- 3.2 webui.sh 接口 --- */
  if (exists("module/webui.sh")) {
    const webui = readText("module/webui.sh");
    if (!/set-language\)/.test(webui)) error("module/webui.sh", "缺少 set-language 子命令");
    if (!/field ui_language/.test(webui)) error("module/webui.sh", "status 未输出 ui_language 字段");
    if (/set-language\)[\s\S]{0,400}?require_running/.test(webui)) {
      error("module/webui.sh", "set-language 不应要求 daemon 运行");
    }
  }

  if (exists("module/customize.sh")) {
    const customize = readText("module/customize.sh");
    if (!/i18n\.sh/.test(customize)) error("module/customize.sh", "未输出 i18n.sh 到 set_perm");
    const chineseLines = customize.split("\n").filter((l) => hasCJK(l) && /ui_print|abort/.test(l));
    for (const line of chineseLines) {
      const quoted = line.match(/"([^"]*)"/g) || [];
      const hasEnglish = quoted.some((q) => /[A-Za-z]{4,}/.test(q));
      if (!hasEnglish) error("module/customize.sh", `中文安装提示缺少英文括注：${line.trim().slice(0, 80)}`);
    }
  }

  /* --- 3.3 残留英文 echo --- */
  for (const file of ["module/webui.sh", "module/action.sh", "module/customize.sh"]) {
    if (!exists(file)) continue;
    const text = readText(file);
    const bad = [];
    text.split("\n").forEach((line, i) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) return;
      if (/^\s*#/.test(trimmed)) return;
      if (!/^(echo|ui_print|abort)\b/.test(trimmed)) return;
      if (/\$\(msg/.test(trimmed) || /\bmsg\b/.test(trimmed)) return;
      const literal = trimmed.match(/"(.*)"/);
      if (!literal) return;
      if (!/[A-Za-z]{3,}/.test(literal[1])) return;
      bad.push(`${i + 1}: ${trimmed.slice(0, 70)}`);
    });
    if (bad.length) {
      warn(file, `${bad.length} 处 echo/ui_print/abort 疑似未走 msg()：${bad.slice(0, 5).join(" | ")}`);
    }
  }
}

/* ------------------------------------------------------------------ */
/* 4. 元数据                                                           */
/* ------------------------------------------------------------------ */

function parseProp(relPath) {
  const out = {};
  for (const line of readText(relPath).split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue;
    const idx = line.indexOf("=");
    if (idx < 0) continue;
    out[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
  }
  return out;
}

function checkMeta() {
  if (!exists("module/module.prop")) {
    error("module/module.prop", "文件不存在");
    return;
  }
  const prop = parseProp("module/module.prop");
  const expect = {
    id: "native_tailscale",
    name: "Native Tailscale TUN",
    version: EXPECTED.version,
    versionCode: EXPECTED.versionCode,
  };
  for (const [key, value] of Object.entries(expect)) {
    if (prop[key] !== value) error("module/module.prop", `${key} 应为 "${value}"，实际 "${prop[key] || ""}"`);
  }
  if (!prop.updateJson) error("module/module.prop", "缺少 updateJson");
  else if (!prop.updateJson.includes(EXPECTED.forkRepo)) {
    error("module/module.prop", `updateJson 未指向 fork：${prop.updateJson}`);
  }
  if (!prop.description || !hasCJK(prop.description)) error("module/module.prop", "description 需包含中文");
  if (!prop.author || !/Iridule/.test(prop.author)) error("module/module.prop", "author 必须保留上游署名 Iridule");

  if (!exists("update.json")) {
    error("update.json", "文件不存在");
  } else {
    let data;
    try {
      data = JSON.parse(readText("update.json"));
    } catch (e) {
      error("update.json", `JSON 解析失败：${e.message}`);
      return;
    }
    if (data.version !== EXPECTED.version) error("update.json", `version 应为 ${EXPECTED.version}，实际 ${data.version}`);
    if (String(data.versionCode) !== EXPECTED.versionCode) error("update.json", `versionCode 应为 ${EXPECTED.versionCode}`);
    const expectedZipUrl = `${EXPECTED.releaseBase}/${EXPECTED.tag}/${EXPECTED.zipName}`;
    if (data.zipUrl !== expectedZipUrl) error("update.json", `zipUrl 应为 ${expectedZipUrl}，实际 ${data.zipUrl}`);
    if (!data.changelog || !data.changelog.includes(EXPECTED.forkRaw)) {
      error("update.json", `changelog 未指向 fork raw：${data.changelog}`);
    }
  }
  pass("meta", "module.prop / update.json 一致");
}

/* ------------------------------------------------------------------ */
/* 5. 文档                                                             */
/* ------------------------------------------------------------------ */

function checkDocs() {
  if (!exists("README.zh-CN.md")) {
    error("README.zh-CN.md", "文件不存在（必需）");
  } else {
    const zh = readText("README.zh-CN.md");
    if (!hasCJK(zh)) error("README.zh-CN.md", "未包含中文内容");
    if (zh.length < 3000) warn("README.zh-CN.md", `篇幅偏短（${zh.length} 字符），确认章节是否完整`);
    for (const section of ["安装", "卸载", "恢复", "安全"]) {
      if (!zh.includes(section)) warn("README.zh-CN.md", `缺少「${section}」章节（对照英文 README）`);
    }
  }

  if (exists("README.md")) {
    const en = readText("README.md");
    if (!/README\.zh-CN\.md/.test(en)) error("README.md", "顶部缺少指向 README.zh-CN.md 的语言切换链接");
    if (!/Strbit\/Tailscale-native-magisk/.test(en)) warn("README.md", "缺少 fork 仓库说明");
    if (!/Iridule\/Tailscale-native-magisk/.test(en)) warn("README.md", "缺少上游来源说明");
  }

  if (exists("module/README.txt")) {
    const txt = readText("module/README.txt");
    if (!hasCJK(txt)) error("module/README.txt", "未包含中文");
    if (!/ENGLISH/i.test(txt)) warn("module/README.txt", "缺少 ENGLISH 段落（契约要求中英双语）");
  }

  if (exists("CHANGELOG.md")) {
    const log = readText("CHANGELOG.md");
    if (!new RegExp(EXPECTED.version.replace(/\./g, "\\.")).test(log)) {
      error("CHANGELOG.md", `缺少 ${EXPECTED.version} 条目`);
    }
  } else {
    error("CHANGELOG.md", "文件不存在");
  }

  if (exists("RELEASE_NOTES.md")) {
    const notes = readText("RELEASE_NOTES.md");
    if (!notes.includes(EXPECTED.tag)) error("RELEASE_NOTES.md", `未提及版本 ${EXPECTED.tag}`);
  } else {
    error("RELEASE_NOTES.md", "文件不存在");
  }

  if (exists(".github/workflows/release.yml")) {
    const wf = readText(".github/workflows/release.yml");
    if (!wf.includes(EXPECTED.tag)) error(".github/workflows/release.yml", `未更新到 ${EXPECTED.tag}`);
    if (!wf.includes(EXPECTED.zipName)) error(".github/workflows/release.yml", `未引用新 ZIP 名 ${EXPECTED.zipName}`);
  }
  pass("docs", "文档与工作流已对齐");
}

/* ------------------------------------------------------------------ */
/* 6. Release ZIP                                                      */
/* ------------------------------------------------------------------ */

function readZipEntries(relPath) {
  const buf = readBytes(relPath);
  // EOCD
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65558); i -= 1) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error("找不到 ZIP EOCD 记录");
  const count = buf.readUInt16LE(eocd + 10);
  let offset = buf.readUInt32LE(eocd + 16);
  const entries = [];
  for (let i = 0; i < count; i += 1) {
    if (buf.readUInt32LE(offset) !== 0x02014b50) throw new Error("ZIP 中央目录损坏");
    const method = buf.readUInt16LE(offset + 10);
    const crc = buf.readUInt32LE(offset + 16);
    const compSize = buf.readUInt32LE(offset + 20);
    const rawSize = buf.readUInt32LE(offset + 24);
    const nameLen = buf.readUInt16LE(offset + 28);
    const extraLen = buf.readUInt16LE(offset + 30);
    const commentLen = buf.readUInt16LE(offset + 32);
    const localOffset = buf.readUInt32LE(offset + 42);
    const name = buf.toString("utf8", offset + 46, offset + 46 + nameLen);
    entries.push({ name, method, crc, compSize, rawSize, localOffset });
    offset += 46 + nameLen + extraLen + commentLen;
  }
  return { buf, entries };
}

function readZipEntryData(buf, entry) {
  const local = entry.localOffset;
  if (buf.readUInt32LE(local) !== 0x04034b50) throw new Error(`本地头损坏：${entry.name}`);
  const nameLen = buf.readUInt16LE(local + 26);
  const extraLen = buf.readUInt16LE(local + 28);
  const dataStart = local + 30 + nameLen + extraLen;
  const raw = buf.subarray(dataStart, dataStart + entry.compSize);
  if (entry.method === 0) return raw;
  if (entry.method === 8) return zlib.inflateRawSync(raw);
  throw new Error(`不支持的压缩方法 ${entry.method}：${entry.name}`);
}

function checkRelease() {
  if (!exists("SHA256SUMS")) {
    error("SHA256SUMS", "文件不存在");
    return;
  }
  const sumsText = readText("SHA256SUMS");
  const sums = new Map();
  for (const line of sumsText.split("\n")) {
    const m = /^([0-9a-f]{64})\s{2}(\S+)$/.exec(line.trim());
    if (m) sums.set(m[2], m[1]);
  }
  const zipRel = `release/${EXPECTED.zipName}`;
  if (!exists(zipRel)) {
    error("release/", `缺少 ${EXPECTED.zipName}（尚未构建则忽略此项）`);
    return;
  }

  const actual = sha256(zipRel);
  const recorded = sums.get(zipRel);
  if (!recorded) error("SHA256SUMS", `缺少 ${zipRel} 的校验行`);
  else if (recorded !== actual) error("SHA256SUMS", `${EXPECTED.zipName} 校验不符：记录 ${recorded.slice(0, 12)}… 实际 ${actual.slice(0, 12)}…`);

  const required = [
    "module.prop", "customize.sh", "service.sh", "action.sh", "common.sh",
    "i18n.sh", "watchdog.sh", "webui.sh", "uninstall.sh", "README.txt", "skip_mount",
    "upstream_commit", "bin/.placeholder", "webroot/index.html", "webroot/app.js",
    "webroot/i18n.js", "webroot/styles.css",
  ];
  let entries;
  try {
    entries = readZipEntries(zipRel);
  } catch (e) {
    error("release/", `ZIP 解析失败：${e.message}`);
    return;
  }
  const names = new Set(entries.entries.map((e) => e.name));
  for (const need of required) {
    if (!names.has(need) && !names.has(need.replace("/.placeholder", "/"))) {
      error("release/", `ZIP 缺少 ${need}`);
    }
  }
  for (const name of names) {
    if (/^\.git|^release\/|^tools\/|README\.zh-CN\.md$|\.bak$/.test(name)) {
      error("release/", `ZIP 不应包含 ${name}`);
    }
  }
  if (!names.has("module.prop")) error("release/", "module.prop 必须位于 ZIP 根目录（当前存在多余顶层目录？）");

  // ZIP 内 .sh 必须是 LF
  for (const entry of entries.entries) {
    if (entry.name.endsWith("/")) continue;
    if (!/\.(sh|prop|txt|js|html|css)$/.test(entry.name)) continue;
    let data;
    try {
      data = readZipEntryData(entries.buf, entry);
    } catch (e) {
      error("release/", `解压失败 ${entry.name}：${e.message}`);
      continue;
    }
    if (data.length >= 3 && data[0] === 0xef && data[1] === 0xbb && data[2] === 0xbf) {
      error("release/", `${entry.name} 含 BOM`);
    }
    let crlf = 0;
    for (let i = 0; i < data.length; i += 1) {
      if (data[i] === 0x0a && i > 0 && data[i - 1] === 0x0d) crlf += 1;
    }
    if (crlf > 0) error("release/", `${entry.name} 在 ZIP 内含 CRLF ${crlf} 处`);
  }

  // ZIP 内文件应与工作区一致（防止打包遗漏修改）
  for (const entry of entries.entries) {
    if (entry.name.endsWith("/")) continue;
    const srcRel = `module/${entry.name}`;
    if (!exists(srcRel)) continue;
    try {
      const zipped = readZipEntryData(entries.buf, entry);
      const source = readBytes(srcRel);
      if (!zipped.equals(source)) error("release/", `${entry.name} 与 module/ 中源文件不一致（ZIP 过期？）`);
    } catch {
      /* 已在上面报告 */
    }
  }

  pass("release", `${EXPECTED.zipName} 结构/校验/编码通过（sha256 ${actual.slice(0, 12)}…）`);
}

/* ------------------------------------------------------------------ */
/* 7. 打包脚本存在性（可选）                                            */
/* ------------------------------------------------------------------ */

/* ------------------------------------------------------------------ */
/* 执行                                                                */
/* ------------------------------------------------------------------ */

area("text", "编码", checkTextEncoding);
area("web", "Web 层", checkWeb);
area("shell", "Shell 层", checkShell);
area("meta", "元数据", checkMeta);
area("docs", "文档", checkDocs);
area("release", "Release", checkRelease);

const filtered = only ? results.filter((r) => only.has(r.area)) : results;
const errors = filtered.filter((r) => r.level === "error");
const warns = filtered.filter((r) => r.level === "warn");
const oks = filtered.filter((r) => r.level === "ok");

const ORDER = ["text", "web", "shell", "meta", "docs", "release"];
const grouped = new Map();
for (const r of filtered) {
  if (!grouped.has(r.area)) grouped.set(r.area, []);
  grouped.get(r.area).push(r);
}

console.log("=== check-i18n ===");
for (const [a, items] of grouped) {
  const e = items.filter((i) => i.level === "error").length;
  const w = items.filter((i) => i.level === "warn").length;
  console.log(`\n[${a}] ${e === 0 ? "PASS" : "FAIL"}  error=${e} warn=${w}`);
  for (const item of items) {
    if (item.level === "ok" && !verbose) continue;
    const badge = item.level === "error" ? "ERROR" : item.level === "warn" ? "WARN " : "ok   ";
    console.log(`  ${badge} ${item.scope}: ${item.message}`);
  }
}
const filteredAreas = ORDER.filter((a) => !only || only.has(a));
for (const a of filteredAreas) if (!grouped.has(a)) console.log(`\n[${a}] SKIP（无结果）`);

console.log(
  `\n合计：error=${errors.length} warn=${warns.length} pass=${oks.length}` +
    (only ? `（仅 ${[...only].join(",")}）` : "")
);
process.exit(errors.length > 0 ? 1 : 0);
