#!/system/bin/sh
#
# Native Tailscale TUN - shell 层双语文本表。
#
# 自包含：不引用其它模块脚本，不创建目录，加载本文件不产生任何副作用。
# 运行环境是 Android mksh（/system/bin/sh），只使用 printf / getprop / tr 等自带命令。
#
# 语言判定顺序（见 I18N-CONTRACT.md 第 1 节）：
#   1. $I18N_LANG_FILE 内容合法 -> 使用之；
#   2. 否则看系统语言 persist.sys.locale / ro.product.locale / ro.product.locale.language；
#   3. 否则 en。
# I18N_LANG_FILE 可用环境变量覆盖，便于测试。
#
# 字典条目格式固定为单行：
#        key.name) printf '%s' "文本" ;;
# 值用双引号包裹，值内不得出现 " 与 '，% 只允许成对的 %s（en/zh 个数必须一致）。

I18N_LANG_FILE=${I18N_LANG_FILE:-/data/adb/tailscale-native/ui-language}

# 归一化任意语言标记：en / en-US -> en；zh / zh_CN / zh-Hans / zh-CN-x -> zh-CN。
i18n_normalize() {
    case "${1:-}" in
        en|en[-_]*) printf '%s\n' en ;;
        zh|zh[-_]*) printf '%s\n' zh-CN ;;
        *) return 1 ;;
    esac
}

# 输出当前生效语言：en 或 zh-CN。同时把结果留在 I18N_ACTIVE_LANG 里，
# 供同一 shell 内的 msg / msgf 复用（避免每次重新探测）。
i18n_lang() {
    I18N_ACTIVE_LANG=""
    if [ -r "$I18N_LANG_FILE" ]; then
        I18N_FILE_VALUE="$(tr -d '\r\n ' < "$I18N_LANG_FILE" 2>/dev/null)"
        if [ -n "$I18N_FILE_VALUE" ]; then
            if I18N_FROM_FILE="$(i18n_normalize "$I18N_FILE_VALUE")"; then
                I18N_ACTIVE_LANG="$I18N_FROM_FILE"
            fi
        fi
    fi

    if [ -z "$I18N_ACTIVE_LANG" ]; then
        for I18N_PROP_NAME in \
            persist.sys.locale \
            ro.product.locale \
            ro.product.locale.language
        do
            I18N_PROP_VALUE="$(getprop "$I18N_PROP_NAME" 2>/dev/null)"
            if I18N_FROM_PROP="$(i18n_normalize "$I18N_PROP_VALUE")"; then
                I18N_ACTIVE_LANG="$I18N_FROM_PROP"
                break
            fi
        done
    fi

    [ -n "$I18N_ACTIVE_LANG" ] || I18N_ACTIVE_LANG=en
    printf '%s\n' "$I18N_ACTIVE_LANG"
}

# 合法参数为 en 或 zh-CN：原子写入语言文件并返回 0；否则返回 1，不写任何文件。
i18n_set_lang() {
    case "${1:-}" in
        en|zh-CN) ;;
        *) return 1 ;;
    esac

    I18N_SET_DIR="${I18N_LANG_FILE%/*}"
    [ "$I18N_SET_DIR" = "$I18N_LANG_FILE" ] && I18N_SET_DIR=.
    [ -d "$I18N_SET_DIR" ] || return 1

    I18N_SET_TMP="$I18N_LANG_FILE.tmp.$$"
    if printf '%s\n' "$1" > "$I18N_SET_TMP" 2>/dev/null; then
        if mv -f "$I18N_SET_TMP" "$I18N_LANG_FILE" 2>/dev/null; then
            I18N_ACTIVE_LANG="$1"
            return 0
        fi
    fi
    rm -f "$I18N_SET_TMP" 2>/dev/null
    return 1
}

