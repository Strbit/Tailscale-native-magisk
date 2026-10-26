#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/i18n.sh"

TAILSCALE="$MODDIR/bin/tailscale"

if [ "$1" != "binary-update" ]; then
    if ! pm path io.github.a13e300.ksuwebui >/dev/null 2>&1; then
        msg action.webui_required
        msg action.webui_install_hint
        msg action.webui_url
        exit 1
    fi
    msg action.opening
    am start \
        -n io.github.a13e300.ksuwebui/.WebUIActivity \
        -d ksuwebui://webui/native_tailscale \
        --es id native_tailscale \
        --es name "Native Tailscale TUN" >/dev/null 2>&1 || {
            msg error.webui_open
            exit 1
        }
    exit 0
fi

if ! pid_is_ours; then
    msg action.starting_daemon
    if official_tailscale_vpn_active; then
        msg error.official_vpn
        exit 1
    fi
    if ! start_daemon; then
        msgf error.daemon_start "$LOGFILE"
        exit 1
    fi
fi

STATUS_JSON="$($TAILSCALE --socket="$SOCKET" status --json 2>/dev/null)"
BACKEND_STATE="$(printf '%s\n' "$STATUS_JSON" |
    sed -n 's/.*"BackendState"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
    head -n 1)"

case "$BACKEND_STATE" in
    NeedsLogin|NoState)
        msg error.signin_required
        exit 1
        ;;
    NeedsMachineAuth)
        msg action.needs_auth_1
        msg action.needs_auth_2
        exit 1
        ;;
    "")
        msgf error.status_unread "$LOGFILE"
        exit 1
        ;;
esac

REPO_RAW=https://raw.githubusercontent.com/android-kxxt/external_tailscale_prebuilt/main
TMP="$BASE/update.$$"
REMOTE_COMMIT_FILE="$TMP/commit"
POST_COMMIT_FILE="$TMP/commit-after"
INSTALLED_COMMIT_FILE="$MODDIR/upstream_commit"

cleanup() {
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

mkdir -p "$TMP"

valid_commit_marker() {
    MARKER="$1"
    [ "${#MARKER}" -eq 40 ] || return 1
    case "$MARKER" in
        *[!0-9a-f]*)
            return 1
            ;;
    esac
}

connection_summary() {
    LIVE_STATUS_JSON="$($TAILSCALE --socket="$SOCKET" status --json 2>/dev/null)"
    LIVE_STATE="$(printf '%s\n' "$LIVE_STATUS_JSON" |
        sed -n 's/.*"BackendState"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1)"
    LIVE_HOSTNAME="$(printf '%s\n' "$LIVE_STATUS_JSON" |
        sed -n 's/.*"HostName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1)"
    LIVE_IPV4="$($TAILSCALE --socket="$SOCKET" ip -4 2>/dev/null | head -n 1)"
    LIVE_TUN=down
    ip link show tailscale0 >/dev/null 2>&1 && LIVE_TUN=up

    echo
    msg summary.title
    msgf summary.state "$LIVE_STATE"
    if [ -n "$LIVE_IPV4" ]; then
        msgf summary.ip "$LIVE_IPV4"
    else
        msg summary.ip_unassigned
    fi
    msgf summary.device "${LIVE_HOSTNAME:-$(android_device_hostname)}"
    msgf summary.tun "$LIVE_TUN"
    if [ "$LIVE_STATE" = Running ] && [ "$LIVE_TUN" = up ]; then
        msg summary.active
    fi
}

msg update.title
echo

if ! verify_binary_hashes; then
    msg error.hash_mismatch
    msg update.reinstall_hint
    exit 1
fi

CURRENT_VERSION="$("$MODDIR/bin/tailscaled" --version 2>/dev/null | head -n 1)"
[ -n "$CURRENT_VERSION" ] || CURRENT_VERSION="unknown"
msgf update.installed_version "$CURRENT_VERSION"

if ! download_file "$REPO_RAW/commit" "$REMOTE_COMMIT_FILE"; then
    msg error.commit_download
    exit 1
fi

REMOTE_COMMIT="$(tr -d '\r\n ' < "$REMOTE_COMMIT_FILE")"
if ! valid_commit_marker "$REMOTE_COMMIT"; then
    msg error.commit_invalid
    exit 1
fi

INSTALLED_COMMIT="$(cat "$INSTALLED_COMMIT_FILE" 2>/dev/null | tr -d '\r\n ')"
msgf update.installed_commit "${INSTALLED_COMMIT:-unknown}"
msgf update.upstream_commit "$REMOTE_COMMIT"

