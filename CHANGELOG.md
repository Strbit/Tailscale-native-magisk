# Changelog

## 0.5.9-zh — 2026-10-31

Rewrite the subnet-route guard: cover the return path and the client-mode case.

### 中文

前几版的热点保护有两个缺口，实测确认后一并重写：

1. **只覆盖去程**。规则选择器是 `iif <热点接口>`，只匹配"从热点接口进来"的包。
   回程包（外网 → 客户端）从 `rmnet`/`wlan0` 进入，不匹配该规则，仍被 table 52
   的 `192.168.43.0/24` 吞掉。现场 conntrack 满屏 `SYN_RECV`（178 → 215 持续
   增长，几乎无 `ESTABLISHED`），客户端能发出请求却永远收不到回应。
2. **只识别热点接口**。判定条件是"地址以 `.1` 结尾的网段接口"。当本机作为
   **客户端**接入同网段的网络时（手机连另一台手机的热点，`wlan0=192.168.43.56`），
   本机自身与局域网之间的流量同样被抢，却完全不在保护范围内。

重写后的做法：

- 按**网段重叠**判定（改为判定前缀包含关系，能识别 `192.168.0.0/16` 这类超网，
  不再要求精确等于 `/24`）。
- 覆盖**本机所有 IPv4 接口**，不再限定 `.1` 地址，客户端模式同样受保护。
- 插入**目标匹配**规则 `to <本地网段> lookup main`，pref `4999`（优先于
  Tailscale 的 `5270`），一次性覆盖去程、回程与本机自身三个方向。

真机验证（Android 17 / KernelSU / arm64；A 作为客户端接入 B 的热点
`wlan0=192.168.43.56`，对端通告 `192.168.43.0/24`）：

| 路径 | 修复前 | 修复后 |
| --- | --- | --- |
| A → 电脑 `192.168.43.163` | `dev tailscale0 table 52` | `dev wlan0` |
| A → 网关 `192.168.43.1` | `dev tailscale0 table 52` | `dev wlan0` |
| A → 公网 `223.5.5.5` | 正常 | 正常（不受影响） |
| 电脑 → A ping / 5244 端口 | 不通 | 通（HTTP 200） |

开关联动验证：关闭 accept-routes 后规则自动释放（0 条），重新开启后自动重插
（1 条），日志记录应用/释放/再应用三次转换，无残留。

### English

The previous hotspot guard had two gaps, both confirmed by measurement, so it was
rewritten:

1. **Forward direction only.** The selector was `iif <hotspot-iface>`, matching
   only packets arriving on that interface. Return packets (internet → client)
   enter via `rmnet`/`wlan0`, do not match, and were still swallowed by
   table 52's `192.168.43.0/24`. Field conntrack showed `SYN_RECV` piling up
   (178 → 215, almost no `ESTABLISHED`): clients sent requests but never got a
   reply.