# 英文词典（默认语言，也是缺 key 时的回退来源）。
i18n_text_en() {
    case "$1" in
        common.unknown) printf '%s' "unknown" ;;
        lang.saved) printf '%s' "Interface language saved." ;;
        error.lang_invalid) printf '%s' "ERROR: Unsupported language. Use en or zh-CN." ;;
        error.lang_save) printf '%s' "ERROR: Could not save the interface language." ;;
        error.not_running) printf '%s' "ERROR: Native tailscaled is not running." ;;
        error.setting_value) printf '%s' "ERROR: Invalid setting value." ;;
        error.unknown_setting) printf '%s' "ERROR: Unknown setting." ;;
        error.hostname_length) printf '%s' "ERROR: Hostname must be 63 characters or fewer." ;;
        error.hostname_chars) printf '%s' "ERROR: Use only letters, numbers, dots, and hyphens." ;;
        error.official_vpn) printf '%s' "ERROR: Disconnect the official Tailscale Android app first." ;;
        daemon.started) printf '%s' "Native tailscaled started." ;;
        daemon.stopped) printf '%s' "Native tailscaled stopped." ;;
        daemon.restarted) printf '%s' "Native tailscaled restarted." ;;
        login.complete_hint) printf '%s' "Complete authentication in the sign-in page, then return to the dashboard." ;;
        login.already_signed_in) printf '%s' "This device is already signed in." ;;
        login.url_pending) printf '%s' "The sign-in URL is not ready yet. Tap Sign in again in a few seconds." ;;
        logs.empty) printf '%s' "No log entries yet." ;;
        logs.cleared) printf '%s' "Daemon log cleared." ;;
        diag.dns_title) printf '%s' "Android DNS note" ;;
        diag.dns_body_1) printf '%s' "The native Android build cannot read or replace the Android base DNS configuration through the Tailscale OS DNS configurator." ;;
        diag.dns_body_2) printf '%s' "This module keeps accept-dns disabled because it cannot provide system-wide MagicDNS." ;;
        diag.dns_body_3) printf '%s' "If an older or manual configuration enabled it, the low-severity warning that says getting OS base config is not supported does not mean TUN or tailnet IP routing failed." ;;
        diag.dns_body_4) printf '%s' "The native daemon continues using the existing Android DNS configuration." ;;
        diag.raw_status) printf '%s' "Raw Tailscale status" ;;
        verify.ok) printf '%s' "Installed binaries match their recorded SHA-256 hashes." ;;
        verify.failed) printf '%s' "ERROR: An installed binary does not match its recorded SHA-256 hash." ;;
        admin.opened) printf '%s' "Opened the Tailscale Machines page in your browser." ;;
        admin.failed) printf '%s' "ERROR: No browser could open the Tailscale admin console." ;;
        usage) printf '%s' "Usage: %s {status|logs|clear-logs|diagnostics|start|stop|restart|login|verify|binary-update|open-admin|set|set-language}" ;;
        action.webui_required) printf '%s' "KsuWebUIStandalone is required to open this module dashboard." ;;
        action.webui_install_hint) printf '%s' "Install it, then tap Action again." ;;
        action.webui_url) printf '%s' "Download: %s" ;;
        action.opening) printf '%s' "Opening Native Tailscale dashboard..." ;;
        action.starting_daemon) printf '%s' "Native tailscaled is not running; starting it..." ;;
        action.needs_auth_1) printf '%s' "This device is signed in but is waiting for an administrator to approve it." ;;
        action.needs_auth_2) printf '%s' "Approve it in the Tailscale admin console before updating binaries." ;;
        error.webui_open) printf '%s' "ERROR: KsuWebUIStandalone could not open the dashboard." ;;
        error.daemon_start) printf '%s' "ERROR: tailscaled did not start. Check %s" ;;
        error.signin_required) printf '%s' "ERROR: Sign in from the dashboard before updating Tailscale binaries." ;;
        error.status_unread) printf '%s' "ERROR: Could not read tailscaled status. Check %s" ;;
        summary.title) printf '%s' "Connection summary" ;;
        summary.state) printf '%s' "State: %s" ;;
        summary.state_unknown) printf '%s' "State: unknown" ;;
        summary.ip) printf '%s' "Tailscale IP: %s" ;;
        summary.ip_unassigned) printf '%s' "Tailscale IP: not assigned" ;;
        summary.device) printf '%s' "Device: %s" ;;
        summary.tun) printf '%s' "TUN interface: %s" ;;
        summary.active) printf '%s' "Tailnet routing is active." ;;
        update.title) printf '%s' "Native Tailscale updater" ;;
        error.hash_mismatch) printf '%s' "ERROR: Installed binaries do not match their recorded SHA-256 hashes." ;;
        update.reinstall_hint) printf '%s' "Reinstall the module or review the files before attempting an update." ;;
        update.installed_version) printf '%s' "Installed Tailscale: %s" ;;
        error.commit_download) printf '%s' "ERROR: Could not download the upstream commit marker." ;;
        error.commit_invalid) printf '%s' "ERROR: Invalid upstream commit marker." ;;
        update.installed_commit) printf '%s' "Installed source commit: %s" ;;
        update.upstream_commit) printf '%s' "Upstream source commit: %s" ;;
        update.up_to_date) printf '%s' "Already current." ;;
        update.downloading) printf '%s' "Downloading new ARM64 binaries..." ;;
        error.download_tailscale) printf '%s' "ERROR: tailscale download failed." ;;
        error.download_tailscaled) printf '%s' "ERROR: tailscaled download failed." ;;
        error.commit_recheck) printf '%s' "ERROR: Could not recheck the upstream commit marker." ;;
        error.commit_invalid_after) printf '%s' "ERROR: Invalid upstream commit marker after download." ;;
        error.upstream_changed) printf '%s' "ERROR: Upstream changed during download. Run Update Tailscale again." ;;
        error.not_elf) printf '%s' "ERROR: A downloaded file is not an ELF executable." ;;
        error.daemon_not_execute) printf '%s' "ERROR: The downloaded daemon did not execute." ;;
        update.downloaded_version) printf '%s' "Downloaded Tailscale: %s" ;;
        error.record_hashes) printf '%s' "ERROR: Could not record the downloaded binary hashes." ;;
        update.success) printf '%s' "Updated successfully." ;;
        update.not_started_official_vpn) printf '%s' "Native daemon was not started because the official Android Tailscale VPN is active." ;;
        update.success_restarted) printf '%s' "Update succeeded and tailscaled restarted." ;;
        update.rolling_back) printf '%s' "New daemon failed to start; rolling back." ;;
        update.rollback_done) printf '%s' "Rollback complete. Check %s" ;;
        install.header) printf '%s' " Native Tailscale TUN module" ;;
        install.arm64_only) printf '%s' "This package currently supports ARM64 only." ;;
        install.fetching) printf '%s' "Fetching current patched binaries" ;;
        install.upstream_changed) printf '%s' "Upstream changed during download; discarding the download" ;;
        install.download_failed) printf '%s' "Download failed; looking for your existing tested binaries" ;;
        install.reused_binaries) printf '%s' "Reused binaries from %s" ;;
        install.abort_no_binaries) printf '%s' "Could not download or locate existing Tailscale binaries." ;;
        install.abort_cd) printf '%s' "Could not enter the module directory." ;;
        install.abort_hashes) printf '%s' "Could not record binary SHA-256 hashes." ;;
        install.abort_tailscale_elf) printf '%s' "tailscale is not a valid ELF executable." ;;
        install.abort_tailscaled_elf) printf '%s' "tailscaled is not a valid ELF executable." ;;
        install.abort_exec) printf '%s' "tailscaled could not execute on this device." ;;
        install.installed_version) printf '%s' "Installed Tailscale %s" ;;
        install.moved_legacy) printf '%s' "Moved old standalone launcher outside service.d" ;;
        install.state_path) printf '%s' "Your state remains at /data/adb/tailscale-native" ;;
        install.keep_official_off) printf '%s' "Keep the official Tailscale app disconnected" ;;
        install.reboot) printf '%s' "Reboot after installation" ;;
        install.install_webui) printf '%s' "Install KsuWebUIStandalone if needed" ;;
        install.action_hint) printf '%s' "After reboot, tap Action to open the dashboard and sign in there" ;;
        install.update_hint) printf '%s' "Use Update Tailscale in the dashboard for manual binary updates" ;;
        service.official_vpn_active) printf '%s' "official Tailscale Android VPN is active; native daemon not started" ;;
        service.start_failed) printf '%s' "failed to start native tailscaled" ;;
        service.started) printf '%s' "native tailscaled started" ;;
        service.hostname_checked) printf '%s' "device hostname preference checked" ;;
        service.auth_required) printf '%s' "authentication required; sign in from the Native Tailscale dashboard" ;;
        *) return 1 ;;
    esac
}

