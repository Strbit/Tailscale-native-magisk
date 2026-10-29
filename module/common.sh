#!/system/bin/sh

MODDIR="${MODDIR:-${0%/*}}"
BASE=/data/adb/tailscale-native
SOCKET="$BASE/tailscaled.sock"
STATE="$BASE/tailscaled.state"
PIDFILE="$BASE/tailscaled.pid"
LOGFILE="$BASE/tailscaled.log"
LOGIN_PIDFILE="$BASE/webui-login.pid"
WATCHDOG_PIDFILE="$BASE/watchdog.pid"
DAEMON_STOPPED_MARKER="$BASE/daemon-stopped"

mkdir -p "$BASE"
chmod 0700 "$BASE"
umask 077

managed_daemon_pid() {
    for CANDIDATE in $(pidof tailscaled 2>/dev/null); do
        [ -r "/proc/$CANDIDATE/cmdline" ] || continue
        CMD="$(tr '\000' ' ' < "/proc/$CANDIDATE/cmdline" 2>/dev/null)"
        case "$CMD" in
            *"--state=$STATE"*"--socket=$SOCKET"*"--tun=tailscale0"*)
                echo "$CANDIDATE"
                return 0
                ;;
        esac
    done
    return 1
}

pid_is_ours() {
    PID="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$PID" ] && [ -r "/proc/$PID/cmdline" ]; then
        CMD="$(tr '\000' ' ' < "/proc/$PID/cmdline" 2>/dev/null)"
        case "$CMD" in
            *"--state=$STATE"*"--socket=$SOCKET"*"--tun=tailscale0"*)
                return 0
                ;;
        esac
    fi

    PID="$(managed_daemon_pid)" || return 1
    echo "$PID" > "$PIDFILE"
    return 0
}

official_tailscale_vpn_active() {
    dumpsys connectivity 2>/dev/null |
        grep -Fq "VPN:com.tailscale.ipn"
}

disable_unsupported_android_dns() {
    [ -x "$MODDIR/bin/tailscale" ] || return 1
    DNS_I=0
    while [ "$DNS_I" -lt 5 ]; do
        "$MODDIR/bin/tailscale" --socket="$SOCKET" set \
            --accept-dns=false >/dev/null 2>&1 && return 0
        sleep 1
        DNS_I=$((DNS_I + 1))
    done
    return 1
}

legacy_pid_list() {
    for P in $(pidof tailscaled 2>/dev/null); do
        [ -r "/proc/$P/cmdline" ] || continue
        CMD="$(tr '\000' ' ' < "/proc/$P/cmdline" 2>/dev/null)"
        case "$CMD" in
            /data/adb/tailscale-native/bin/tailscaled*)
                echo "$P"
                ;;
        esac
    done
}

stop_legacy_daemon() {
    LEGACY_PIDS="$(legacy_pid_list)"
    [ -n "$LEGACY_PIDS" ] || return 0

    for P in $LEGACY_PIDS; do
        kill "$P" 2>/dev/null
    done

    I=0
    while [ "$I" -lt 15 ]; do
        REMAINING="$(legacy_pid_list)"
        [ -z "$REMAINING" ] && break
        sleep 1
        I=$((I + 1))
    done

    for P in $(legacy_pid_list); do
        kill -9 "$P" 2>/dev/null
    done

    rm -f "$PIDFILE" "$SOCKET"
}

stop_pending_login() {
    LOGIN_PID="$(cat "$LOGIN_PIDFILE" 2>/dev/null)"
    if [ -n "$LOGIN_PID" ] && [ -r "/proc/$LOGIN_PID/cmdline" ]; then
        LOGIN_CMD="$(tr '\000' ' ' < "/proc/$LOGIN_PID/cmdline" 2>/dev/null)"
        case "$LOGIN_CMD" in
            *"$MODDIR/bin/tailscale"*"--socket=$SOCKET"*" up"*)
                kill "$LOGIN_PID" 2>/dev/null || true
                ;;
        esac
    fi
    rm -f "$LOGIN_PIDFILE"
}

stop_daemon() {
    stop_pending_login

    if ! pid_is_ours; then
        rm -f "$PIDFILE" "$SOCKET"
        return 0
    fi

    PID="$(cat "$PIDFILE")"
    kill "$PID" 2>/dev/null

    I=0
    while [ "$I" -lt 15 ] && pid_is_ours; do
        sleep 1
        I=$((I + 1))
    done

    if pid_is_ours; then
        kill -9 "$PID" 2>/dev/null
        sleep 1
    fi

    rm -f "$PIDFILE" "$SOCKET"
}

