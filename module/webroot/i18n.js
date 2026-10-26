/*
 * i18n.js — Native Tailscale TUN 仪表盘双语词典与本地化 API
 *
 * 依据 I18N-CONTRACT.md v1 第 1、2 节：
 *   - 支持语言：en（默认回退）/ zh-CN，顺序固定。
 *   - 语言判定优先级：localStorage 缓存（root 侧 ui-language 文件的即时镜像）
 *     → 系统语言（navigator）→ en。WebView 存储可能被清空，所以 app.js 必须以
 *     helper `status` 返回的 ui_language 为最终权威值。
 *   - 顶层不得访问 document / navigator / localStorage：本文件在无 DOM 的沙箱中
 *     也会被 eval 校验，所有宿主对象访问都发生在函数体内并带存在性判断。
 *
 * 纯静态资源，无模块语法，通过 IIFE 挂载 window.I18N。
 */
(function (root) {
  "use strict";

  var STORAGE_KEY = "native-ts-lang";
  var SUPPORTED = ["en", "zh-CN"];

  var dict = {
    en: {
      /* 应用外壳 */
      "app.title": "Native Tailscale",
      "app.eyebrow": "MAGISK // KSUWEBUI",
      "app.chip": "NATIVE BINARY",
      "footer.system": "SYSTEM LOCAL // MAGISK + KSUWEBUISTANDALONE",

      /* 顶部栏 */
      "header.refresh": "Refresh status",
      "header.language": "Switch language",
      "header.language_target_en": "EN",
      "header.language_target_zh": "中文",

      /* 连接状态 */
      "status.network": "NETWORK STATUS",
      "status.loading": "Loading…",
      "status.checking_daemon": "Checking the native daemon",
      "status.no_ip": "No Tailscale IP assigned",
      "status.daemon_stopped": "Native daemon is stopped",
      "status.not_running": "Not running",

      /* tailscaled BackendState 显示映射（逻辑仍比对英文原值） */
      "state.Running": "Running",
      "state.Stopped": "Stopped",
      "state.Starting": "Starting",
      "state.NeedsLogin": "NeedsLogin",
      "state.NoState": "NoState",
      "state.NeedsMachineAuth": "NeedsMachineAuth",
      "state.Unavailable": "Unavailable",

      /* 二进制完整性 */
      "integrity.title": "System integrity",
      "integrity.subtitle": "Installed binary verification",
      "integrity.commit": "Upstream source revision",
      "integrity.version": "Tailscale version",
      "integrity.module_version": "Module version",
      "integrity.pid": "Daemon PID",
      "integrity.verify": "Verify binaries",
      "integrity.update": "Update Tailscale",
      "integrity.verified": "verified",
      "integrity.modified": "modified",
      "integrity.recorded": "recorded",
      "integrity.unrecorded": "unrecorded",
      "integrity.unknown": "unknown",
      "integrity.checking": "Checking",

      /* TUN 接口状态 */
      "interface.up": "UP",
      "interface.down": "DOWN",

      /* 配置项 */
      "config.title": "Configuration flags",
      "config.subtitle": "Applied safely through <code>tailscale set</code>",
      "config.accept_routes": "Accept subnet routes",
      "config.accept_routes_hint": "Use routes advertised by other nodes",
      "config.shields_up": "Shields up",
      "config.shields_up_hint": "Block incoming tailnet connections",
      "config.hostname": "Device hostname",
      "config.hostname_hint": "Letters, numbers, dots, and hyphens",
      "config.hostname_placeholder": "my-phone",
      "config.save": "Save",

      /* 守护进程控制 */
      "daemon.title": "Daemon controls",
      "daemon.subtitle": "Manage the root-native service",

      /* 操作标题（按钮 / 忙碌遮罩 / 结果弹窗共用） */
      "action.start": "Start",
      "action.restart": "Restart",
      "action.stop": "Stop",
      "action.sign_in": "Sign in",
      "action.signed_in": "Signed in",
      "action.restoring": "Restoring",
      "action.tailnet_admin": "Tailnet admin",
      "action.logs_title": "Logs and diagnostics",
      "action.logs_hint": "Historical activity—not current login state",
      "action.refresh_logs": "Refresh logs",
      "action.clear_log": "Clear log",
      "action.run_diagnostics": "Run diagnostics",
      "action.diagnostics": "Diagnostics",
      "action.starting_service": "Starting service",
      "action.stopping_service": "Stopping service",
      "action.restarting_service": "Restarting service",
      "action.tailscale_signin": "Tailscale sign in",
      "action.verifying_binaries": "Verifying binaries",
      "action.updating_binaries": "Updating Tailscale binaries",
      "action.opening_admin": "Opening Tailnet Admin",
      "action.clearing_log": "Clearing daemon log",
      "action.updating_hostname": "Updating hostname",

      /* 日志面板 */
      "logs.open_hint": "Open this section to load logs.",
      "logs.empty": "No log entries yet.",

      /* 忙碌遮罩 */
      "busy.working": "Working…",

      /* 结果弹窗 */
      "dialog.result": "Result",
      "dialog.close": "Close result",
      "dialog.completed": "Completed successfully.",
      "dialog.failed": "{name} failed",
      "dialog.updating": "Updating {name}",
      "dialog.invalid_hostname": "Invalid hostname",
      "dialog.hostname_hint": "Use 1–63 letters, numbers, dots, or hyphens. Do not begin or end with punctuation.",
      "dialog.login_instructions": "Open the authentication page, finish signing in, then return here.",
      "dialog.open_login": "Open Tailscale sign-in",
      "dialog.auth_url": "Authentication URL — tap and hold to copy",

      /* 提示条 */
      "alert.official_vpn": "The official Tailscale Android VPN is active. Disconnect it before starting the native daemon.",
      "alert.integrity_modified": "Binary integrity check failed. Updates are blocked until the installation is reviewed.",
      "alert.restoring_session": "Restoring the saved Tailscale session…",
      "alert.needs_login": "This device needs authentication. Tap Sign in to open the Tailscale authentication page.",

      /* 通信错误 */
      "error.bridge_unavailable": "KsuWebUIStandalone bridge is unavailable.",
      "error.timeout": "The root command timed out.",
      "error.command_failed": "Command failed ({code}).",
    },

    "zh-CN": {
      /* 应用外壳 */
      "app.title": "原生 Tailscale",
      "app.eyebrow": "MAGISK // KSUWEBUI 控制台",
      "app.chip": "原生二进制",
      "footer.system": "本地系统 // MAGISK + KSUWEBUISTANDALONE",

      /* 顶部栏 */
      "header.refresh": "刷新状态",
      "header.language": "切换语言",
      "header.language_target_en": "EN",
      "header.language_target_zh": "中文",

      /* 连接状态 */
      "status.network": "网络状态",
      "status.loading": "加载中…",
      "status.checking_daemon": "正在检查原生守护进程",
      "status.no_ip": "尚未分配 Tailscale IP",
      "status.daemon_stopped": "原生守护进程已停止",
      "status.not_running": "未运行",

      /* tailscaled BackendState 显示映射（逻辑仍比对英文原值） */
      "state.Running": "运行中",
      "state.Stopped": "已停止",
      "state.Starting": "启动中",
      "state.NeedsLogin": "需要登录",
      "state.NoState": "无状态",
      "state.NeedsMachineAuth": "等待管理员授权",
      "state.Unavailable": "不可用",

      /* 二进制完整性 */
      "integrity.title": "系统完整性",
      "integrity.subtitle": "已安装二进制校验",
      "integrity.commit": "上游源码修订",
      "integrity.version": "Tailscale 版本",
      "integrity.module_version": "模块版本",
      "integrity.pid": "守护进程 PID",
      "integrity.verify": "校验二进制",
      "integrity.update": "更新 Tailscale",
      "integrity.verified": "已校验",
      "integrity.modified": "已修改",
      "integrity.recorded": "已记录",
      "integrity.unrecorded": "未记录",
      "integrity.unknown": "未知",
      "integrity.checking": "检查中",

      /* TUN 接口状态 */
      "interface.up": "已启用",
      "interface.down": "已停用",

      /* 配置项 */
      "config.title": "配置项",
      "config.subtitle": "通过 <code>tailscale set</code> 安全应用",
      "config.accept_routes": "接受子网路由",
      "config.accept_routes_hint": "使用其他节点通告的路由",
      "config.shields_up": "屏蔽入站连接",
      "config.shields_up_hint": "阻止来自 tailnet 的入站连接",
      "config.hostname": "设备主机名",
      "config.hostname_hint": "可含字母、数字、点和连字符",
      "config.hostname_placeholder": "例如：my-phone",
      "config.save": "保存",

      /* 守护进程控制 */
      "daemon.title": "守护进程控制",
      "daemon.subtitle": "管理 root 原生服务",

      /* 操作标题（按钮 / 忙碌遮罩 / 结果弹窗共用） */
      "action.start": "启动",
      "action.restart": "重启",
      "action.stop": "停止",
      "action.sign_in": "登录",
      "action.signed_in": "已登录",
      "action.restoring": "恢复中",
      "action.tailnet_admin": "Tailnet 管理",
      "action.logs_title": "日志与诊断",
      "action.logs_hint": "历史活动记录，不代表当前登录状态",
      "action.refresh_logs": "刷新日志",
      "action.clear_log": "清空日志",
      "action.run_diagnostics": "运行诊断",
      "action.diagnostics": "诊断",
      "action.starting_service": "启动服务",
      "action.stopping_service": "停止服务",
      "action.restarting_service": "重启服务",
      "action.tailscale_signin": "Tailscale 登录",
      "action.verifying_binaries": "校验二进制",
      "action.updating_binaries": "更新 Tailscale 二进制",
      "action.opening_admin": "打开 Tailnet 管理",
      "action.clearing_log": "清空守护进程日志",
      "action.updating_hostname": "更新主机名",

      /* 日志面板 */
      "logs.open_hint": "展开此栏以加载日志。",
      "logs.empty": "暂无日志记录。",

      /* 忙碌遮罩 */
      "busy.working": "处理中…",

      /* 结果弹窗 */
      "dialog.result": "执行结果",
      "dialog.close": "关闭结果",
      "dialog.completed": "操作已成功完成。",
      "dialog.failed": "{name}失败",
      "dialog.updating": "更新{name}",
      "dialog.invalid_hostname": "主机名无效",
      "dialog.hostname_hint": "请使用 1–63 个字母、数字、点或连字符，且不要以标点符号开头或结尾。",
      "dialog.login_instructions": "请打开认证页面完成登录，然后返回此页。",
      "dialog.open_login": "打开 Tailscale 登录页面",
      "dialog.auth_url": "认证链接：长按复制",

      /* 提示条 */
      "alert.official_vpn": "官方 Tailscale Android VPN 正在运行，请先断开后再启动原生守护进程。",
      "alert.integrity_modified": "二进制完整性校验未通过，在确认安装内容之前更新会被阻止。",
      "alert.restoring_session": "正在恢复已保存的 Tailscale 会话…",
      "alert.needs_login": "此设备需要认证。点击「登录」打开 Tailscale 认证页面。",

      /* 通信错误 */
      "error.bridge_unavailable": "KsuWebUIStandalone 桥接不可用。",
      "error.timeout": "root 命令执行超时。",
      "error.command_failed": "命令执行失败（{code}）。",
    },
  };

  /* ------------------------------------------------------------------ */
  /* 宿主对象访问（全部延迟到函数体内，且带存在性判断）                  */
  /* ------------------------------------------------------------------ */

  function doc() {
    return typeof document !== "undefined" && document ? document : null;
  }

  function storage() {
    try {
      if (typeof localStorage !== "undefined" && localStorage) return localStorage;
    } catch (e) {
      /* WebView 禁用存储时静默降级 */
    }
    return null;
  }

  /* 语言代码归一化：zh / zh-cn / zh_CN / zh-Hans / zh-CN-x → zh-CN；en-US → en。 */
  function normalize(lang) {
    var value = String(lang === null || lang === undefined ? "" : lang)
      .trim()
      .toLowerCase()
      .replace(/_/g, "-");
    if (!value) return null;
    if (value === "en" || value.indexOf("en-") === 0) return "en";
    if (value === "zh" || value.indexOf("zh-") === 0) return "zh-CN";
    return null;
  }

  var current = "en";

  /* 查表 → 回退 en → 最后返回 key 本身；params 用于 {name} 插值。 */
  function t(key, params) {
    var name = String(key === null || key === undefined ? "" : key);
    var table = dict[current];
    var value = table && typeof table[name] === "string" ? table[name] : null;
    if (value === null) {
      value = typeof dict.en[name] === "string" ? dict.en[name] : name;
    }
    if (params && typeof params === "object") {
      value = value.replace(/\{([A-Za-z0-9_]+)\}/g, function (match, token) {
        var replacement = params[token];
        return replacement === undefined || replacement === null ? match : String(replacement);
      });
    }
    return value;
  }

  function resolveRoot(target) {
    if (target && typeof target.querySelectorAll === "function") return target;
    var d = doc();
    if (d && typeof d.querySelectorAll === "function") return d;
    return null;
  }

  /* 翻译 root（默认 document）下所有 data-i18n* 元素，返回处理数量。 */
  function apply(target) {
    var scope = resolveRoot(target);
    if (!scope) return 0;
    var nodes = scope.querySelectorAll(
      "[data-i18n],[data-i18n-html],[data-i18n-placeholder],[data-i18n-aria],[data-i18n-title]"
    );
    var applied = 0;
    for (var i = 0; i < nodes.length; i += 1) {
      var node = nodes[i];
      if (!node || typeof node.getAttribute !== "function") continue;

      var key = node.getAttribute("data-i18n");
      if (key) {
        node.textContent = t(key);
        applied += 1;
      }
      key = node.getAttribute("data-i18n-html");
      if (key) {
        node.innerHTML = t(key);
        applied += 1;
      }
      key = node.getAttribute("data-i18n-placeholder");
      if (key) {
        node.setAttribute("placeholder", t(key));
        applied += 1;
      }
      key = node.getAttribute("data-i18n-aria");
      if (key) {
        node.setAttribute("aria-label", t(key));
        applied += 1;
      }
      key = node.getAttribute("data-i18n-title");
      if (key) {
        node.setAttribute("title", t(key));
        applied += 1;
      }
    }
    return applied;
  }

  /*
   * 切换语言：opts.persist !== false 时写入 localStorage。
   * 同步 <html lang>、翻译静态区域并派发 i18n:change，返回生效语言。
   */
  function setLang(lang, opts) {
    var requested = normalize(lang);
    current = requested || current;

    var options = opts || {};
    if (options.persist !== false) {
      var store = storage();
      if (store) {
        try {
          store.setItem(STORAGE_KEY, current);
        } catch (e) {
          /* 存储不可写时不影响界面切换 */
        }
      }
    }

    var d = doc();
    if (d) {
      if (d.documentElement) d.documentElement.lang = current;
      apply(d);
      try {
        if (typeof CustomEvent === "function" && typeof d.dispatchEvent === "function") {
          d.dispatchEvent(new CustomEvent("i18n:change", { detail: { lang: current } }));
        }
      } catch (e) {
        /* 极旧 WebView 不支持 CustomEvent 构造器时忽略事件 */
      }
    }
    return current;
  }

  /* 按契约第 1 节顺序判定语言。 */
  function detectLanguage() {
    var store = storage();
    if (store && typeof store.getItem === "function") {
      var cached = normalize(store.getItem(STORAGE_KEY));
      if (cached) return cached;
    }

    try {
      if (typeof navigator !== "undefined" && navigator) {
        var list = navigator.languages && navigator.languages.length
          ? navigator.languages
          : [navigator.language];
        for (var i = 0; i < list.length; i += 1) {
          var detected = normalize(list[i]);
          if (detected) return detected;
        }
      }
    } catch (e) {
      /* 缺少 navigator 时回退 en */
    }
    return "en";
  }

  function init() {
    var lang = setLang(detectLanguage(), { persist: false });
    apply(doc());
    return lang;
  }

  var api = {
    supported: SUPPORTED,
    dict: dict,
    get lang() {
      return current;
    },
    t: t,
    setLang: setLang,
    detectLanguage: detectLanguage,
    apply: apply,
    init: init,
    normalize: normalize,
  };

  root.I18N = api;
})(
  typeof window !== "undefined"
    ? window
    : typeof globalThis !== "undefined"
    ? globalThis
    : this
);