# 简体中文词典。安装器/日志类词条保留英文括注，便于 recovery 缺中文字体时辨认。
i18n_text_zh() {
    case "$1" in
        common.unknown) printf '%s' "未知" ;;
        lang.saved) printf '%s' "界面语言已保存。" ;;
        error.lang_invalid) printf '%s' "错误：不支持的语言，请使用 en 或 zh-CN。" ;;
        error.lang_save) printf '%s' "错误：无法保存界面语言。" ;;
        error.not_running) printf '%s' "错误：原生 tailscaled 未在运行。" ;;
        error.setting_value) printf '%s' "错误：设置值无效。" ;;
        error.unknown_setting) printf '%s' "错误：未知的设置项。" ;;
        error.hostname_length) printf '%s' "错误：主机名不得超过 63 个字符。" ;;
        error.hostname_chars) printf '%s' "错误：主机名只能包含字母、数字、点和连字符。" ;;
        error.official_vpn) printf '%s' "错误：请先断开官方 Tailscale Android 应用。" ;;
        daemon.started) printf '%s' "原生 tailscaled 已启动。" ;;
        daemon.stopped) printf '%s' "原生 tailscaled 已停止。" ;;
        daemon.restarted) printf '%s' "原生 tailscaled 已重启。" ;;
        login.complete_hint) printf '%s' "请在登录页面完成身份验证，然后返回仪表盘。" ;;
        login.already_signed_in) printf '%s' "此设备已登录。" ;;
        login.url_pending) printf '%s' "登录链接尚未就绪，请稍等几秒后再次点击登录。" ;;
        logs.empty) printf '%s' "暂无日志记录。" ;;
        logs.cleared) printf '%s' "守护进程日志已清空。" ;;
        diag.dns_title) printf '%s' "Android DNS 说明" ;;
        diag.dns_body_1) printf '%s' "原生 Android 版本无法通过 Tailscale 的系统 DNS 配置器读取或替换 Android 基础 DNS 配置。" ;;
        diag.dns_body_2) printf '%s' "本模块保持 accept-dns 关闭，因为它无法提供系统级 MagicDNS。" ;;
        diag.dns_body_3) printf '%s' "如果旧版本或手动配置将它开启，出现「getting OS base config is not supported」这类低危提示并不代表 TUN 或 tailnet IP 路由失效。" ;;
        diag.dns_body_4) printf '%s' "原生守护进程会继续沿用 Android 现有的 DNS 配置。" ;;
        diag.raw_status) printf '%s' "Tailscale 原始状态输出" ;;
        verify.ok) printf '%s' "已安装的二进制文件与记录的 SHA-256 哈希一致。" ;;
        verify.failed) printf '%s' "错误：已安装的二进制文件与记录的 SHA-256 哈希不一致。" ;;
        admin.opened) printf '%s' "已在浏览器中打开 Tailscale 机器管理页面。" ;;
        admin.failed) printf '%s' "错误：没有浏览器可以打开 Tailscale 管理控制台。" ;;
        usage) printf '%s' "用法：%s {status|logs|clear-logs|diagnostics|start|stop|restart|login|verify|binary-update|open-admin|set|set-language}" ;;
        action.webui_required) printf '%s' "打开本模块仪表盘需要安装 KsuWebUIStandalone。" ;;
        action.webui_install_hint) printf '%s' "请先安装，然后再次点击「操作」。" ;;
        action.webui_url) printf '%s' "下载地址：%s" ;;
        action.opening) printf '%s' "正在打开 Native Tailscale 仪表盘……" ;;
        action.starting_daemon) printf '%s' "原生 tailscaled 未在运行，正在启动……" ;;
        action.needs_auth_1) printf '%s' "此设备已登录，但正在等待管理员批准。" ;;
        action.needs_auth_2) printf '%s' "请先在 Tailscale 管理控制台批准，再更新二进制文件。" ;;
        error.webui_open) printf '%s' "错误：KsuWebUIStandalone 无法打开仪表盘。" ;;
        error.daemon_start) printf '%s' "错误：tailscaled 未能启动，请查看 %s" ;;
        error.signin_required) printf '%s' "错误：请先在仪表盘登录，再更新 Tailscale 二进制文件。" ;;
        error.status_unread) printf '%s' "错误：无法读取 tailscaled 状态，请查看 %s" ;;
        summary.title) printf '%s' "连接摘要" ;;
        summary.state) printf '%s' "状态：%s" ;;
        summary.state_unknown) printf '%s' "状态：未知" ;;
        summary.ip) printf '%s' "Tailscale IP 地址：%s" ;;
        summary.ip_unassigned) printf '%s' "Tailscale IP：未分配" ;;
        summary.device) printf '%s' "设备：%s" ;;
        summary.tun) printf '%s' "TUN 接口：%s" ;;
        summary.active) printf '%s' "Tailnet 路由已生效。" ;;
        update.title) printf '%s' "Native Tailscale 更新程序" ;;
        error.hash_mismatch) printf '%s' "错误：已安装的二进制文件与记录的 SHA-256 哈希不一致。" ;;
        update.reinstall_hint) printf '%s' "请重装模块或先检查相关文件，再尝试更新。" ;;
        update.installed_version) printf '%s' "已安装的 Tailscale：%s" ;;
        error.commit_download) printf '%s' "错误：无法下载上游提交标记。" ;;
        error.commit_invalid) printf '%s' "错误：上游提交标记无效。" ;;
        update.installed_commit) printf '%s' "已安装源码提交：%s" ;;
        update.upstream_commit) printf '%s' "上游源码提交：%s" ;;
        update.up_to_date) printf '%s' "已是最新版本。" ;;
        update.downloading) printf '%s' "正在下载新的 ARM64 二进制文件……" ;;
        error.download_tailscale) printf '%s' "错误：tailscale 下载失败。" ;;
        error.download_tailscaled) printf '%s' "错误：tailscaled 下载失败。" ;;
        error.commit_recheck) printf '%s' "错误：无法重新校验上游提交标记。" ;;
        error.commit_invalid_after) printf '%s' "错误：下载完成后上游提交标记无效。" ;;
        error.upstream_changed) printf '%s' "错误：下载过程中上游发生变更，请重新执行「Update Tailscale」。" ;;
        error.not_elf) printf '%s' "错误：下载的文件不是有效的 ELF 可执行文件。" ;;
        error.daemon_not_execute) printf '%s' "错误：下载的守护进程无法执行。" ;;
        update.downloaded_version) printf '%s' "已下载的 Tailscale：%s" ;;
        error.record_hashes) printf '%s' "错误：无法记录下载的二进制文件哈希。" ;;
        update.success) printf '%s' "更新成功。" ;;
        update.not_started_official_vpn) printf '%s' "由于官方 Tailscale Android VPN 正在运行，原生守护进程未启动。" ;;
        update.success_restarted) printf '%s' "更新成功，tailscaled 已重启。" ;;
        update.rolling_back) printf '%s' "新守护进程启动失败，正在回滚。" ;;
        update.rollback_done) printf '%s' "回滚完成，请查看 %s" ;;
        install.header) printf '%s' " Native Tailscale TUN 模块 (Native Tailscale TUN module)" ;;
        install.arm64_only) printf '%s' "本安装包目前仅支持 ARM64 架构 (this package currently supports ARM64 only)" ;;
        install.fetching) printf '%s' "正在获取最新的补丁二进制文件 (fetching current patched binaries)" ;;
        install.upstream_changed) printf '%s' "下载过程中上游发生变更，已丢弃本次下载 (upstream changed during download; download discarded)" ;;
        install.download_failed) printf '%s' "下载失败，正在查找设备上已有的已验证二进制文件 (download failed; looking for existing tested binaries)" ;;
        install.reused_binaries) printf '%s' "已复用来自 %s 的二进制文件 (reused binaries)" ;;
        install.abort_no_binaries) printf '%s' "无法下载或找到已有的 Tailscale 二进制文件 (could not download or locate existing Tailscale binaries)" ;;
        install.abort_cd) printf '%s' "无法进入模块目录 (could not enter the module directory)" ;;
        install.abort_hashes) printf '%s' "无法记录二进制文件的 SHA-256 哈希 (could not record binary SHA-256 hashes)" ;;
        install.abort_tailscale_elf) printf '%s' "tailscale 不是有效的 ELF 可执行文件 (not a valid ELF executable)" ;;
        install.abort_tailscaled_elf) printf '%s' "tailscaled 不是有效的 ELF 可执行文件 (not a valid ELF executable)" ;;
        install.abort_exec) printf '%s' "tailscaled 无法在此设备上执行 (could not execute on this device)" ;;
        install.installed_version) printf '%s' "已安装 Tailscale %s (installed Tailscale)" ;;
        install.moved_legacy) printf '%s' "已将旧版独立启动脚本移出 service.d (moved old standalone launcher outside service.d)" ;;
        install.state_path) printf '%s' "登录状态仍保留在 /data/adb/tailscale-native (state remains at /data/adb/tailscale-native)" ;;
        install.keep_official_off) printf '%s' "请保持官方 Tailscale 应用处于断开状态 (keep the official Tailscale app disconnected)" ;;
        install.reboot) printf '%s' "安装完成后请重启设备 (reboot after installation)" ;;
        install.install_webui) printf '%s' "如需要请安装 KsuWebUIStandalone (install KsuWebUIStandalone if needed)" ;;
        install.action_hint) printf '%s' "重启后点击「操作」打开仪表盘并在此登录 (after reboot, tap Action to open the dashboard and sign in there)" ;;
        install.update_hint) printf '%s' "需要手动更新二进制文件时，使用仪表盘中的 Update Tailscale (use Update Tailscale in the dashboard for manual binary updates)" ;;
        service.official_vpn_active) printf '%s' "官方 Tailscale Android VPN 正在运行，原生守护进程未启动 (official Tailscale Android VPN is active; native daemon not started)" ;;
        service.start_failed) printf '%s' "原生 tailscaled 启动失败 (failed to start native tailscaled)" ;;
        service.started) printf '%s' "原生 tailscaled 已启动 (native tailscaled started)" ;;
        service.hostname_checked) printf '%s' "已检查设备主机名偏好 (device hostname preference checked)" ;;
        service.auth_required) printf '%s' "需要身份验证，请在 Native Tailscale 仪表盘登录 (authentication required; sign in from the dashboard)" ;;
        *) return 1 ;;
    esac
}

