# Native Tailscale TUN v0.5.5-zh

The watchdog now re-checks and corrects its own cgroup placement every round,
and the fix was verified against the real "swipe away from recents" action.

## 中文

看护器现在每轮巡检都会自查并纠正 cgroup 归属，并且这次是用**真正的「划掉」**
动作验证的。

### 本次改动

- **看护器每 15 秒自我纠偏**：检查看护器自身与守护进程是否仍留在 `apps` 内存
  桶，若在则立即迁到 `system`。即使开机时迁移因时机问题没成功，也会在一轮内
  自动纠正，不需要再重启。
- **用真正的「划掉」验证通过**：
  - `am stack remove <taskId>`（等价于从最近任务划掉 KernelSU）后，守护进程与
    看护器均存活 20 秒以上；
  - 更激进的 `am force-stop` 也无法杀死它们。

### 关于之前那次失败

你 01:47 复测时，设备上生效的还是 `0.5.3`——`0.5.4` 是 01:52 才安装的。而
`0.5.3` 的 cgroup 迁移路径写错了（写的是 cgroup v2 根节点，实际有效的是
`/dev/memcg` 的 v1 层级），所以守护进程和看护器当时都还留在 `apps` 桶里，被
一起清掉。这不是 0.5.4 的回归。

另外更正我自己的排查手法：我之前用 `am force-stop` 模拟"划掉"是错的，那比划掉
激进得多，会连带杀掉 `su` 会话，连我自己的 adb 连接都被打断。已改用
`am stack remove`。

### 使用

- 安装后**重启一次**，让 `service.sh` 用新代码启动看护器并完成迁移。
- 之后无论从管理器启动还是开机启动，看护器都会保证两者待在 `system` 桶。

## English

The watchdog now re-checks and corrects its own cgroup placement every round, and
the fix was verified with the real "swipe away from recents" action.

### Changed

- **The watchdog self-corrects every 15 seconds**: it checks whether itself and
  the daemon are still in the `apps` memory bucket and moves them to `system` if
  they are. Even if the boot-time migration loses a timing race, it self-heals
  within one tick without a reboot.
- **Verified with a real swipe**:
  - `am stack remove <taskId>` (equivalent to removing KernelSU from recents)
    left both the daemon and the watchdog alive for 20+ seconds;
  - the more aggressive `am force-stop` also fails to kill them.

### About the earlier failure

When you retested at 01:47 the device was still running `0.5.3` — `0.5.4` was
only installed at 01:52. `0.5.3` wrote the cgroup migration to the cgroup v2 root
while the effective memory controller is the v1 mount at `/dev/memcg`, so the
daemon and watchdog were still in the `apps` bucket and were swept away
together. This was not a regression in `0.5.4`.

I also have to correct my own debugging method: using `am force-stop` to
simulate "swiping away" was wrong. It is far more aggressive than a swipe, kills
the `su` session too, and even dropped my own adb connection. I switched to
`am stack remove`.

### Usage

- Reboot once after installing so `service.sh` starts the watchdog with the new
  code and completes the migration.
- From then on, whether started from the manager or at boot, the watchdog keeps
  both processes in the `system` bucket.

## Validation

- `node tools/check-i18n.js` reports zero errors across all areas.
- Shell syntax checks pass for every module script.
- Device measurements (Android 17 / KernelSU / arm64, module `0.5.4` live):
  - daemon and watchdog both `4:memory:/system`;
  - `am stack remove 182` (KernelSU task) → daemon and watchdog alive 20+ s;
  - `am force-stop me.weishu.kernelsu` → daemon and watchdog alive 20+ s;
  - earlier `SIGKILL` of the daemon → watchdog restarted it in ~15 s.

## 验证

- `node tools/check-i18n.js` 全部领域无 error。
- 所有模块脚本通过 shell 语法检查。
- 真机实测（Android 17 / KernelSU / arm64，生效版本 `0.5.4`）：
  - 守护进程与看护器均在 `4:memory:/system`；
  - `am stack remove 182`（KernelSU 任务）后两者存活 20 秒以上；
  - `am force-stop me.weishu.kernelsu` 后两者同样存活 20 秒以上；
  - 更早的强杀测试中，看护器约 15 秒完成自愈重启。

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
