#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/i18n.sh"

TAILSCALE="$MODDIR/bin/tailscale"
LOGIN_LOG="$BASE/webui-login.log"
LOGIN_PIDFILE="$BASE/webui-login.pid"

field() {
    printf '%s=%s\n' "$1" "$2"
}

json_value() {
    printf '%s\n' "$1" |
        sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^,\"}]*\).*/\1/p" |
        head -n 1 |
        tr -d '\r'
}

status_command() {
    RUNNING=false
    PID=""
    if pid_is_ours; then
        RUNNING=true
        PID="$(cat "$PIDFILE" 2>/dev/null)"
    fi

    STATUS_JSON=""
    PREFS_JSON=""
    if [ "$RUNNING" = true ]; then
        STATUS_JSON="$($TAILSCALE --socket="$SOCKET" status --json 2>/dev/null)"
        PREFS_JSON="$($TAILSCALE --socket="$SOCKET" debug prefs 2>/dev/null)"
    fi

    BACKEND_STATE="$(json_value "$STATUS_JSON" BackendState)"
    [ -n "$BACKEND_STATE" ] || {
        if [ "$RUNNING" = true ]; then
            BACKEND_STATE=Starting
        else
            BACKEND_STATE=Stopped
        fi
    }

    IPV4="$($TAILSCALE --socket="$SOCKET" ip -4 2>/dev/null | head -n 1)"
    IPV6="$($TAILSCALE --socket="$SOCKET" ip -6 2>/dev/null | head -n 1)"
    VERSION="$("$MODDIR/bin/tailscaled" --version 2>/dev/null | head -n 1)"
    MODULE_VERSION="$(sed -n 's/^version=//p' "$MODDIR/module.prop" | head -n 1)"
    COMMIT="$(tr -d '\r\n ' < "$MODDIR/upstream_commit" 2>/dev/null)"

    INTEGRITY="$(cat "$BASE/last-integrity-status" 2>/dev/null)"
    [ -n "$INTEGRITY" ] || {
        [ -s "$MODDIR/binary-sha256" ] && INTEGRITY=recorded || INTEGRITY=unrecorded
    }

    INTERFACE=down
    ip link show tailscale0 >/dev/null 2>&1 && INTERFACE=up
    OFFICIAL_VPN=false
    official_tailscale_vpn_active && OFFICIAL_VPN=true

    field backend_state "$BACKEND_STATE"
    field ui_language "$(i18n_lang)"
    field running "$RUNNING"
    field pid "$PID"
    field ipv4 "$IPV4"
    field ipv6 "$IPV6"
    field tailscale_version "${VERSION:-unknown}"
    field module_version "${MODULE_VERSION:-unknown}"
    field upstream_commit "${COMMIT:-unknown}"
    field integrity "$INTEGRITY"
    field interface "$INTERFACE"
    field official_vpn "$OFFICIAL_VPN"
    field accept_routes "$(json_value "$PREFS_JSON" RouteAll)"
    field shields_up "$(json_value "$PREFS_JSON" ShieldsUp)"
    HOSTNAME_VALUE="$(json_value "$PREFS_JSON" Hostname)"
    [ -n "$HOSTNAME_VALUE" ] || HOSTNAME_VALUE="$(json_value "$STATUS_JSON" HostName)"
    case "$HOSTNAME_VALUE" in
        ""|localhost|node) HOSTNAME_VALUE="$(android_device_hostname)" ;;
    esac
    field hostname "$HOSTNAME_VALUE"
}

require_running() {
    pid_is_ours || {
        msg error.not_running
        exit 1
    }
}

set_boolean() {
    FLAG="$1"
    VALUE="$2"
    case "$VALUE" in
        true|false) ;;
        *) msg error.setting_value; exit 2 ;;
    esac
    require_running
    "$TAILSCALE" --socket="$SOCKET" set "--$FLAG=$VALUE"
}

print_login_url() {
    case "$1" in
        https://*) ;;
        *) return 1 ;;
    esac

    printf 'login_url=%s\n' "$1"
    msg login.complete_hint
}

print_live_login_result() {
    LOGIN_STATUS_JSON="$($TAILSCALE --socket="$SOCKET" status --json 2>/dev/null)"
    LOGIN_STATE="$(json_value "$LOGIN_STATUS_JSON" BackendState)"
    LOGIN_URL="$(json_value "$LOGIN_STATUS_JSON" AuthURL)"

    if print_login_url "$LOGIN_URL"; then
        return 0
    fi

    if [ "$LOGIN_STATE" = Running ]; then
        msg login.already_signed_in
        return 0
    fi

    return 1
}

