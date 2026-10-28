# Native Tailscale TUN v0.5.3-zh

This release really fixes the daemon dying when the KernelSU or Magisk manager
app is swiped away. The previous attempt only detached the process group, which
turned out not to be what Android uses here.

## 中文

本次发布**真正修复**了「划掉 KernelSU / Magisk 管理器后 Tailscale 停止」的问题。
上一版只做了进程组脱离，事实证明那不是 Android 实际采用的清理维度。

### 根因

`setsid` 确实生效了——实测守护进程 `ppid=1`，进程组与会话都独立。但它只改变
会话和进程组，**不改变 cgroup**。从管理器启动的进程继承的是应用侧的
`/apps` 内存 cgroup（实测 `memory:/apps`），而 Android 划掉应用时按 cgroup
成批清理，于是守护进程被连带杀掉。

开机启动之所以一直正常，是因为它由 `init` 拉起，本来就位于 system cgroup。
这正是「开机启动没事、管理器启动会死」的真正分界。

### 修复

- **cgroup 迁移**：守护进程启动成功后，显式迁到 system cgroup，恢复与开机启动
  相同的免疫效果。
- **新增看护器 `watchdog.sh`**：由 `service.sh` 在开机时以 init 子进程身份启动，
  本身就在 system cgroup；每 15 秒巡检一次，守护进程若被外部杀掉会自动重新拉起，
  重新拉起的进程同样落在 system cgroup。
- **尊重用户意图**：仪表盘点「停止」会写入 `daemon-stopped` 标记并停止看护器，
  看护器不会把用户主动停掉的服务又拉起来；点「启动」会清除标记并恢复看护。

### 版本

- 版本号 `0.5.3-zh`（versionCode `503`）。
- 可直接覆盖安装，`/data/adb/tailscale-native` 中的登录身份保留。
- 安装后请重启，让 `service.sh` 重新执行并在 init 上下文里拉起看护器。

## English

This release really fixes the daemon dying when the KernelSU or Magisk manager
app is swiped away. The previous attempt only detached the process group, which
turned out not to be the dimension Android actually cleans up along.

### Root cause

`setsid` did work — the daemon measurably had `ppid=1` with its own process
group and session. But it only changes the session and process group, **not the
cgroup**. A process started from the manager inherits the app-side `/apps`
memory cgroup (measured `memory:/apps`), and Android cleans apps up by cgroup,
so the daemon was killed along with them.

Boot-time start was always fine because `init` spawns it, so it already lives in
the system cgroup. That is the real dividing line between "boot start is fine"
and "manager start dies".

### Fixed

- **cgroup migration**: after a successful start the daemon is explicitly moved
  to the system cgroup, restoring boot-like immunity.
- **New `watchdog.sh`**: started by `service.sh` at boot as an init child, so it
  already lives in the system cgroup. Every 15 seconds it checks the daemon and
  relaunches it if something killed it; the relaunched process lands in the
  system cgroup as well.
- **Respects user intent**: pressing Stop writes a `daemon-stopped` marker and
  stops the watchdog so it will not resurrect a deliberately stopped service;
  Start clears the marker and restores the watchdog.

### Version

- Version `0.5.3-zh` (versionCode `503`).
- Installs over previous versions; the authenticated identity under
  `/data/adb/tailscale-native` is preserved.
- Reboot after installing so `service.sh` runs again and starts the watchdog in
  the init context.

## Validation

- `node tools/check-i18n.js` reports zero errors across all areas.
- Shell syntax checks pass for every module script, including `watchdog.sh`.
- On the affected device the daemon was observed with `ppid=1` and
  `cgroup memory:/apps` before the fix, which identified the cgroup as the
  actual kill vector.

## 验证

- `node tools/check-i18n.js` 全部领域无 error。
- 所有模块脚本（含 `watchdog.sh`）通过 shell 语法检查。
- 在问题设备上观测到修复前守护进程 `ppid=1` 而 `cgroup memory:/apps`，据此
  定位到 cgroup 才是真正的清理维度。

## Important

- ARM64 only.
- Reboot after installing so the kernel manager activates every updated module
  script.
- Disconnect the official Android Tailscale app before using the native daemon.
- Existing identity under `/data/adb/tailscale-native` remains preserved.

## 重要说明

- 仅支持 ARM64。
- 安装后请重启，以便内核管理器激活全部更新后的模块脚本。
- 使用原生守护进程前，请先断开官方 Android Tailscale 应用。
- `/data/adb/tailscale-native` 中已有的身份会被保留。

## SHA-256

The checksum of this release archive is published in `SHA256SUMS` and attached
to the GitHub release. Verify it after downloading:

本次发布包的校验值公布在 `SHA256SUMS` 中，并随后续 GitHub Release 一并附上。
下载后请核对：

```sh
sha256sum --check SHA256SUMS
```
