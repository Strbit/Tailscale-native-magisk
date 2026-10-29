# Native Tailscale TUN v0.5.8-zh

Fixes hotspot-guard rule cleanup so stale policy rules never accumulate.

## 中文

修复热点保护的规则清理缺陷，避免策略规则永久残留。

### 本次修复

`0.5.7` 判断规则是否存在时用的是 `grep "iif wlan2 lookup main"`。但接口消失后
`ip rule show` 会显示为：

```
5000: from all iif wlan2 [detached] lookup main
```

`[detached]` 插在两个片段之间，导致匹配失败，规则永远不会被删除。真机上确实
留下了两条（`192.168.43.1`、`wlan2`，前两轮测试的遗留）。

现在改为分两步匹配，并新增 `guarded_rule_ifaces` 直接枚举本模块插入的所有规则；
本轮不再需要的（热点关闭、冲突消失、接口已消失）一律删除。

另外 `guard_hotspot_route` 的日志改用 `guard_msgf`：调用方没加载 `i18n.sh` 时
退化为纯文本，不再写出空日志行。

### 验证

- 清理前：2 条 detached 残留规则；
- 调用一次 `guard_hotspot_route` 后：0 条残留；
- 热点开启/关闭循环中，规则的插入与释放均正常，日志记录完整。

### 功能回顾（0.5.7 引入）

热点子网与 Tailnet 子网路由同网段时，为热点接口插入
`ip rule add iif <热点接口> lookup main pref 5000`：

| 测试 | 结果 |
| --- | --- |
| 热点客户端 → 同网段设备 | `dev <热点接口>`（留在本地） |
| 手机自身 → 对端局域网 | `dev tailscale0`（不受影响） |
| 热点客户端 → 互联网 | 正常经 VPN |

## English

Fixes hotspot-guard rule cleanup so stale policy rules never accumulate.

### Fixed

`0.5.7` detected an existing rule with `grep "iif wlan2 lookup main"`. But once
the interface disappears, `ip rule show` renders:

```
5000: from all iif wlan2 [detached] lookup main
```

The `[detached]` marker sits between the two fragments, so the match failed and
the rule was never removed. Two such rules were actually left behind on the test
device (`192.168.43.1`, `wlan2`, from earlier test rounds).

It now matches in two steps and adds `guarded_rule_ifaces` to enumerate every
rule this module inserted, removing all that are no longer needed this round
(hotspot closed, conflict gone, interface disappeared).

Logging in `guard_hotspot_route` now uses `guard_msgf`, which degrades to plain
text when the caller did not load `i18n.sh`, instead of writing empty log lines.

### Verified

- before cleanup: 2 detached leftover rules;
- after one `guard_hotspot_route` call: 0 leftovers;
- across hotspot on/off cycles the rule is added and released correctly with
  complete log records.

### Feature recap (introduced in 0.5.7)

When the hotspot subnet collides with a tailnet subnet route, a
higher-priority rule is added for the hotspot interface:

```
ip rule add iif <hotspot-iface> lookup main pref 5000
```

| Test | Result |
| --- | --- |
| hotspot client → same-subnet device | `dev <hotspot-iface>` (stays local) |
| phone itself → peer LAN | `dev tailscale0` (unaffected) |
| hotspot client → internet | works via VPN |

## Important

- ARM64 only.
- The guard acts only on a real subnet collision.
- Reboot after installing so `service.sh` starts the watchdog with the new code.
- Existing identity under `/data/adb/tailscale-native` remains preserved.

## 重要说明

- 仅支持 ARM64。
- 该保护只在真正发生同网段冲突时介入。
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
