#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/i18n.sh"

# Move any older standalone launcher completely out of service.d.
LEGACY_DIR=/data/adb/service.d-disabled
mkdir -p "$LEGACY_DIR"
for OLD in \
    /data/adb/service.d/99-tailscale-native.sh \
    /data/adb/service.d/99-tailscale-native.sh.disabled \
    /data/adb/service.d/99-tailscale-native.sh.disabled-by-module
do
    if [ -e "$OLD" ]; then
        chmod 0644 "$OLD" 2>/dev/null
        mv -f "$OLD" "$LEGACY_DIR/" 2>/dev/null
    fi
done

# Stop the daemon launched by the old standalone path before touching its socket.
stop_legacy_daemon

# Clean stale kernel routes/interfaces left by an interrupted prior run.
"$MODDIR/bin/tailscaled" \
    --cleanup \
    --state="$STATE" \
    --statedir="$BASE" \
    --socket="$SOCKET" \
    --tun=tailscale0 \
    >>"$LOGFILE" 2>&1 || true

# The patched routing setup is safest after Android's networking services
# settle. Polling getprop also works on Magisk versions predating resetprop -w.
I=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] &&
    [ "$I" -lt 120 ]
do
    sleep 1
    I=$((I + 1))
done

I=0
while [ ! -e /dev/tun ] && [ "$I" -lt 30 ]; do
    sleep 1
    I=$((I + 1))
done

if official_tailscale_vpn_active; then
    echo "$(date): $(msg service.official_vpn_active)" >> "$LOGFILE"
    exit 0
fi

if ! start_daemon; then
    echo "$(date): $(msg service.start_failed)" >> "$LOGFILE"
    exit 1
fi

echo "$(date): $(msg service.started)" >> "$LOGFILE"

if ensure_device_hostname; then
    echo "$(date): $(msg service.hostname_checked)" >> "$LOGFILE"
fi

STATUS_JSON="$("$MODDIR/bin/tailscale" --socket="$SOCKET" status --json 2>/dev/null)"
if printf '%s\n' "$STATUS_JSON" |
    grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"(NeedsLogin|NoState)"'
then
    echo "$(date): $(msg service.auth_required)" >> "$LOGFILE"
fi
