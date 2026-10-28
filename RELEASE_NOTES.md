# Native Tailscale TUN v0.5.6-zh

This release fixes the actual cause of "swiping KernelSU stops Tailscale".
Previous releases moved the daemon out of the cgroup v1 memory bucket, but
Android's swipe-away cleanup walks the **cgroup v2** subtree, which was never
moved. Both hierarchies are now migrated, verified on a real device.

## 中文

本次发布修复了「划掉 KernelSU 就停掉 Tailscale」的**真正原因**。之前几个版本
只把守护进程迁出 cgroup v1 的内存桶，但 Android 的划掉清理走的是 **cgroup v2**
子树，那一侧从未迁移过。现在两层都迁，并已真机验证。

### 根因与证据

在 WebUI 点「启动」后，守护进程的归属是：

```
cgroup v1: 4:memory:/mimd/uid_10320
cgroup v2: 0::/apps/uid_10320/pid_10639
```

它仍嵌在 KernelSU 应用的 cgroup 子树里。划掉时系统记录：

```
am_kill: me.weishu.kernelsu ... due to SwipeUpClean
```

`SwipeUpClean` 顺着 v2 子树把这个后代进程一起清掉了。只迁 v1 不够，因为
v2 路径没变。

### 修复

- **双层迁移**：同时迁 v1（`/dev/memcg/system`）与 v2
  （`/sys/fs/cgroup/system`），并且各自回读 `/proc/PID/cgroup` 确认生效。
- 看护器同样适用，它每轮巡检也会自查并纠正这两层归属。

### 真机验证（Android 17 / KernelSU / arm64）

| 时刻 | cgroup v1 | cgroup v2 | 状态 |
| --- | --- | --- | --- |
| 启动瞬间 | `/mimd/uid_10320` | `/apps/uid_10320/pid_10639` | 仍在应用子树 |
| 1 秒后 | `/system` | `/system` | 迁移完成 |
| 划掉 KernelSU 后 | `/system` | `/system` | 存活，`ppid=1` |

划掉之后 `tailscale status` 正常，对端保持 direct 连接，看护器也存活。

### 使用

- 安装后重启一次，让 `service.sh` 用新代码启动看护器。
- 之后无论从 WebUI 启动还是开机启动，两层次归属都会被纠正到 `/system`。

## English

This release fixes the actual cause of "swiping KernelSU stops Tailscale".
Previous releases only moved the daemon out of the cgroup v1 memory bucket, but
Android's swipe-away cleanup walks the **cgroup v2** subtree, which was never
moved. Both hierarchies are migrated now, verified on a real device.

### Root cause and evidence

After pressing Start in the WebUI, the daemon's placement was:

```
cgroup v1: 4:memory:/mimd/uid_10320
cgroup v2: 0::/apps/uid_10320/pid_10639
```

It was still nested inside the KernelSU app's cgroup subtree. On swipe the
system logged:

```
am_kill: me.weishu.kernelsu ... due to SwipeUpClean
```

`SwipeUpClean` swept the descendant along the v2 subtree. Moving only v1 was not
enough because the v2 path never changed.

### Fixed

- **Dual-hierarchy migration**: both v1 (`/dev/memcg/system`) and v2
  (`/sys/fs/cgroup/system`) are moved, each verified by re-reading
  `/proc/PID/cgroup`.
- The watchdog applies the same correction for itself on every tick.

### Verified on a real device (Android 17 / KernelSU / arm64)

| Moment | cgroup v1 | cgroup v2 | State |
| --- | --- | --- | --- |
| at start-up | `/mimd/uid_10320` | `/apps/uid_10320/pid_10639` | still under the app |
| one second later | `/system` | `/system` | migration done |
| after swiping KernelSU | `/system` | `/system` | alive, `ppid=1` |

After the swipe `tailscale status` is healthy, the peer stays on a direct
connection, and the watchdog is alive as well.

### Usage

- Reboot once after installing so `service.sh` starts the watchdog with the new
  code.
- From then on, whether started from the WebUI or at boot, both hierarchies are
  corrected to `/system`.

## Validation

- `node tools/check-i18n.js` reports zero errors across all areas.
- Shell syntax checks pass for every module script.
- Device measurements as shown in the tables above, captured with a 0.2 s
  sampling monitor while performing the real swipe-away action.

## 验证

- `node tools/check-i18n.js` 全部领域无 error。
- 所有模块脚本通过 shell 语法检查。
- 真机数据见上表，由 0.2 秒粒度的监控在你实际划掉操作时抓取。

## Important

- ARM64 only.
- Reboot after installing so the watchdog starts from the init context.
- Disconnect the official Android Tailscale app before using the native daemon.
- Existing identity under `/data/adb/tailscale-native` remains preserved.

## 重要说明

- 仅支持 ARM64。
- 安装后请重启，让看护器从 init 上下文启动。
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