# Move a pid out of the app cgroup buckets into the system ones.
#
# setsid() only changes the session and process group. The cgroup is inherited
# from the parent, and Android sweeps an app's descendants through BOTH
# hierarchies:
#   - cgroup v1 memory controller, mounted at /dev/memcg, path 4:memory:/apps
#   - cgroup v2 unified hierarchy, mounted at /sys/fs/cgroup, path
#     0::/apps/uid_XXXXX/pid_YYYYY
#
# A daemon started from the manager app is nested under the app's cgroup in both
# and is removed with it by a recents "SwipeUpClean". Moving only the v1 side is
# not enough: the v2 path stays under /apps and the process still dies. Both
# must be moved.
move_daemon_to_system_cgroup() {
    MOVE_PID="${1:-}"
    [ -n "$MOVE_PID" ] || return 1
    MOVE_ANY=0

    # cgroup v1 memory controller.
    for TARGET in \
        /dev/memcg/system/cgroup.procs \
        /dev/memcg/cgroup.procs
    do
        [ -w "$TARGET" ] || continue
        printf '%s\n' "$MOVE_PID" > "$TARGET" 2>/dev/null || continue
        case "$(grep -m 1 '^4:memory:' "/proc/$MOVE_PID/cgroup" 2>/dev/null)" in
            *":/apps"*) continue ;;
            ?*) MOVE_ANY=1; break ;;
        esac
    done

    # cgroup v2 unified hierarchy: this is the subtree SwipeUpClean walks.
    for TARGET in \
        /sys/fs/cgroup/system/cgroup.procs \
        /sys/fs/cgroup/cgroup.procs
    do
        [ -w "$TARGET" ] || continue
        printf '%s\n' "$MOVE_PID" > "$TARGET" 2>/dev/null || continue
        case "$(grep -m 1 '^0::' "/proc/$MOVE_PID/cgroup" 2>/dev/null)" in
            *":/apps"*) continue ;;
            ?*) MOVE_ANY=1; break ;;
        esac
    done

    [ "$MOVE_ANY" -eq 1 ]
}

# --- 本地热点子网保护 -------------------------------------------------------
#
# Tailscale 的 accept-routes 会把对端通告的子网路由装进 table 52。Android 手机
# 热点默认使用 192.168.43.0/24，一旦对端通告的也是同一网段，本机热点下设备的
# 转发流量就会被 table 52 抢走，表现为"热点里的设备访问不了本地网络"。
#
# 这里为热点接口单独加一条更高优先级的策略规则，让「从热点接口进来的流量」查
# main 表（本地直连）而不是 table 52。本机自己发起的流量不受影响，仍然经由
# Tailscale 访问对端局域网。
HOTSPOT_RULE_PREF=5000
HOTSPOT_GUARDED="$BASE/hotspot-guarded"

# 列出热点类接口名（拥有 A.B.C.1/24 地址且不属于常见非热点接口）。
hotspot_interfaces() {
    for IF in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}'); do
        case "$IF" in
            lo|dummy0|tailscale0|p2p*|wifi-aware0|sit0|gre0|gretap0|erspan0|\
tunl0|ip_vti0|ip6tnl0|ip6gre0|ip6_vti0|rmnet*|r_rmnet*|mihoyo|ifb*)
                continue
                ;;
        esac
        ADDR="$(ip -4 addr show "$IF" 2>/dev/null |
            sed -n 's/.*inet \([0-9.]*\)\/24.*/\1/p' | head -1)"
        [ -n "$ADDR" ] || continue
        case "$ADDR" in
            *.1) printf '%s\n' "$IF" ;;
        esac
    done
}

# 取接口的 /24 网段（例如 192.168.43.0/24）
hotspot_subnet() {
    HS_ADDR="$(ip -4 addr show "$1" 2>/dev/null |
        sed -n 's/.*inet \([0-9.]*\)\/24.*/\1/p' | head -1)"
    [ -n "$HS_ADDR" ] || return 1
    printf '%s.0/24\n' "${HS_ADDR%.*}"
}

hotspot_rule_present() {
    # 接口消失后规则会显示为 "iif wlan2 [detached] lookup main"，
    # 因此分两步匹配，不能要求两个片段紧邻。
    ip rule show 2>/dev/null | grep "iif $1" | grep -q "lookup main"
}

# 本模块插入的保护规则所对应的接口名（含已 detached 的）
guarded_rule_ifaces() {
    ip rule show 2>/dev/null |
        sed -n "s/^${HOTSPOT_RULE_PREF}:.*iif \([^ ]*\).*lookup main.*/\1/p" |
        sort -u
}

# 供日志使用：调用方未加载 i18n.sh 时退化为纯文本，避免写出空行
guard_msgf() {
    if command -v msgf >/dev/null 2>&1; then
        msgf "$@"
    else
        shift
        printf '%s\n' "$*"
    fi
}