if [ "$REMOTE_COMMIT" = "$INSTALLED_COMMIT" ]; then
    echo
    msg update.up_to_date
    connection_summary
    exit 0
fi

echo
msg update.downloading

if ! download_file "$REPO_RAW/arm64/tailscale?commit=$REMOTE_COMMIT" "$TMP/tailscale"; then
    msg error.download_tailscale
    exit 1
fi

if ! download_file "$REPO_RAW/arm64/tailscaled?commit=$REMOTE_COMMIT" "$TMP/tailscaled"; then
    msg error.download_tailscaled
    exit 1
fi

if ! download_file "$REPO_RAW/commit" "$POST_COMMIT_FILE"; then
    msg error.commit_recheck
    exit 1
fi

POST_COMMIT="$(tr -d '\r\n ' < "$POST_COMMIT_FILE")"
if ! valid_commit_marker "$POST_COMMIT"; then
    msg error.commit_invalid_after
    exit 1
fi

if [ "$POST_COMMIT" != "$REMOTE_COMMIT" ]; then
    msg error.upstream_changed
    exit 1
fi

chmod 0755 "$TMP/tailscale" "$TMP/tailscaled"

if ! is_elf "$TMP/tailscale" || ! is_elf "$TMP/tailscaled"; then
    msg error.not_elf
    exit 1
fi

NEW_VERSION="$("$TMP/tailscaled" --version 2>/dev/null | head -n 1)"
if [ -z "$NEW_VERSION" ]; then
    msg error.daemon_not_execute
    exit 1
fi

msgf update.downloaded_version "$NEW_VERSION"
sha256sum "$TMP/tailscale" "$TMP/tailscaled" |
    tee "$BASE/last-update.sha256"

WAS_RUNNING=0
pid_is_ours && WAS_RUNNING=1

cp -fp "$MODDIR/bin/tailscale" "$MODDIR/bin/tailscale.bak" 2>/dev/null || true
cp -fp "$MODDIR/bin/tailscaled" "$MODDIR/bin/tailscaled.bak" 2>/dev/null || true
cp -fp "$MODDIR/binary-sha256" "$MODDIR/binary-sha256.bak" 2>/dev/null || true

stop_daemon

cp -f "$TMP/tailscale" "$MODDIR/bin/tailscale"
cp -f "$TMP/tailscaled" "$MODDIR/bin/tailscaled"
chmod 0755 "$MODDIR/bin/tailscale" "$MODDIR/bin/tailscaled"
if ! record_binary_hashes; then
    msg error.record_hashes
    [ -f "$MODDIR/bin/tailscale.bak" ] &&
        cp -f "$MODDIR/bin/tailscale.bak" "$MODDIR/bin/tailscale"
    [ -f "$MODDIR/bin/tailscaled.bak" ] &&
        cp -f "$MODDIR/bin/tailscaled.bak" "$MODDIR/bin/tailscaled"
    [ -f "$MODDIR/binary-sha256.bak" ] &&
        cp -f "$MODDIR/binary-sha256.bak" "$MODDIR/binary-sha256"
    [ "$WAS_RUNNING" -eq 1 ] && start_daemon || true
    exit 1
fi

if official_tailscale_vpn_active; then
    printf '%s\n' "$REMOTE_COMMIT" > "$INSTALLED_COMMIT_FILE"
    echo
    msg update.success
    msg update.not_started_official_vpn
    exit 0
fi

if start_daemon; then
    printf '%s\n' "$REMOTE_COMMIT" > "$INSTALLED_COMMIT_FILE"
    echo
    msg update.success_restarted
    connection_summary
    exit 0
fi

echo
msg update.rolling_back

stop_daemon
[ -f "$MODDIR/bin/tailscale.bak" ] &&
    cp -f "$MODDIR/bin/tailscale.bak" "$MODDIR/bin/tailscale"
[ -f "$MODDIR/bin/tailscaled.bak" ] &&
    cp -f "$MODDIR/bin/tailscaled.bak" "$MODDIR/bin/tailscaled"
[ -f "$MODDIR/binary-sha256.bak" ] &&
    cp -f "$MODDIR/binary-sha256.bak" "$MODDIR/binary-sha256"
chmod 0755 "$MODDIR/bin/tailscale" "$MODDIR/bin/tailscaled"

if [ "$WAS_RUNNING" -eq 1 ]; then
    start_daemon || true
fi

msgf update.rollback_done "$LOGFILE"
exit 1