# 输出「当前语言」的本地化文本；缺 key 时回退 en，再回退 key 本身。
msg() {
    [ -n "${1:-}" ] || return 0
    i18n_lang >/dev/null
    case "$I18N_ACTIVE_LANG" in
        zh-CN) I18N_TEXT="$(i18n_text_zh "$1")" ;;
        *) I18N_TEXT="$(i18n_text_en "$1")" ;;
    esac
    [ -n "$I18N_TEXT" ] || I18N_TEXT="$(i18n_text_en "$1")"
    [ -n "$I18N_TEXT" ] || I18N_TEXT="$1"
    printf '%s\n' "$I18N_TEXT"
}

# 同 msg，但把剩余参数交给 printf 填充词典中的 %s。
msgf() {
    [ -n "${1:-}" ] || return 0
    I18N_MSGF_KEY="$1"
    shift
    i18n_lang >/dev/null
    case "$I18N_ACTIVE_LANG" in
        zh-CN) I18N_MSGF_FORMAT="$(i18n_text_zh "$I18N_MSGF_KEY")" ;;
        *) I18N_MSGF_FORMAT="$(i18n_text_en "$I18N_MSGF_KEY")" ;;
    esac
    [ -n "$I18N_MSGF_FORMAT" ] || I18N_MSGF_FORMAT="$(i18n_text_en "$I18N_MSGF_KEY")"
    [ -n "$I18N_MSGF_FORMAT" ] || I18N_MSGF_FORMAT="$I18N_MSGF_KEY"
    printf "$I18N_MSGF_FORMAT" "$@"
    printf '\n'
}
