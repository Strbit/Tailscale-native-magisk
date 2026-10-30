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

# --- 本地网段保护 -----------------------------------------------------------
#
# Tailscale 的 accept-routes 会把对端通告的子网路由装进 table 52。Android 手机
# 热点默认使用 192.168.43.0/24，一旦对端通告的也是同一网段，本机与局域网之间的
# 流量会被 tailscale0 抢走，表现为「热点里的设备访问不了本地网络」甚至整段断网。
#
# 早期版本只加了 `iif <热点接口>` 规则，有两个缺口：
#   1. 只覆盖去程。回程包（外网 → 客户端）从 rmnet/wlan0 进入，不匹配 iif，
#      仍被表 52 吞掉，客户端 TCP 卡在 SYN_RECV（实测 conntrack 满屏 SYN_RECV）。
#   2. 只识别「地址以 .1 结尾的热点接口」。本机作为客户端接入同网段的网络时
#      （例如手机连另一台手机的热点），本机自身流量同样被抢，却没有保护。
#
# 现在改为按「网段重叠」判定，并插入一条目标匹配的规则：
#   pref 4999  to <本地网段> lookup main
# 它优先于 Tailscale 的 5270，让该网段的所有流量（去程、回程、本机自身）
# 都回到本地直连路由。无冲突时自动释放，完全保持系统原状。
GUARD_PREF_TO=4999
GUARD_RULES_FILE="$BASE/guard-rules"
GUARD_LOCAL_LIST="$BASE/guard-local.tmp"

# 本机各接口的 IPv4 网段，输出 "接口|地址|前缀长度"
local_ipv4_subnets() {
    for IF in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}'); do
        case "$IF" in
            lo|dummy0|tailscale0|p2p*|wifi-aware0|sit0|gre0|gretap0|erspan0|\
tunl0|ip_vti0|ip6tnl0|ip6gre0|ip6_vti0|rmnet*|r_rmnet*|mihoyo|ifb*)
                continue
                ;;
        esac
        ip -o -4 addr show "$IF" 2>/dev/null | while read -r LINE; do
            CIDR="$(printf '%s\n' "$LINE" |
                sed -n 's/.*inet \([0-9.]*\/[0-9]*\).*/\1/p')"
            [ -n "$CIDR" ] || continue
            ADDR="${CIDR%%/*}"
            PREFIX="${CIDR##*/}"
            [ "$PREFIX" -le 30 ] 2>/dev/null || continue
            printf '%s|%s|%s\n' "$IF" "$ADDR" "$PREFIX"
        done
    done
}

# 计算网段地址：network_address 192.168.43.56 24 -> 192.168.43.0
network_address() {
    printf '%s %s\n' "$1" "$2" | awk '{
        split($1, o, ".");
        n = ($2 + 0);
        if (n >= 32) { print $1; exit }
        full = int(n / 8);
        rem  = n % 8;
        out  = "";
        for (i = 1; i <= 4; i++) {
            if (i <= full) v = o[i] + 0;
            else if (i == full + 1) v = (o[i] + 0) - ((o[i] + 0) % (2 ^ (8 - rem)));
            else v = 0;
            out = out (i > 1 ? "." : "") v;
        }
        print out;
    }'
}

# 两个 IPv4 网段是否重叠（含包含关系，例如 192.168.0.0/16 覆盖 192.168.43.0/24）
subnets_overlap() {
    A_ADDR="${1%%/*}"
    A_LEN="${1##*/}"
    B_ADDR="${2%%/*}"
    B_LEN="${2##*/}"
    [ -n "$A_LEN" ] && [ -n "$B_LEN" ] || return 1
    MIN="$A_LEN"
    [ "$B_LEN" -lt "$MIN" ] && MIN="$B_LEN"
    [ "$(network_address "$A_ADDR" "$MIN")" = "$(network_address "$B_ADDR" "$MIN")" ]
}

# 若 table 52 中存在与给定网段重叠的路由，输出该路由网段
tailnet_claims_subnet() {
    ip route show table 52 2>/dev/null | while read -r ROUTE; do
        [ -n "$ROUTE" ] || continue
        R_NET="${ROUTE%% *}"
        case "$R_NET" in
            */*) ;;
            *) continue ;;
        esac
        if subnets_overlap "$1" "$R_NET"; then
            printf '%s\n' "$R_NET"
            break
        fi
    done
}

# 本模块当前生效的保护规则（pref 4999），输出 "to <网段>"
guard_active_rules() {
    ip rule show 2>/dev/null | while read -r LINE; do
        case "$LINE" in
            "${GUARD_PREF_TO}:"*)
                SEL="$(printf '%s\n' "$LINE" |
                    sed -n 's/.*\(to [^ ]*\) lookup main.*/\1/p')"
                [ -n "$SEL" ] && printf '%s\n' "$SEL"
                ;;
        esac
    done
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

# 让本地网段与 table 52 的冲突自动隔离；无冲突时保持系统原状。
guard_hotspot_route() {
    local_ipv4_subnets > "$GUARD_LOCAL_LIST" 2>/dev/null

    WANT=""
    if ip route show table 52 >/dev/null 2>&1; then
        while IFS='|' read -r IF ADDR PREFIX; do
            [ -n "$IF" ] || continue
            SUBNET="$(network_address "$ADDR" "$PREFIX")/$PREFIX"
            ROUTE_NET="$(tailnet_claims_subnet "$SUBNET")"
            [ -n "$ROUTE_NET" ] || continue
            WANT="$WANT
to $SUBNET"
        done < "$GUARD_LOCAL_LIST"
    fi

    WANT="$(printf '%s\n' "$WANT" | grep . | sort -u)"
    HAVE="$(guard_active_rules | grep . | sort -u)"

    # 新增缺失的规则
    printf '%s\n' "$WANT" | while IFS= read -r SEL; do
        [ -n "$SEL" ] || continue
        printf '%s\n' "$HAVE" | grep -qxF "$SEL" && continue
        # SEL 形如 "to 192.168.43.0/24"，需要按词传入
        if ip rule add $SEL lookup main pref "$GUARD_PREF_TO" 2>/dev/null; then
            echo "$(date): $(guard_msgf guard.hotspot_applied "$SEL")" >> "$LOGFILE"
        fi
    done

    # 释放不再需要的规则（冲突消失、接口消失、Tailscale 停止）
    printf '%s\n' "$HAVE" | while IFS= read -r SEL; do
        [ -n "$SEL" ] || continue
        printf '%s\n' "$WANT" | grep -qxF "$SEL" && continue
        if ip rule del $SEL lookup main pref "$GUARD_PREF_TO" 2>/dev/null; then
            echo "$(date): $(guard_msgf guard.hotspot_removed "$SEL")" >> "$LOGFILE"
        fi
    done

    printf '%s\n' "$WANT" > "$GUARD_RULES_FILE" 2>/dev/null
    rm -f "$GUARD_LOCAL_LIST" 2>/dev/null
}

cleanup_hotspot_rules() {
    guard_active_rules | while IFS= read -r SEL; do
        [ -n "$SEL" ] || continue
        ip rule del $SEL lookup main pref "$GUARD_PREF_TO" 2>/dev/null
    done
    : > "$GUARD_RULES_FILE"
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
