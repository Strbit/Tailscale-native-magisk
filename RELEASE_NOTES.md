# Native Tailscale TUN v0.5.1-zh

This release fixes a daemon lifecycle bug that affected KernelSU and Magisk
manager apps. Module behaviour and the security model are otherwise unchanged
from `0.5.0-zh`.

## 中文

本次发布修复了一个守护进程生命周期缺陷，该缺陷会影响 KernelSU 与 Magisk 管理器
应用。除此之外，模块行为与安全模型与 `0.5.0-zh` 保持一致。

### 修复

- **守护进程不再随管理器被划掉而退出**。此前从管理器「操作」按钮启动
  `tailscaled` 时，它会加入管理器应用的进程组；划掉管理器后整个进程组被清理，
  `tailscaled` 随之被终止，并留下幽灵进程。现在启动时使用 `setsid` 让守护进程
  进入独立会话，不再依附调用它的应用进程。
- **开机启动路径本就不受影响**。由 `service.sh` 在开机时启动的守护进程以 `init`
  为父进程，与管理器应用无关；本次修复针对的是手动「操作」启动的场景。
- **修复残留 `tailscale0` 导致无法再次启动**。守护进程被强杀后可能留下
  `tailscale0` 接口，旧逻辑会因此拒绝启动。现在检测到残留接口时先执行
  `tailscaled --cleanup` 清理，再正常启动。
- **PID 记录更准确**。`setsid` 可能 fork，因此启动成功后改用实际守护进程 PID
  写入 pidfile，而不是 shell 的 `$!`。

### 版本

- 版本号 `0.5.1-zh`（versionCode `501`）。
- 已安装 `0.5.0-zh` 的设备可直接覆盖安装；`/data/adb/tailscale-native` 中的登录
  身份会被保留。

## English

This release fixes a daemon lifecycle bug affecting KernelSU and Magisk manager
apps. Module behaviour and the security model are unchanged from `0.5.0-zh`.

### Fixed

- **The daemon no longer dies when the manager app is swiped away.** Starting
  `tailscaled` from the manager's Action button previously placed it in the
  manager app's process group, so closing the manager killed the daemon and
  left a ghost process. The daemon now starts under `setsid` in its own
  session and no longer depends on the calling app.
- **The boot path was never affected.** A daemon started by `service.sh` at
  boot is parented by `init` and unrelated to the manager app; this fix targets
  the manual Action-button start.
- **A stale `tailscale0` interface no longer blocks restarts.** A killed daemon
  could leave `tailscale0` behind, which made the old logic refuse to start.
  The stale interface is now cleaned with `tailscaled --cleanup` first.
- **More accurate PID tracking.** `setsid` may fork, so the real daemon PID is
  recorded after startup instead of the shell's `$!`.

### Version

- Version `0.5.1-zh` (versionCode `501`).
- Devices running `0.5.0-zh` can install this over the top; the authenticated
  identity under `/data/adb/tailscale-native` is preserved.

## Validation

- `node tools/check-i18n.js` reports zero errors across all areas.
- Shell syntax checks pass for every module script.
- `en` and `zh-CN` dictionaries and `%s` placeholders remain aligned.

## 验证

- `node tools/check-i18n.js` 全部领域无 error。
- 所有模块脚本通过 shell 语法检查。
- `en` 与 `zh-CN` 词典及 `%s` 占位符保持对齐。

## Important

- ARM64 only.
- Reboot after installing so the kernel manager activates every updated module
  script.
- Disconnect the official Android Tailscale app before using the native daemon.
- Existing identity under `/data/adb/tailscale-native` remains preserved.
- Installing this fork replaces the upstream module of the same module ID
  (`native_tailscale`); your saved identity is kept.

## 重要说明

- 仅支持 ARM64。
- 安装后请重启，以便内核管理器激活全部更新后的模块脚本。
- 使用原生守护进程前，请先断开官方 Android Tailscale 应用。
- `/data/adb/tailscale-native` 中已有的身份会被保留。
- 本 fork 与上游模块 ID 相同（`native_tailscale`），安装本 fork 会替换上游模块；
  已保存的身份不受影响。

## SHA-256

The checksum of this release archive is published in `SHA256SUMS` and attached
to the GitHub release. Verify it after downloading:

本次发布包的校验值公布在 `SHA256SUMS` 中，并随后续 GitHub Release 一并附上。
下载后请核对：

```sh
sha256sum --check SHA256SUMS
```