# 让热点子网与 table 52 的冲突自动隔离；无冲突时保持系统原状。
guard_hotspot_route() {
    ip route show table 52 >/dev/null 2>&1 || {
        # Tailscale 未运行或没有 table 52：清掉我们加过的规则
        cleanup_hotspot_rules
        return 0
    }

    WANT=""
    for IF in $(hotspot_interfaces); do
        SUBNET="$(hotspot_subnet "$IF")" || continue
        # 只有真的和 Tailscale 路由表冲突才介入
        if ip route show table 52 2>/dev/null | grep -q "^$SUBNET "; then
            WANT="$WANT $IF"
            if ! hotspot_rule_present "$IF"; then
                ip rule add iif "$IF" lookup main pref "$HOTSPOT_RULE_PREF" 2>/dev/null &&
                    echo "$(date): $(guard_msgf guard.hotspot_applied "$IF" "$SUBNET")" >> "$LOGFILE"
            fi
        fi
    done

    # 释放不再需要的规则：热点关闭、冲突消失、或接口已消失（detached）
    for IF in $(guarded_rule_ifaces); do
        case " $WANT " in
            *" $IF "*) continue ;;
        esac
        ip rule del iif "$IF" lookup main pref "$HOTSPOT_RULE_PREF" 2>/dev/null &&
            echo "$(date): $(guard_msgf guard.hotspot_removed "$IF")" >> "$LOGFILE"
    done

    # 记录本轮结果，便于排查
    printf '%s\n' $WANT | grep . > "$HOTSPOT_GUARDED" 2>/dev/null || : > "$HOTSPOT_GUARDED"
}

cleanup_hotspot_rules() {
    for IF in $(guarded_rule_ifaces); do
        [ -n "$IF" ] || continue
        ip rule del iif "$IF" lookup main pref "$HOTSPOT_RULE_PREF" 2>/dev/null
    done
    : > "$HOTSPOT_GUARDED"
}

watchdog_pid() {
    W_PID="$(cat "$WATCHDOG_PIDFILE" 2>/dev/null)"
    [ -n "$W_PID" ] || return 1
    [ -r "/proc/$W_PID/cmdline" ] || return 1
    W_CMD="$(tr '\000' ' ' < "/proc/$W_PID/cmdline" 2>/dev/null)"
    case "$W_CMD" in
        *"watchdog.sh"*) printf '%s\n' "$W_PID"; return 0 ;;
    esac
    return 1
}

ensure_watchdog() {
    watchdog_pid >/dev/null 2>&1 && return 0
    [ -x "$MODDIR/watchdog.sh" ] || return 1
    rm -f "$WATCHDOG_PIDFILE"
    if command -v setsid >/dev/null 2>&1; then
        setsid "$MODDIR/watchdog.sh" >/dev/null 2>&1 &
    else
        "$MODDIR/watchdog.sh" >/dev/null 2>&1 &
    fi
    W_I=0
    while [ "$W_I" -lt 10 ]; do
        W_REAL="$(watchdog_pid 2>/dev/null)"
        if [ -n "$W_REAL" ]; then
            # The watchdog must outlive the manager app too, otherwise it is
            # useless exactly when it is needed.
            move_daemon_to_system_cgroup "$W_REAL" || true
            return 0
        fi
        sleep 1
        W_I=$((W_I + 1))
    done
    return 1
}

stop_watchdog() {
    W_PID="$(watchdog_pid 2>/dev/null)"
    [ -n "$W_PID" ] || { rm -f "$WATCHDOG_PIDFILE"; return 0; }
    kill "$W_PID" 2>/dev/null || true
    rm -f "$WATCHDOG_PIDFILE"
    return 0
}

