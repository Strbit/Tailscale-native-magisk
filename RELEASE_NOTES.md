# Native Tailscale TUN v0.5.4-zh

Fixes the cgroup migration path from `0.5.3-zh` and ships a daemon watchdog that
was verified on a real device. After this release, the native daemon survives
the manager app being closed and recovers on its own if it is killed.

## 中文

修正了 `0.5.3-zh` 的 cgroup 迁移路径，并附带一个已在真机上验证通过的守护进程
看护器。安装本版后，原生守护进程不会再因为关闭管理器应用而消失；即使被强杀，
也会自动恢复。

### 本次修复

- **修正 cgroup 迁移路径**。上一版写入的是 cgroup v2 挂载
  （`/sys/fs/cgroup/cgroup.procs`），但真正生效的是挂载在 `/dev/memcg` 的 v1
  内存控制器。旧写法虽然返回成功，`4:memory:/apps` 却从未改变。现在改为写
  `/dev/memcg/system/cgroup.procs`，并且写入后回读 `/proc/PID/cgroup` 校验，
  确认真的离开 `apps` 桶才算成功。
- **看护器真机验证**。在 Android 17 / KernelSU 设备上实测：强杀 `tailscaled`
  后约 15 秒内自动拉起新进程，新进程位于 `4:memory:/system`，Tailscale 连接
  自动恢复，无需手动干预。

### 关于根因的更正

上一版说明把原因归于「划掉管理器会连带清理 cgroup」。实测结论更精确：

- 单独 `kill -9` KernelSU 管理器**不会**杀死 `tailscaled`——管理器位于
  `mimd/uid_10320`，守护进程位于 `/apps`，两者不是同一 cgroup。
- 真正让服务恢复可用的是**看护器的自愈能力**。
- 把守护进程迁出 `apps` 桶属于**预防性加固**，让它和开机启动（`init` 位于
  cgroup 根）处于同等地位，避免被系统当作应用进程一类的清理目标。

### 使用提示

- 安装后请**重启**，让 `service.sh` 在 init 上下文里拉起看护器。
- 仪表盘点「停止」时看护器会同步停止，不会把主动停掉的服务又拉起来；点「启动」
  会自动恢复看护。

## English

Fixes the cgroup migration path from `0.5.3-zh` and ships a daemon watchdog
verified on a real device. After this release the native daemon survives the
manager app being closed and recovers on its own if it is killed.

### Fixed

- **Corrected the cgroup migration path.** The previous release wrote to the
  cgroup v2 mount (`/sys/fs/cgroup/cgroup.procs`), but the effective memory
  controller is the v1 mount at `/dev/memcg`. The old code reported success
  while `4:memory:/apps` never changed. It now writes
  `/dev/memcg/system/cgroup.procs` and re-reads `/proc/PID/cgroup` to confirm the
  process really left the `apps` bucket.
- **Watchdog verified on a real device.** On an Android 17 / KernelSU device,
  `SIGKILL` on `tailscaled` made the watchdog relaunch it within about 15
  seconds; the new process lands in `4:memory:/system` and Tailscale
  connectivity recovers without manual intervention.

### Root-cause correction

The previous release attributed the problem to "swiping the manager sweeps up
the cgroup". Measurement gives a more precise picture:

- `kill -9` on the KernelSU manager alone does **not** kill `tailscaled` — the
  manager sits in `mimd/uid_10320` while the daemon sits in `/apps`; they are
  different cgroups.
- What actually restores service availability is the **watchdog's self-healing**.
- Moving the daemon out of the `apps` bucket is **preventive hardening** that
  puts it on the same footing as a boot start (`init` lives at the cgroup root),
  so the system is less likely to treat it as an app-like cleanup target.

### Usage

- Reboot after installing so `service.sh` starts the watchdog in the init
  context.
- Pressing Stop in the dashboard also stops the watchdog so a deliberately
  stopped service stays stopped; Start restores the watchdog automatically.

## Validation

- `node tools/check-i18n.js` reports zero errors across all areas.
- Shell syntax checks pass for every module script, including `watchdog.sh`.
- Device measurements (Android 17 / KernelSU / arm64):
  - daemon before fix: `4:memory:/apps`; after migration `4:memory:/system`;
  - `kill -9` on the KernelSU manager left `tailscaled` alive for 20+ seconds;
  - `SIGKILL` on `tailscaled` was followed by automatic restart in ~15 s with
    `4:memory:/system`;
  - `tailscale status` recovered and peer connectivity returned to direct.

## 验证

- `node tools/check-i18n.js` 全部领域无 error。
- 所有模块脚本（含 `watchdog.sh`）通过 shell 语法检查。
- 真机实测（Android 17 / KernelSU / arm64）：
  - 修复前守护进程为 `4:memory:/apps`，迁移后为 `4:memory:/system`；
  - `kill -9` KernelSU 管理器后 `tailscaled` 存活 20 秒以上；
  - 强杀 `tailscaled` 后约 15 秒自动重启，且位于 `4:memory:/system`；
  - `tailscale status` 恢复正常，对端回到 direct 连接。

## Important

- ARM64 only.
- Reboot after installing so the kernel manager activates every updated module
  script and `service.sh` starts the watchdog.
- Disconnect the official Android Tailscale app before using the native daemon.
- Existing identity under `/data/adb/tailscale-native` remains preserved.

## 重要说明

- 仅支持 ARM64。
- 安装后请重启，以便内核管理器激活全部更新后的模块脚本，并由 `service.sh`
  拉起看护器。
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