login_process_is_ours() {
    LOGIN_PID="$(cat "$LOGIN_PIDFILE" 2>/dev/null)"
    if [ -n "$LOGIN_PID" ] && [ -r "/proc/$LOGIN_PID/cmdline" ]; then
        LOGIN_CMD="$(tr '\000' ' ' < "/proc/$LOGIN_PID/cmdline" 2>/dev/null)"
        case "$LOGIN_CMD" in
            *"$TAILSCALE"*"--socket=$SOCKET"*" up"*) return 0 ;;
        esac
    fi

    rm -f "$LOGIN_PIDFILE"
    return 1
}

print_login_result() {
    if print_live_login_result; then
        return 0
    fi

    LOGIN_URL="$(grep -Eo 'https://[^[:space:]]+' "$LOGIN_LOG" 2>/dev/null |
        head -n 1 |
        tr -d '\r')"
    if print_login_url "$LOGIN_URL"; then
        return 0
    else
        cat "$LOGIN_LOG" 2>/dev/null
        if login_process_is_ours; then
            msg login.url_pending
        fi
    fi
}

case "$1" in
    status)
        if [ "$2" = refresh ] && pid_is_ours; then
            "$TAILSCALE" --socket="$SOCKET" debug force-netmap-update \
                >/dev/null 2>&1 || true
        fi
        status_command
        ;;
    logs)
        tail -n 120 "$LOGFILE" 2>/dev/null || msg logs.empty
        ;;
    clear-logs)
        : > "$LOGFILE"
        msg logs.cleared
        ;;
    diagnostics)
        status_command
        echo
        msg diag.dns_title
        msg diag.dns_body_1
        msg diag.dns_body_2
        msg diag.dns_body_3
        msg diag.dns_body_4
        echo
        msg diag.raw_status
        "$TAILSCALE" --socket="$SOCKET" status 2>&1 || true
        echo
        ip addr show tailscale0 2>&1 || true
        ;;
    start)
        if official_tailscale_vpn_active; then
            msg error.official_vpn
            exit 1
        fi
        start_daemon && msg daemon.started
        ;;
    stop)
        stop_daemon
        msg daemon.stopped
        ;;
    restart)
        if official_tailscale_vpn_active; then
            msg error.official_vpn
            exit 1
        fi
        stop_daemon
        start_daemon && msg daemon.restarted
        ;;
    login)
        require_running
        if print_live_login_result; then
            exit 0
        fi
        if login_process_is_ours; then
            print_login_result
            exit 0
        fi
        rm -f "$LOGIN_PIDFILE"
        : > "$LOGIN_LOG"
        disable_unsupported_android_dns || true
        ensure_device_hostname || true
        nohup "$TAILSCALE" --socket="$SOCKET" up \
            > "$LOGIN_LOG" 2>&1 &
        echo "$!" > "$LOGIN_PIDFILE"
        I=0
        while [ ! -s "$LOGIN_LOG" ] && [ "$I" -lt 8 ]; do
            if print_live_login_result; then
                exit 0
            fi
            sleep 1
            I=$((I + 1))
        done
        print_login_result
        ;;
    verify)
        if verify_binary_hashes; then
            printf '%s\n' verified > "$BASE/last-integrity-status"
            msg verify.ok
        else
            printf '%s\n' modified > "$BASE/last-integrity-status"
            msg verify.failed
            exit 1
        fi
        ;;
    binary-update)
        exec "$MODDIR/action.sh" binary-update
        ;;
    open-admin)
        ADMIN_URL=https://console.tailscale.com/admin/machines
        if am start -a android.intent.action.VIEW -d "$ADMIN_URL" \
            >/dev/null 2>&1
        then
            msg admin.opened
        else
            msg admin.failed
            exit 1
        fi
        ;;
    set-language)
        if i18n_set_lang "$2"; then
            msg lang.saved
        else
            msg error.lang_invalid
            exit 2
        fi
        ;;
    set)
        case "$2" in
            accept-routes) set_boolean accept-routes "$3" ;;
            shields-up) set_boolean shields-up "$3" ;;
            hostname)
                HOSTNAME_VALUE="$3"
                [ "${#HOSTNAME_VALUE}" -le 63 ] || {
                    msg error.hostname_length
                    exit 2
                }
                case "$HOSTNAME_VALUE" in
                    ""|*[!A-Za-z0-9.-]*|.*|-*|*..*|*.|*-)
                        msg error.hostname_chars
                        exit 2
                        ;;
                esac
                require_running
                "$TAILSCALE" --socket="$SOCKET" set "--hostname=$HOSTNAME_VALUE"
                ;;
            *) msg error.unknown_setting; exit 2 ;;
        esac
        ;;
    *)
        msg usage
        exit 2
        ;;
esac