start_daemon() {
    if pid_is_ours; then
        disable_unsupported_android_dns || true
        return 0
    fi

    if pidof tailscaled >/dev/null 2>&1; then
        echo "$(date): refusing to start: another tailscaled already exists" \
            >> "$LOGFILE"
        return 1
    fi

    # A daemon killed while running (for example when the KernelSU or Magisk
    # manager app was swiped away) can leave tailscale0 behind. Clear the stale
    # interface instead of refusing to start on every later attempt.
    if ip link show tailscale0 >/dev/null 2>&1; then
        echo "$(date): cleaning up stale tailscale0 interface" >> "$LOGFILE"
        "$MODDIR/bin/tailscaled" \
            --cleanup \
            --state="$STATE" \
            --statedir="$BASE" \
            --socket="$SOCKET" \
            --tun=tailscale0 \
            >>"$LOGFILE" 2>&1 || true
        rm -f "$PIDFILE" "$SOCKET"
    fi

    stop_pending_login

    [ -x "$MODDIR/bin/tailscaled" ] || return 1
    rm -f "$PIDFILE" "$SOCKET"

    # Detach into a fresh session. When the daemon is started from the manager
    # app's Action button it would otherwise join that app's process group, and
    # closing the app would take the daemon down with it. setsid gives the
    # daemon its own session so it survives the manager going away. Booting via
    # service.sh is already init-parented and unaffected either way.
    if command -v setsid >/dev/null 2>&1; then
        setsid "$MODDIR/bin/tailscaled" \
            --state="$STATE" \
            --statedir="$BASE" \
            --socket="$SOCKET" \
            --tun=tailscale0 \
            --verbose=1 \
            >>"$LOGFILE" 2>&1 &
    else
        "$MODDIR/bin/tailscaled" \
            --state="$STATE" \
            --statedir="$BASE" \
            --socket="$SOCKET" \
            --tun=tailscale0 \
            --verbose=1 \
            >>"$LOGFILE" 2>&1 &
    fi

    PID=$!
    echo "$PID" > "$PIDFILE"

    I=0
    while [ "$I" -lt 20 ]; do
        if [ -S "$SOCKET" ] && pid_is_ours; then
            # setsid may fork, so record the real daemon pid rather than $!.
            REAL_PID="$(managed_daemon_pid)"
            if [ -n "$REAL_PID" ]; then
                echo "$REAL_PID" > "$PIDFILE"
                move_daemon_to_system_cgroup "$REAL_PID" || true
            fi
            if ! disable_unsupported_android_dns; then
                echo "$(date): could not disable unsupported native Android DNS preference" \
                    >> "$LOGFILE"
            fi
            return 0
        fi
        sleep 1
        I=$((I + 1))
    done

    return 1
}

download_file() {
    URL="$1"
    OUT="$2"

    rm -f "$OUT"

    # Prefer the system curl. Android ships /system/bin/curl on recent releases
    # and KernelSU/Magisk boxes frequently have no wget at all, so relying on
    # wget first made every update fail on those devices.
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 20 --max-time 180 \
            -o "$OUT" "$URL" && [ -s "$OUT" ] && return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -q -T 45 -O "$OUT" "$URL" && [ -s "$OUT" ] && return 0
    fi

    TERMUX_CURL=/data/data/com.termux/files/usr/bin/curl
    if [ -x "$TERMUX_CURL" ]; then
        "$TERMUX_CURL" -fsSL --connect-timeout 20 --max-time 180 \
            -o "$OUT" "$URL" && [ -s "$OUT" ] && return 0
    fi

    return 1
}

is_elf() {
    FILE="$1"
    MAGIC="$(
        dd if="$FILE" bs=4 count=1 2>/dev/null |
        od -An -tx1 2>/dev/null |
        tr -d ' \n'
    )"
    [ "$MAGIC" = "7f454c46" ]
}

record_binary_hashes() {
    (
        cd "$MODDIR" || exit 1
        sha256sum bin/tailscale bin/tailscaled > binary-sha256
        chmod 0600 binary-sha256
    ) && printf '%s\n' verified > "$BASE/last-integrity-status"
}

verify_binary_hashes() {
    [ -s "$MODDIR/binary-sha256" ] || return 1
    (cd "$MODDIR" && sha256sum -c binary-sha256 >/dev/null 2>&1)
}

android_device_hostname() {
    DEVICE_NAME="$(settings get global device_name 2>/dev/null)"
    [ -n "$DEVICE_NAME" ] && [ "$DEVICE_NAME" != null ] ||
        DEVICE_NAME="$(settings get secure bluetooth_name 2>/dev/null)"
    [ -n "$DEVICE_NAME" ] && [ "$DEVICE_NAME" != null ] ||
        DEVICE_NAME="$(getprop ro.product.marketname 2>/dev/null)"
    [ -n "$DEVICE_NAME" ] ||
        DEVICE_NAME="$(getprop ro.product.model 2>/dev/null)"
    [ -n "$DEVICE_NAME" ] || DEVICE_NAME=android-device

    printf '%s\n' "$DEVICE_NAME" |
        tr '[:upper:]' '[:lower:]' |
        sed 's/[^a-z0-9.-]/-/g; s/--*/-/g; s/^[.-]*//; s/[.-]*$//' |
        cut -c1-63
}

ensure_device_hostname() {
    [ -x "$MODDIR/bin/tailscale" ] || return 1
    PREFS_JSON="$("$MODDIR/bin/tailscale" --socket="$SOCKET" debug prefs 2>/dev/null)"
    CONFIGURED_HOSTNAME="$(printf '%s\n' "$PREFS_JSON" |
        sed -n 's/.*"Hostname"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1)"
    [ -z "$CONFIGURED_HOSTNAME" ] || return 0
    DEVICE_HOSTNAME="$(android_device_hostname)"
    [ -n "$DEVICE_HOSTNAME" ] || return 1
    "$MODDIR/bin/tailscale" --socket="$SOCKET" set \
        --hostname="$DEVICE_HOSTNAME" >/dev/null 2>&1
}