2. **Hotspot interfaces only.** Detection required an interface whose address
   ends in `.1`. When the phone is a **client** on a colliding subnet
   (`wlan0=192.168.43.56` on another phone's hotspot), the phone's own LAN
   traffic was hijacked too and was not covered at all.

What changed:

- Detection now works by **prefix overlap** (including containment, so a
  `192.168.0.0/16` supernet is caught), no longer requiring an exact `/24` match.
- **All IPv4 interfaces** are considered, not just `.1` addresses, so the
  client-mode case is protected.
- A **destination-based** rule `to <subnet> lookup main` at pref `4999` (ahead of
  Tailscale's `5270`) covers forward, return, and phone-originated traffic in one
  rule.

Verified on a real device (Android 17 / KernelSU / arm64; phone A as a client of
phone B's hotspot, `wlan0=192.168.43.56`, peer advertising `192.168.43.0/24`):

| Path | Before | After |
| --- | --- | --- |
| A → PC `192.168.43.163` | `dev tailscale0 table 52` | `dev wlan0` |
| A → gateway `192.168.43.1` | `dev tailscale0 table 52` | `dev wlan0` |
| A → internet `223.5.5.5` | fine | fine (unaffected) |
| PC → A ping / port 5244 | unreachable | reachable (HTTP 200) |

Toggle check: turning accept-routes off releases the rule automatically (0
rules), turning it back on re-adds it (1 rule), and the log records all three
transitions with no residue.

## 0.5.8-zh — 2026-10-29

Fix hotspot-guard cleanup so stale policy rules never accumulate.

### 中文

- **修复热点保护的规则清理**。`0.5.7` 用 `grep "iif wlan2 lookup main"` 判断规则是
  否存在，但接口消失后 `ip rule show` 会显示为
  `iif wlan2 [detached] lookup main`，两个片段不再相邻，导致清理匹配失败、规则
  永久残留。现在改为分两步匹配，并新增 `guarded_rule_ifaces` 直接枚举本模块插入
  的所有规则，凡是本轮不再需要的（热点关闭、冲突消失、接口已消失）一律删除。
- **日志兜底**：`guard_hotspot_route` 改用 `guard_msgf`，调用方未加载 `i18n.sh`
  时退化为纯文本，不再写出空日志行。
- **真机验证**：清理前存在两条 detached 残留规则（`192.168.43.1`、`wlan2`，
  为前两轮测试遗留），调用一次 `guard_hotspot_route` 后全部移除，无残留。

### English

- **Fixed hotspot-guard rule cleanup.** `0.5.7` detected an existing rule with
  `grep "iif wlan2 lookup main"`, but once the interface disappears
  `ip rule show` renders it as `iif wlan2 [detached] lookup main`, so the two
  fragments are no longer adjacent and the match failed, leaving rules behind
  forever. It now matches in two steps and adds `guarded_rule_ifaces` to
  enumerate every rule this module inserted, removing all that are no longer
  needed this round (hotspot closed, conflict gone, interface disappeared).
- **Logging fallback**: `guard_hotspot_route` now uses `guard_msgf`, which
  degrades to plain text when the caller did not load `i18n.sh`, instead of
  writing empty log lines.
- **Verified on device**: two detached leftover rules (`192.168.43.1`, `wlan2`,
  left by earlier tests) were removed by a single `guard_hotspot_route` call,
  with no residue.

## 0.5.7-zh — 2026-10-29

Add a hotspot route guard so accepting tailnet subnet routes no longer breaks
the phone's own hotspot LAN.

### 中文

- **新增「热点子网保护」**。Android 手机热点默认使用 `192.168.43.0/24`。当
  Tailscale 开启接受子网路由（`accept-routes`），而对端节点也通告
  `192.168.43.0/24` 时，Tailscale 会在策略路由表 52 里安装
  `192.168.43.0/24 dev tailscale0`。结果本机热点下设备的转发流量被抢进隧道，
  表现为「热点里的设备访问不了本地网络」，而本机自己却正常。
- **修复方式**：仅当**热点子网与 table 52 中的路由同网段**时才介入，为热点接口
  插入一条更高优先级的策略规则
  `ip rule add iif <热点接口> lookup main pref 5000`，让热点转发流量查 main 表。
  本机自己发起的流量不受影响，仍然经 Tailscale 访问对端局域网。
- **自动跟随热点开关**：看护器每 15 秒检查一次，热点开启/关闭、网段变化、
  Tailscale 启停都会自动插入或释放规则，并写入日志。
- **真机验证**（Android 17 / KernelSU / arm64，热点接口 `wlan2`）：

  | 测试 | 加规则前 | 加规则后 |
  | --- | --- | --- |
  | 热点客户端 → `192.168.43.5` | `dev tailscale0`（被劫持） | `dev wlan2`（本地） |
  | 本机自身 → `192.168.43.5` | `dev tailscale0` | `dev tailscale0`（不变） |
  | 热点客户端 → `8.8.8.8` | 正常经 VPN | 正常经 VPN |

  关闭热点后规则自动释放，无残留。

### English

- **New hotspot route guard.** Android hotspots default to `192.168.43.0/24`.
  When Tailscale accepts subnet routes and a peer advertises the same
  `192.168.43.0/24`, Tailscale installs `192.168.43.0/24 dev tailscale0` in
  policy table 52. Forwarded traffic from the hotspot's clients is then pulled
  into the tunnel, so devices on the hotspot cannot reach the local network,
  while the phone itself still works.
- **Fix**: only when the hotspot subnet collides with a route in table 52, add a
  higher-priority policy rule
  `ip rule add iif <hotspot-iface> lookup main pref 5000` so forwarded hotspot
  traffic consults the main table. The phone's own traffic is untouched and
  still reaches the peer LAN over Tailscale.
- **Follows the hotspot automatically**: the watchdog re-checks every 15
  seconds and adds or releases the rule as the hotspot, subnet, or Tailscale
  state changes, logging each transition.
- **Verified on a real device** (Android 17 / KernelSU / arm64, hotspot interface
  `wlan2`):

  | Test | Before | After |
  | --- | --- | --- |
  | hotspot client → `192.168.43.5` | `dev tailscale0` (hijacked) | `dev wlan2` (local) |
  | phone itself → `192.168.43.5` | `dev tailscale0` | `dev tailscale0` (unchanged) |
  | hotspot client → `8.8.8.8` | works via VPN | works via VPN |

  Stopping the hotspot releases the rule automatically with no leftovers.

## 0.5.6-zh — 2026-10-29

Fix the real cause: Android's swipe-away cleanup walks the **cgroup v2** subtree,
which the previous releases never moved.

### 中文

- **找到并修复真正的根因**。之前在 WebUI 点「启动」后被划掉仍会停止，实测证据：
  - `am_kill` 记录 `me.weishu.kernelsu ... due to SwipeUpClean`，即上滑清理；
  - 高频监控抓到启动瞬间的进程归属：
    v1 `4:memory:/mimd/uid_10320`、v2 `0::/apps/uid_10320/pid_10639`，
    也就是**仍嵌在应用的 cgroup 子树里**；
  - 之前的迁移只写了 cgroup v1 内存控制器（`/dev/memcg`），v2 侧从未移动，
    所以 `SwipeUpClean` 顺着 v2 子树把它一起清掉。
- **双层迁移**：现在同时迁 v1（`/dev/memcg/system`）与
  v2（`/sys/fs/cgroup/system`），并各自回读 `/proc/PID/cgroup` 校验。
- **真机验证**（Android 17 / KernelSU / arm64）：
  - 启动瞬间：`v1=/mimd/uid_10320`、`v2=/apps/uid_10320/pid_10639`；
  - 1 秒后：`v1=/system`、`v2=/system`；
  - 划掉 KernelSU 后：`ppid=1`，两层次均为 `/system`，**守护进程存活**，
    Tailscale 连接保持，看护器同时存活。

### English

- **Found and fixed the real cause.** The daemon still stopped after a swipe
  when started from the WebUI. Evidence:
  - `am_kill` recorded `me.weishu.kernelsu ... due to SwipeUpClean`;
  - a high-resolution monitor captured the placement at start-up:
    v1 `4:memory:/mimd/uid_10320`, v2 `0::/apps/uid_10320/pid_10639` — still
    nested inside the app's cgroup subtree;
  - earlier releases only wrote the cgroup v1 memory controller
    (`/dev/memcg`) and never moved the v2 side, so `SwipeUpClean` swept the
    daemon away along the v2 subtree.
- **Dual-hierarchy migration**: both v1 (`/dev/memcg/system`) and v2
  (`/sys/fs/cgroup/system`) are now moved, each verified by re-reading
  `/proc/PID/cgroup`.
- **Verified on a real device** (Android 17 / KernelSU / arm64):
  - at start-up: `v1=/mimd/uid_10320`, `v2=/apps/uid_10320/pid_10639`;
  - one second later: `v1=/system`, `v2=/system`;
  - after swiping KernelSU away: `ppid=1`, both hierarchies `/system`, the
    daemon **survives**, Tailscale stays connected, and the watchdog survives
    too.

## 0.5.5-zh — 2026-10-29

Watchdog now self-corrects its cgroup placement; verified against the real
"swipe away" action.

### 中文

- **看护器每轮自我纠偏**：每 15 秒巡检时，看护器会检查自己和守护进程是否仍
  留在 `apps` 内存桶里，若是则立即迁到 `system`。这样即使开机时迁移因时机问题
  失败，也能在一轮内自动纠正，不需要重启。
- **用真正的「划掉」验证**：此前用 `am force-stop` 模拟是错的（那是强制停止，
  比划掉激进得多，会连带杀 su 会话，甚至把我自己的 adb 连接搞断）。改用
  `am stack remove <taskId>`（等价于从最近任务划掉）实测：
  - 划掉 KernelSU 后，守护进程与看护器均存活 20 秒以上；
  - `am force-stop` 同样无法杀死它们。
- **澄清之前那次失败**：你 01:47 复测时，设备上生效的仍是 `0.5.3`（`0.5.4`
  是 01:52 才安装的），而 `0.5.3` 的 cgroup 迁移路径写错了，守护进程和看护器
  都还留在 `apps` 桶里，才会被一起清掉。

### English

- **Watchdog self-corrects every round**: on each 15-second tick it checks
  whether itself and the daemon are still in the `apps` memory bucket and moves
  them to `system` if so. Even if the boot-time migration loses a timing race,
  it now self-heals within one tick without a reboot.
- **Verified with a real "swipe away"**: the earlier `am force-stop` simulation
  was wrong — that is a force-stop, far more aggressive than swiping, and it
  kills the `su` session along with it, which even dropped my own adb
  connection. Using `am stack remove <taskId>` (equivalent to removing the task
  from recents) the measurement is:
  - after removing KernelSU from recents, both the daemon and the watchdog
    stayed alive for 20+ seconds;
  - `am force-stop` also fails to kill them.
- **Explains the earlier failure**: when you retested at 01:47 the device was
  still running `0.5.3` (`0.5.4` was only installed at 01:52), and `0.5.3` had
  the wrong cgroup migration path, so the daemon and watchdog were still in the
  `apps` bucket and got swept away together.

## 0.5.4-zh — 2026-10-29

Fix the cgroup migration path; the watchdog is verified working on a real
device.

### 中文

- **修正 cgroup 迁移路径**。`0.5.3-zh` 写入的是 cgroup v2 挂载
  （`/sys/fs/cgroup/cgroup.procs`），实际有效的是 v1 内存控制器挂载在
  `/dev/memcg`。之前的写法虽然返回成功，但 `4:memory:/apps` 并未改变。现在改为
  写 `/dev/memcg/system/cgroup.procs`，并且写入后回读 `/proc/PID/cgroup` 校验，
  确认真的离开了 `apps` 桶才算成功。
- **看护器真机验证通过**。在 Android 17 / KernelSU 设备上实测：强杀
  `tailscaled` 后，看护器在约 15 秒内自动拉起新进程，新进程
  `4:memory:/system`，Tailscale 连接自动恢复。
- **澄清根因边界**。实测表明单独 `kill -9` KernelSU 管理器**不会**杀死
  `tailscaled`（管理器位于 `mimd/uid_10320`，守护进程位于 `/apps`，两者不同
  cgroup）。因此 0.5.3 的表述不准确：真正生效的是看护器的自愈能力；把守护进程
  迁出 `apps` 桶是预防性加固，让它与开机启动（init 位于根 cgroup）保持一致的
  地位。
- 安装后请重启，让 `service.sh` 在 init 上下文里拉起看护器。

### English

- **Fixed the cgroup migration path.** `0.5.3-zh` wrote to the cgroup v2 mount
  (`/sys/fs/cgroup/cgroup.procs`), but the effective memory controller is the
  v1 mount at `/dev/memcg`. The old code reported success while
  `4:memory:/apps` never changed. It now writes
  `/dev/memcg/system/cgroup.procs` and re-reads `/proc/PID/cgroup` to confirm
  the process really left the `apps` bucket.
- **Watchdog verified on a real device.** On an Android 17 / KernelSU device,
  killing `tailscaled` with `SIGKILL` made the watchdog relaunch it within about
  15 seconds; the new process lands in `4:memory:/system` and Tailscale
  connectivity recovers on its own.
- **Corrected the root-cause claim.** Measurement shows that `kill -9` on the
  KernelSU manager alone does **not** kill `tailscaled` (the manager sits in
  `mimd/uid_10320` while the daemon sits in `/apps` — different cgroups). The
  watchdog's self-healing is therefore the effective fix; moving the daemon out
  of the `apps` bucket is preventive hardening that puts it on the same footing
  as a boot start (init lives at the cgroup root).
- Reboot after installing so `service.sh` starts the watchdog in the init
  context.

## 0.5.3-zh — 2026-10-29

Fix the daemon still dying when the manager app is swiped away.

### 中文

- **真正修复「划掉管理器后 Tailscale 停止」**。`0.5.1-zh` 用 `setsid` 让守护
  进程脱离了调用方的会话和进程组，实测 `ppid` 确实变成 `1`，但守护进程仍会被
  杀。原因是 `setsid` 只改会话和进程组，**不改变 cgroup**：从管理器启动的进程
  继承的是 `/apps` 内存 cgroup（实测 `memory:/apps`），而 Android 清理应用时按
  cgroup 成批处理，于是守护进程照样被连带杀掉。开机启动之所以正常，是因为它由
  `init` 拉起，本来就在 system cgroup。
- **cgroup 迁移**：守护进程启动成功后，显式迁到 system cgroup，恢复与开机启动
  相同的免疫效果。
- **新增看护器 `watchdog.sh`**：由 `service.sh` 在开机时以 init 子进程身份启动，
  位于 system cgroup；每 15 秒检查一次守护进程，若被外部杀掉则自动拉起，重新
  拉起的进程同样落在 system cgroup。
- **尊重用户意图**：仪表盘点「停止」会写入 `daemon-stopped` 标记并停止看护器，
  看护器不会把用户主动停掉的服务又拉起来；点「启动」清除标记并恢复看护。

### English

- **Actually fix "Tailscale stops after the manager is swiped away".** `0.5.1-zh`
  used `setsid` to detach the daemon from the caller's session and process group;
  measured `ppid` really did become `1`, yet the daemon was still killed. The
  reason is that `setsid` changes the session and process group but **not the
  cgroup**: a process started from the manager inherits the `/apps` memory
  cgroup (measured `memory:/apps`), and Android cleans apps up by cgroup, so the
  daemon was swept away with them. Boot-time start was fine because it is
  spawned by `init` and already lives in the system cgroup.
- **cgroup migration**: after a successful start the daemon is explicitly moved
  to the system cgroup, restoring boot-like immunity.
- **New `watchdog.sh`**: started by `service.sh` at boot as an init child, so it
  lives in the system cgroup; every 15 seconds it checks the daemon and
  relaunches it if something killed it, and the relaunched process lands in the
  system cgroup too.
- **Respects user intent**: pressing Stop in the dashboard writes a
  `daemon-stopped` marker and stops the watchdog so it will not resurrect a
  deliberately stopped service; Start clears the marker and restores the
  watchdog.

## 0.5.2-zh — 2026-10-27

Fix binary download on devices without `wget`.

### 中文

- **修复更新程序无法下载**：`download_file` 此前只尝试 `wget` 和写死的
  Termux `curl` 路径。许多设备（含 KernelSU 环境）没有 `wget`，也没有装
  Termux，导致「更新 Tailscale」始终报「无法下载上游提交标记」，安装时也会
  退回到复用旧二进制。现在优先使用系统自带的 `/system/bin/curl`（Android 已
  内置），再回退到 `wget` 与 Termux `curl`。
- `customize.sh` 的安装期下载函数同步修复，安装时可直接拉取最新二进制。

### English

- **Fix the updater failing to download**: `download_file` only tried `wget`
  and a hardcoded Termux `curl` path. Many devices (including KernelSU setups)
  ship no `wget` and have no Termux, so "Update Tailscale" always reported
  "Could not download the upstream commit marker", and installation fell back to
  reusing existing binaries. The system `/system/bin/curl` (bundled with modern
  Android) is now tried first, with `wget` and Termux `curl` as fallbacks.
- The installer's download helper in `customize.sh` is fixed the same way.

## 0.5.1-zh — 2026-10-27

Daemon lifecycle fix for KernelSU and Magisk manager apps.

### 中文

- **修复守护进程随管理器被划掉而退出**：此前从管理器「操作」按钮启动
  `tailscaled` 时，它会加入管理器应用的进程组；划掉管理器后整个进程组被清理，
  `tailscaled` 被终止并留下幽灵进程。现在启动时用 `setsid` 让守护进程进入独立
  会话，不再依附于调用它的应用进程。开机时由 `service.sh` 启动的路径本就以 init
  为父进程，不受影响。
- **修复残留 `tailscale0` 导致无法再次启动**：守护进程被强杀后可能留下
  `tailscale0` 接口，旧逻辑会因此拒绝启动。现在检测到残留接口时先执行
  `tailscaled --cleanup` 清理，再正常启动。
- **PID 记录更准确**：`setsid` 可能 fork，因此启动成功后改用实际守护进程的 PID
  写入 pidfile，而不是 shell 的 `$!`。

### English

- **Fix daemon dying with the manager app**: starting `tailscaled` from the
  manager's Action button previously placed it in the manager app's process
  group, so swiping the manager away killed the daemon and left a ghost
  process. The daemon now starts under `setsid` in its own session and no
  longer depends on the calling app. The boot path via `service.sh` is
  init-parented and was never affected.
- **Fix stale `tailscale0` blocking restarts**: a killed daemon could leave the
  `tailscale0` interface behind, which made the old logic refuse to start. The
  stale interface is now cleaned with `tailscaled --cleanup` before starting.
- **More accurate PID tracking**: `setsid` may fork, so the real daemon PID is
  recorded after startup instead of the shell's `$!`.

## 0.5.0-zh — 2026-10-26

Chinese localization release. The module, its scripts, and its security model
behave as in `0.4.6-bootstrap`; this release adds bilingual UI and tooling on
top and moves the project to the `Strbit` fork.

### 中文

- **双语仪表盘**：新增离线词典与 `I18N` API，页头提供语言切换按钮，切换后立即
  重渲染，无需刷新页面。
- **语言持久化**：语言选择写入 `/data/adb/tailscale-native/ui-language`，Web 层
  与 shell 层共用同一事实源；未设置时按系统语言自动判定，英文为默认回退。
- **shell 与安装器本地化**：模块自身产生的所有面向用户的输出改走 `msg` /
  `msgf`；Magisk 安装器每条中文提示附带英文括注，确保 recovery 环境缺字体时仍
  可读。`tailscale` / `tailscaled` 的原始输出保持原文。
- **状态显示映射**：`BackendState`、`integrity`、`interface` 等字段仍以英文原值
  参与逻辑判断，仅在显示层映射为本地化文本。
- **i18n 校验工具**：新增 `tools/check-i18n.js`，检查双语文典键与占位符对齐、
  HTML/JS 引用的键是否存在、shell 字典与 `%s` 一致性、模块元数据与发布包结构。
- **换行符修复**：所有文本文件统一为 LF 且无 BOM，避免 Android shell 因 CRLF
  无法执行。
- **fork 化**：版本号改为 `0.5.0-zh`（versionCode `500`），`update.json`、
  `module.prop` 的 `updateJson` 与发布资产链接均指向
  `Strbit/Tailscale-native-magisk`。

### English

- **Bilingual dashboard**: adds an offline dictionary and `I18N` API with a
  header language switch that re-renders immediately, without a page reload.
- **Persisted language**: the choice is written to
  `/data/adb/tailscale-native/ui-language` and shared by the web and shell
  layers. Without a stored value it follows the system language, falling back
  to English.
- **Localized shell and installer output**: every user-facing line produced by
  the module's own scripts now goes through `msg` / `msgf`. Each Chinese
  installer message keeps an English gloss in parentheses so it stays readable
  when recovery lacks Chinese fonts. Raw `tailscale` / `tailscaled` output is
  passed through unchanged.
- **Display-only state mapping**: `BackendState`, `integrity`, and `interface`
  values still drive logic in their original English form and are translated
  only at the display layer.
- **i18n checks**: adds `tools/check-i18n.js` to verify dictionary key and
  placeholder parity, referenced HTML/JS keys, shell dictionary alignment and
  `%s` counts, module metadata, and release archive structure.
- **Line-ending fix**: all text files are LF and BOM-free so Android shell
  scripts remain executable.
- **Forked release**: version `0.5.0-zh` (versionCode `500`); `update.json`,
  the `updateJson` in `module.prop`, and release asset URLs now point at
  `Strbit/Tailscale-native-magisk`.

## 0.4.6-bootstrap — 2026-08-12

- Read an authentication URL directly from the live daemon status before
  starting or consulting a background login command.
- Ignore stale or recycled login PIDs unless `/proc` confirms that they belong
  to this module's exact `tailscale up` process.
- Stop orphaned login commands and clear their PID metadata whenever the daemon
  is stopped or freshly started.
- Prevent an old login log from replaying the incomplete-flags error after the
  daemon has already generated a valid sign-in URL.
- Retain bare `tailscale up` as the fallback, preserving every existing
  non-default preference.

## 0.4.5-bootstrap — 2026-08-12

- Recover saved sessions automatically after Start or Restart, including after
  an abrupt daemon kill, by retrying the control-plane refresh while the new
  daemon settles.
- Treat transient `NeedsLogin`/`NoState` startup states as session restoration
  instead of immediately prompting for authentication.
- Disable the login action during recovery and show a green **Signed in**
  state once the daemon reaches `Running`.
- Use a bare `tailscale up` for genuine authentication so existing non-default
  subnet-route, shields-up, hostname, and DNS preferences are preserved.
- Recheck live daemon state during login and report when the saved session has
  already recovered instead of claiming that a sign-in URL is unavailable.
- Remove the mismatched accent-colored bottom-right corner decoration from
  dashboard cards.

## 0.4.4-bootstrap — 2026-08-12

- Return pending authentication URLs through the same `login_url=` WebUI
  protocol as new login attempts, keeping the clickable sign-in control on
  repeated taps.
- Replace raw `tailscale status` output in the binary updater with a concise
  live state, IP, hostname, and TUN summary.
- Explain the native Android no-op OS DNS configurator and its expected
  low-severity base-DNS warning in Diagnostics.
- Remove the ineffective Tailscale DNS switch and keep `accept-dns=false`
  during daemon startup and dashboard login, leaving Android's existing DNS
  untouched.
- Add an allowlisted Tailnet Admin action that opens the official Tailscale
  Machines page in the device's normal browser.

## 0.4.3-bootstrap — 2026-08-12

- Restyle the offline dashboard with a responsive cyber-terminal interface,
  high-contrast connection matrix, and explicit ON/OFF switches.
- Keep all fonts, icons, scripts, and visual effects local to the module.
- Respect the device's reduced-motion accessibility setting.
- Show Tailscale authentication as a large tappable link and repeat the full,
  selectable URL underneath as a copy-and-paste fallback.
- Preserve the tested helper allowlist, live status, integrity, service,
  settings, updater, and real daemon-log behavior beneath the new design.

## 0.4.2-bootstrap — 2026-08-12

- Make Magisk Action exclusively launch the KsuWebUIStandalone dashboard.
- Move manual Tailscale binary updates into a clearly labeled dashboard
  control while leaving module releases to Magisk's built-in updater.
- Make normal dashboard refreshes fast by caching the last integrity result;
  hashing now runs separately on initial load or explicit verification.
- Ask the live daemon for a control-plane refresh before rechecking status so
  remotely removed machines can transition out of a stale running state.
- Label daemon logs as historical rather than current authentication truth.
- Add a Clear log control.

## 0.4.1-bootstrap — 2026-08-12

- Open this module directly in KsuWebUIStandalone when Magisk Action detects
  that authentication is required.
- Replace terminal QR output with a tappable authentication button inside the
  dashboard.
- Keep `tailscale up` running in the background while browser authentication
  completes.
- Fall back to printing the plain authentication URL when KsuWebUIStandalone
  is not installed or cannot be opened.
- Derive fresh node names from Android's configured device name, Bluetooth
  name, product market name, or model instead of using `node`/`localhost`.
- Prefill the dashboard hostname with that derived device name while retaining
  the manual hostname control.

## 0.4.0-bootstrap — 2026-08-12

- Add an offline dashboard for Magisk users running KsuWebUIStandalone.
- Show daemon, TUN interface, connection, version, source revision, and binary
  integrity status.
- Add controls for login, start, stop, restart, diagnostics, and logs.
- Add safe settings for Tailscale DNS, subnet routes, shields-up, and hostname.
- Record binary SHA-256 hashes during installation and after updates.
- Block binary updates when installed files no longer match their recorded
  hashes.
- Keep the existing Magisk Action flow as a fallback.
- Use Magisk's built-in `updateJson` notification flow for module releases;
  module updating is not duplicated inside the dashboard.
- Recover ownership of a managed daemon when its PID file is stale or missing,
  and refuse duplicate starts while another `tailscaled` or `tailscale0`
  already exists.

## 0.3.0-bootstrap — 2026-08-12

- Detect a fresh device's `NeedsLogin`/`NoState` state from the module Action.
- Start interactive `tailscale up --qr` login from the Magisk Action screen.
- Explain `NeedsMachineAuth` instead of silently running the updater.
- Start the daemon from Action when boot startup has not left it running.
- Record an actionable authentication message in the daemon log.

## 0.2.1-bootstrap — 2026-07-24

- Move legacy standalone launchers completely outside `service.d`.
- Stop legacy native daemons before cleaning or recreating their socket.
- Preserve the authenticated Tailscale state during upgrades and uninstall.
- Retain manual, validated, rollback-capable upstream binary updates.
- Recheck the upstream source marker around install and update downloads.
- Validate source markers as exact 40-character lowercase hexadecimal values.
- Avoid signaling a reused PID that no longer belongs to the module daemon.
- Use a portable boot-completion wait across Magisk versions.
- Clarify bootstrap-version, checksum, and dual-VPN limitations.

## 0.2.0-bootstrap — 2026-07-24

- Add a Magisk bootstrap installer for ARM64 patched Tailscale binaries.
- Start `tailscaled` as a root-native TUN service after Android networking is
  ready.
- Add a Magisk Action updater with ELF validation, backup, restart, and
  rollback.
