Native Tailscale TUN — Magisk 引导模块 v0.5.0-zh

============================================================
中文
============================================================

用途
以 root 原生的 TUN 服务运行 android-kxxt 打过补丁的 tailscaled 守护进程，
从而把 Android 的 VpnService 槽位留给其他 VPN 使用。

安装
1. 断开官方 Android Tailscale 应用。
2. 在 Magisk > 模块 > 从本地安装 中安装本 ZIP。
3. 重启。
4. 安装 KsuWebUIStandalone。
5. 点击模块的 操作（Action）按钮打开仪表盘，然后点击 登录（Sign in）。
6. 模块会复用以下状态文件：
   /data/adb/tailscale-native/tailscaled.state
   因此你原有的 Tailscale 节点身份通常仍保持登录状态。

登录与更新
操作（Action）按钮仅用于打开仪表盘，请在其中完成登录与手动 Tailscale 二进制
更新。更新器会：
- 检查 android-kxxt/external_tailscale_prebuilt
- 比较上游源码提交标记
- 下载 ARM64 tailscale 与 tailscaled
- 复查该标记，若下载期间上游发生变更则中止
- 校验 ELF 格式，并确认 tailscaled 可以执行
- 记录 SHA-256 哈希
- 备份当前二进制
- 重启守护进程
- 若新守护进程启动失败则自动回滚

可选 WebUI
在 Magisk 上安装 KsuWebUIStandalone 即可打开内置仪表盘。它会显示连接与完整性
状态，提供安全的 Tailscale 偏好设置，控制原生服务，校验已安装二进制，并显示
近期日志。仪表盘支持英文与简体中文，可在页头切换；语言选择同样作用于模块的
shell 输出。登录结果同时包含可点击的链接与完整可复制的 URL；重复点击 登录
（Sign in）会复用同一个待认证链接。诊断（Diagnostics）会解释原生 Android 上
预期出现的 DNS 健康警告；更新结果不含该警告，而是显示简洁的实时连接摘要。
原生 Android 构建无法安装系统级 MagicDNS，因此模块保持 accept-dns 关闭，不改
动 Android 现有 DNS。Tailnet 管理（Tailnet Admin）会在普通浏览器中打开官方
Tailscale Machines 页面。模块更新通知由 Magisk 负责，仪表盘负责登录与手动
Tailscale 二进制更新。

安全说明
上游仓库目前只发布未签名的原始预编译二进制，没有签名发布包或签名校验清单。
因此更新器信任 HTTPS、GitHub 与 android-kxxt 仓库。更新为手动操作，绝不在
开机时自动执行。若对此有顾虑，请在点击 更新 Tailscale（Update Tailscale）
之前先审查上游变更。

状态与卸载
卸载会停止守护进程，但会刻意保留：
  /data/adb/tailscale-native
仅当你需要抹掉节点身份时，才手动删除该目录。

故障排查
日志：
  /data/adb/tailscale-native/tailscaled.log

状态：
  su -c '/data/adb/modules/native_tailscale/bin/tailscale --socket=/data/adb/tailscale-native/tailscaled.sock status'

版本：
  su -c '/data/adb/modules/native_tailscale/bin/tailscaled --version'

接口：
  su -c 'ip addr show tailscale0'

当 Android 报告官方 com.tailscale.ipn VPN 处于活动状态时，原生守护进程不会启动。

已知限制
- 仅支持 ARM64。
- 模块版本描述的是引导脚本，不是安装时下载的 Tailscale 版本。
- 同一个 ZIP 可在之后安装更新的上游 Tailscale 构建。
- 另一个 VPN 仍可能通过 DNS、路由或终止开关（kill switch）策略产生冲突。
- 发布 ZIP 的校验值不验证之后下载的二进制。

0.2.1 迁移修复
更早的独立启动脚本会被移动到 /data/adb/service.d-disabled。仅修改文件名后缀
并不能禁用 service.d 中的可执行脚本，因为 Magisk 依据可执行权限而非后缀来执行
它们。模块还会在移除或重建 socket 之前先停止旧版守护进程。

============================================================
ENGLISH
============================================================

Native Tailscale TUN — Magisk bootstrap module v0.5.0-zh

PURPOSE
Runs the android-kxxt patched tailscaled daemon as a root-native TUN service,
leaving Android's VpnService slot available for another VPN.

INSTALL
1. Disconnect the official Android Tailscale app.
2. Install this ZIP from Magisk > Modules > Install from storage.
3. Reboot.
4. Install KsuWebUIStandalone.
5. Tap the module's Action button to open the dashboard, then tap Sign in.
6. The module reuses:
   /data/adb/tailscale-native/tailscaled.state
   so your existing Tailscale node identity should remain logged in.

LOGIN AND UPDATES
The Action button only opens the dashboard. Sign in and run manual Tailscale
binary updates there. The binary updater:
- checks android-kxxt/external_tailscale_prebuilt
- compares the upstream source commit marker
- downloads ARM64 tailscale and tailscaled
- rechecks the marker and aborts if upstream changed during the download
- verifies ELF format and that tailscaled executes
- records SHA-256 hashes
- backs up the current binaries
- restarts the daemon
- rolls back automatically if the new daemon fails to start

OPTIONAL WEBUI
Install KsuWebUIStandalone on Magisk to open the bundled dashboard. It shows
connection and integrity status, exposes safe Tailscale preferences, controls
the native service, verifies installed binaries, and displays recent logs.
The dashboard is available in English and Simplified Chinese, switchable from
its header; the choice also applies to the module's shell output. The sign-in
result includes both a tappable link and the full selectable URL. Repeated
Sign in taps reuse the same pending authentication link. Diagnostics explains
the expected native Android DNS health warning; updater results omit that
warning and show a concise live connection summary instead.
The native Android build cannot install system-wide MagicDNS, so the module
keeps accept-dns disabled and leaves Android's existing DNS untouched.
Tailnet Admin opens the official Tailscale Machines page in the normal browser.
Magisk handles module update notifications. The dashboard handles login and
manual Tailscale binary updates.

SECURITY NOTE
The upstream repository currently publishes raw prebuilts without signed
releases or a signed checksum manifest. The updater therefore trusts HTTPS,
GitHub, and the android-kxxt repository. Updates are manual, never automatic
at boot. Review upstream changes before selecting Update Tailscale if this is
a concern.

STATE AND UNINSTALL
Uninstalling stops the daemon but intentionally preserves:
  /data/adb/tailscale-native
Delete that directory manually only when you want to erase the node identity.

TROUBLESHOOTING
Log:
  /data/adb/tailscale-native/tailscaled.log

Status:
  su -c '/data/adb/modules/native_tailscale/bin/tailscale --socket=/data/adb/tailscale-native/tailscaled.sock status'

Version:
  su -c '/data/adb/modules/native_tailscale/bin/tailscaled --version'

Interface:
  su -c 'ip addr show tailscale0'

The native daemon will not start while Android reports the official
com.tailscale.ipn VPN as active.

LIMITATIONS
- ARM64 only.
- The module version describes the bootstrap scripts, not the Tailscale
  version downloaded at installation time.
- The same ZIP can install a newer upstream Tailscale build on a later date.
- Another VPN can still conflict through DNS, routes, or kill-switch policy.
- The release ZIP checksum does not verify binaries downloaded afterward.

MIGRATION FIX IN 0.2.1
Older standalone launchers are moved to /data/adb/service.d-disabled.
Simply changing a filename suffix does not disable an executable service.d
script, because Magisk uses its executable permission rather than the suffix.
The module also stops a legacy daemon before removing or recreating its socket.
