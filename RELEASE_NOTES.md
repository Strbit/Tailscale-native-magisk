# Native Tailscale TUN v0.5.9-zh

Rewrites the subnet-route guard so that enabling "accept subnet routes" no longer
breaks the phone's local network. The previous guard only covered the forward
direction and only recognised hotspot interfaces; both gaps are fixed.

## 中文

重写子网路由保护：开启「接受子网路由」后不再破坏本机局域网。上一版只覆盖去程、
且只识别热点接口，这两个缺口都已修复。

### 问题

对端节点通告的子网路由若与本机所在网段相同（Android 手机热点默认都是
`192.168.43.0/24`），Tailscale 会把 `192.168.43.0/24 dev tailscale0` 装进策略
路由表 52。此时本机与局域网之间的流量会被吸进隧道。

旧版保护的规则是 `ip rule add iif <热点接口> lookup main`，存在两个缺口：

| 缺口 | 后果 |
| --- | --- |
| 只匹配"从热点接口进来"的包 | 回程包（外网 → 客户端）从 rmnet 进入，不匹配，仍被吞掉；客户端 TCP 卡在 `SYN_RECV`，能发请求收不到回应 |
| 只识别"地址以 .1 结尾"的热点接口 | 本机作为**客户端**接入同网段网络时（连另一台手机的热点），自身流量同样被抢，却完全没有保护 |

### 修复

- 判定改为**网段重叠**（含前缀包含关系，`192.168.0.0/16` 这类超网也能识别），
  不再要求精确等于 `/24`。
- 覆盖**本机全部 IPv4 接口**，不再限定 `.1` 地址，客户端模式同样受保护。
- 插入**目标匹配**规则：

  ```
  ip rule add to <本地网段> lookup main pref 4999
  ```

  pref `4999` 优先于 Tailscale 的 `5270`，一条规则同时覆盖去程、回程和本机自身。

无冲突时不插入任何规则，完全保持系统原状。

### 真机验证（Android 17 / KernelSU / arm64）

场景：A 手机作为客户端接入 B 手机的热点（`wlan0=192.168.43.56`），对端通告
`192.168.43.0/24`。

| 路径 | 修复前 | 修复后 |
| --- | --- | --- |
| A → 电脑 `192.168.43.163` | `dev tailscale0 table 52` | `dev wlan0` |
| A → 网关 `192.168.43.1` | `dev tailscale0 table 52` | `dev wlan0` |
| A → 公网 `223.5.5.5` | 正常 | 正常（不受影响） |
| 电脑 → A ping | 不通 | 通（14ms） |
| 电脑 → `http://192.168.43.56:5244/` | 不通 | HTTP 200 |

开关联动：关闭 accept-routes 后规则自动释放（0 条），重新开启后自动重插（1 条），
日志完整记录应用/释放/再应用，无残留。

## English

Rewrites the subnet-route guard so that enabling "accept subnet routes" no longer
breaks the phone's local network. The previous guard only covered the forward
direction and only recognised hotspot interfaces; both gaps are fixed.

### Problem

When a peer advertises a subnet route identical to the one the phone is already on
(Android hotspots all default to `192.168.43.0/24`), Tailscale installs
`192.168.43.0/24 dev tailscale0` into policy routing table 52, pulling LAN traffic
into the tunnel.

The old guard used `ip rule add iif <hotspot-iface> lookup main` and had two gaps:

| Gap | Consequence |
| --- | --- |
| Matched only packets arriving on the hotspot interface | Return packets (internet → client) enter via rmnet, do not match, and are still swallowed; client TCP sticks in `SYN_RECV` — requests go out, replies never arrive |
| Required an interface address ending in `.1` | When the phone is a **client** on a colliding subnet (joined another phone's hotspot), its own traffic was hijacked with no protection at all |

### Fix

- Detection now uses **prefix overlap** (including containment, so a
  `192.168.0.0/16` supernet is caught) instead of an exact `/24` match.
- **All IPv4 interfaces** are considered, not only `.1` addresses, so the
  client-mode case is protected.
- A **destination-based** rule is inserted:

  ```
  ip rule add to <subnet> lookup main pref 4999
  ```

  Pref `4999` precedes Tailscale's `5270`, so one rule covers forward, return, and
  phone-originated traffic.

When there is no conflict, no rule is inserted and the system is left untouched.

### Verified on a real device (Android 17 / KernelSU / arm64)

Scenario: phone A joined phone B's hotspot as a client (`wlan0=192.168.43.56`),
peer advertising `192.168.43.0/24`.

| Path | Before | After |
| --- | --- | --- |
| A → PC `192.168.43.163` | `dev tailscale0 table 52` | `dev wlan0` |
| A → gateway `192.168.43.1` | `dev tailscale0 table 52` | `dev wlan0` |
| A → internet `223.5.5.5` | fine | fine (unaffected) |
| PC → A ping | unreachable | reachable (14 ms) |
| PC → `http://192.168.43.56:5244/` | unreachable | HTTP 200 |

Toggle check: turning accept-routes off releases the rule (0 rules), turning it
back on re-adds it (1 rule); the log records applied/released/re-applied with no
residue.

## Important

- ARM64 only.
- When both networks share one subnet, only local access can win: devices on the
  phone's own LAN take priority over the peer's identically-numbered subnet. Two
  private networks with the same prefix cannot both be routed.
- Reboot after installing so `service.sh` starts the watchdog with the new code.
- Existing identity under `/data/adb/tailscale-native` remains preserved.

## 重要说明

- 仅支持 ARM64。
- 两侧同网段时只能"本地优先"：本机所在局域网优先于对端同号网段。两个同前缀的私有
  网络无法同时路由，这是拓扑层面的限制，不是配置问题。
- 安装后请重启，让 `service.sh` 用新代码启动看护器。
- `/data/adb/tailscale-native` 中已有的身份会被保留。

## SHA-256

The checksum of this release archive is published in `SHA256SUMS` and attached
to the GitHub release. Verify it after downloading:

本次发布包的校验值公布在 `SHA256SUMS` 中，并随后续 GitHub Release 一并附上。
下载后请核对：

```sh
sha256sum --check SHA256SUMS
```