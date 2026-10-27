# Native Tailscale TUN v0.5.2-zh

This release fixes binary downloads on devices that have no `wget`, which made
both the in-dashboard updater and the installer fail. It also includes the
daemon lifecycle fix from `0.5.1-zh`.

## 中文

本次发布修复了没有 `wget` 的设备上二进制下载失败的问题——这会导致仪表盘的
「更新 Tailscale」和安装过程都无法下载。同时包含 `0.5.1-zh` 的守护进程生命周期
修复。

### 修复

- **更新程序无法下载**。此前 `download_file` 只尝试 `wget` 和写死的 Termux
  `curl` 路径。许多设备（含 KernelSU 环境）既没有 `wget` 也未安装 Termux，
  于是「更新 Tailscale」总是报「无法下载上游提交标记」，安装时也会退回复用旧
  二进制。现在优先使用 Android 自带的 `/system/bin/curl`，再回退到 `wget` 与
  Termux `curl`。
- **安装期下载同步修复**。`customize.sh` 的下载函数一并修正，安装时可直接拉取
  最新二进制，不再依赖设备上是否装了 `wget`。

### 沿用 0.5.1-zh 的修复

- **守护进程不再随管理器被划掉而退出**：从管理器「操作」按钮启动时，守护进程
  现在通过 `setsid` 进入独立会话，不再依附管理器应用的进程组。
- **残留 `tailscale0` 自动清理**：被强杀后不再因为接口残留而拒绝启动。

### 版本

- 版本号 `0.5.2-zh`（versionCode `502`）。
- 可直接覆盖安装 `0.5.0-zh` / `0.5.1-zh`，登录身份保留在
  `/data/adb/tailscale-native`。

## English

This release fixes binary downloads on devices without `wget`, which broke both
the dashboard updater and installation. It also carries the daemon lifecycle fix
from `0.5.1-zh`.

### Fixed

- **The updater could not download anything.** `download_file` previously tried
  only `wget` and a hardcoded Termux `curl` path. Many devices (including
  KernelSU setups) ship no `wget` and have no Termux, so "Update Tailscale"
  always reported "Could not download the upstream commit marker" and
  installation fell back to reusing old binaries. Android's bundled
  `/system/bin/curl` is now tried first, with `wget` and Termux `curl` as
  fallbacks.
- **Installer downloads fixed too.** The download helper in `customize.sh` is
  corrected the same way, so installation can fetch fresh binaries regardless of
  whether `wget` exists.

### Carried over from 0.5.1-zh

- **The daemon no longer dies with the manager app.** Started from the manager's
  Action button, it now runs under `setsid` in its own session instead of the
  manager app's process group.
- **Stale `tailscale0` is cleaned automatically** instead of blocking restarts.

### Version

- Version `0.5.2-zh` (versionCode `502`).
- Installs over `0.5.0-zh` / `0.5.1-zh`; the authenticated identity under
  `/data/adb/tailscale-native` is preserved.

## Validation

- `node tools/check-i18n.js` reports zero errors across all areas.
- Shell syntax checks pass for every module script.
- On a KernelSU device with no `wget`, `curl` downloads the upstream commit
  marker and the 18.7 MB ARM64 binary successfully (ELF header verified).

## 验证

- `node tools/check-i18n.js` 全部领域无 error。
- 所有模块脚本通过 shell 语法检查。
- 在无 `wget` 的 KernelSU 设备上实测：`curl` 成功下载上游 commit 标记与
  18.7 MB 的 ARM64 二进制（已校验 ELF 头）。

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
