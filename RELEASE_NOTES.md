# Native Tailscale TUN v0.5.7-zh

Adds a hotspot route guard: accepting tailnet subnet routes no longer breaks the
phone's own hotspot LAN when both sides use `192.168.43.0/24`.

## 中文

新增「热点子网保护」：当两侧都使用 `192.168.43.0/24` 时，接受 Tailnet 子网路由
不再会破坏本机热点的局域网访问。

### 问题

Android 手机热点默认网段是 `192.168.43.0/24`。开启 `accept-routes` 后，若对端
节点也通告 `192.168.43.0/24`，Tailscale 会在策略路由表 52 安装：

```
table 52: 192.168.43.0/24 dev tailscale0
```

于是本机热点下设备的**转发流量**被抢进隧道，表现出「热点里的设备访问不了本地
网络」，而手机自己访问对端局域网却是正常的。两者用了同一网段，靠目的地址无法
区分。

### 修复

仅当热点子网与 table 52 中的路由**确实同网段**时介入，为热点接口插入一条更高
优先级的策略规则：

```
ip rule add iif wlan2 lookup main pref 5000
```

这条规则只影响「从热点接口进来」的流量，让它查 main 表（本地直连）。手机自己
发起的流量不匹配该规则，仍走 table 52 经 Tailscale 到对端局域网。

看护器每 15 秒复查一次，热点开关、网段变化、Tailscale 启停都会自动插入或释放
规则，并记录日志。

### 真机验证（Android 17 / KernelSU / arm64，热点接口 wlan2）

| 测试 | 加规则前 | 加规则后 |
| --- | --- | --- |
| 热点客户端 → `192.168.43.5` | `dev tailscale0`（被劫持） | `dev wlan2`（本地） |
| 手机自身 → `192.168.43.5` | `dev tailscale0` | `dev tailscale0`（不变） |
| 热点客户端 → `8.8.8.8` | 正常经 VPN | 正常经 VPN |

关闭热点后规则自动释放，无残留；无冲突时不插入任何规则，行为与原生一致。

## English

Adds a hotspot route guard: accepting tailnet subnet routes no longer breaks the
phone's own hotspot LAN when both sides use `192.168.43.0/24`.

### Problem

Android hotspots default to `192.168.43.0/24`. With `accept-routes` enabled, if a
peer advertises the same `192.168.43.0/24`, Tailscale installs:

```
table 52: 192.168.43.0/24 dev tailscale0
```

Forwarded traffic from the hotspot's clients is then pulled into the tunnel, so
devices on the hotspot cannot reach the local network, while the phone itself
still reaches the peer LAN. Both sides share one subnet, so the destination
address alone cannot distinguish them.

### Fix

Only when the hotspot subnet actually collides with a route in table 52, a
higher-priority policy rule is added for the hotspot interface:

```
ip rule add iif wlan2 lookup main pref 5000
```

It affects only traffic arriving on the hotspot interface, which then consults
the main table (local link). The phone's own traffic does not match the rule and
still uses table 52 to reach the peer LAN over Tailscale.

The watchdog re-checks every 15 seconds and adds or releases the rule as the
hotspot, subnet, or Tailscale state changes, logging each transition.

### Verified on a real device (Android 17 / KernelSU / arm64, hotspot `wlan2`)

| Test | Before | After |
| --- | --- | --- |
| hotspot client → `192.168.43.5` | `dev tailscale0` (hijacked) | `dev wlan2` (local) |
| phone itself → `192.168.43.5` | `dev tailscale0` | `dev tailscale0` (unchanged) |
| hotspot client → `8.8.8.8` | works via VPN | works via VPN |

Stopping the hotspot releases the rule automatically with no leftovers, and when
there is no conflict no rule is inserted at all.

## Validation

- `node tools/check-i18n.js` reports zero errors across all areas.
- Shell syntax checks pass for every module script.
- Device measurements above were taken with a temporary software hotspot created
  via `cmd wifi start-softap`, and path resolution was verified with
  `ip route get ... from ... iif ...`.

## 验证

- `node tools/check-i18n.js` 全部领域无 error。
- 所有模块脚本通过 shell 语法检查。
- 上述真机数据使用 `cmd wifi start-softap` 临时开热点测得，路径用
  `ip route get ... from ... iif ...` 精确验证。

## Important

- ARM64 only.
- The guard only acts on a real subnet collision; otherwise the routing is left
  exactly as Android configured it.
- Reboot after installing so `service.sh` starts the watchdog with the new code.
- Existing identity under `/data/adb/tailscale-native` remains preserved.

## 重要说明

- 仅支持 ARM64。
- 该保护只在真正发生同网段冲突时介入，否则完全不改动系统原有路由。
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
