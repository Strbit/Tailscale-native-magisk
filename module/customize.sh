#!/system/bin/sh

# 安装器在 recovery 环境运行，可能没有中文字体：所有中文提示都附带英文括注。
. "$MODPATH/i18n.sh"

ui_print "*******************************"
msg install.header
ui_print "*******************************"

[ "$ARCH" = "arm64" ] || abort "$(msg install.arm64_only)"

RAW=https://raw.githubusercontent.com/android-kxxt/external_tailscale_prebuilt/main
mkdir -p "$MODPATH/bin"
PRE_COMMIT_FILE="$MODPATH/.upstream-commit-before"
POST_COMMIT_FILE="$MODPATH/.upstream-commit-after"

download_installer_file() {
    URL="$1"
    OUT="$2"

    rm -f "$OUT"

    # Prefer the system curl. Android ships /system/bin/curl on recent releases
    # and some devices have no wget at all, which made installation always fall
    # back to reusing existing binaries.
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

is_elf_installer() {
    FILE="$1"
    MAGIC="$(
        dd if="$FILE" bs=4 count=1 2>/dev/null |
        od -An -tx1 2>/dev/null |
        tr -d ' \n'
    )"
    [ "$MAGIC" = "7f454c46" ]
}

valid_commit_marker_installer() {
    MARKER="$1"
    [ "${#MARKER}" -eq 40 ] || return 1
    case "$MARKER" in
        *[!0-9a-f]*)
            return 1
            ;;
    esac
}

msg install.fetching

FETCHED=false
if download_installer_file "$RAW/commit" "$PRE_COMMIT_FILE"; then
    PRE_COMMIT="$(tr -d '\r\n ' < "$PRE_COMMIT_FILE")"

    if valid_commit_marker_installer "$PRE_COMMIT" &&
        download_installer_file \
            "$RAW/arm64/tailscale?commit=$PRE_COMMIT" \
            "$MODPATH/bin/tailscale" &&
        download_installer_file \
            "$RAW/arm64/tailscaled?commit=$PRE_COMMIT" \
            "$MODPATH/bin/tailscaled" &&
        download_installer_file "$RAW/commit" "$POST_COMMIT_FILE"
    then
        POST_COMMIT="$(tr -d '\r\n ' < "$POST_COMMIT_FILE")"
        if valid_commit_marker_installer "$POST_COMMIT" &&
            [ "$POST_COMMIT" = "$PRE_COMMIT" ]
        then
            printf '%s\n' "$PRE_COMMIT" > "$MODPATH/upstream_commit"
            FETCHED=true
        else
            msg install.upstream_changed
        fi
    fi
fi

rm -f "$PRE_COMMIT_FILE" "$POST_COMMIT_FILE"

if [ "$FETCHED" != true ]; then
    msg install.download_failed
    rm -f "$MODPATH/upstream_commit"

    for SRC in \
        /data/local/tmp/ts-native \
        /data/adb/tailscale-native/bin \
        /data/adb/modules/native_tailscale/bin
    do
        if [ -x "$SRC/tailscale" ] && [ -x "$SRC/tailscaled" ]; then
            cp -f "$SRC/tailscale" "$MODPATH/bin/tailscale"
            cp -f "$SRC/tailscaled" "$MODPATH/bin/tailscaled"
            msgf install.reused_binaries "$SRC"
            FETCHED=true
            break
        fi
    done
fi

[ "$FETCHED" = true ] || abort "$(msg install.abort_no_binaries)"

chmod 0755 "$MODPATH/bin/tailscale" "$MODPATH/bin/tailscaled"

(
    cd "$MODPATH" || abort "$(msg install.abort_cd)"
    sha256sum bin/tailscale bin/tailscaled > binary-sha256 ||
        abort "$(msg install.abort_hashes)"
)
mkdir -p /data/adb/tailscale-native
chmod 0700 /data/adb/tailscale-native
printf '%s\n' verified > /data/adb/tailscale-native/last-integrity-status

is_elf_installer "$MODPATH/bin/tailscale" ||
    abort "$(msg install.abort_tailscale_elf)"
is_elf_installer "$MODPATH/bin/tailscaled" ||
    abort "$(msg install.abort_tailscaled_elf)"

TS_VERSION="$("$MODPATH/bin/tailscaled" --version 2>/dev/null | head -n 1)"
[ -n "$TS_VERSION" ] || abort "$(msg install.abort_exec)"
msgf install.installed_version "$TS_VERSION"

# Prevent any standalone launcher from running alongside the module.
# Magisk executes every executable file in service.d regardless of its suffix,
# so move legacy scripts fully outside that directory.
LEGACY_DIR=/data/adb/service.d-disabled
mkdir -p "$LEGACY_DIR"

MOVED_OLD=false
for OLD_SERVICE in \
    /data/adb/service.d/99-tailscale-native.sh \
    /data/adb/service.d/99-tailscale-native.sh.disabled \
    /data/adb/service.d/99-tailscale-native.sh.disabled-by-module
do
    if [ -e "$OLD_SERVICE" ]; then
        chmod 0644 "$OLD_SERVICE" 2>/dev/null
        mv -f "$OLD_SERVICE" "$LEGACY_DIR/" 2>/dev/null
        MOVED_OLD=true
    fi
done

if [ "$MOVED_OLD" = true ]; then
    msg install.moved_legacy
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/bin/tailscale" 0 0 0755
set_perm "$MODPATH/bin/tailscaled" 0 0 0755
set_perm "$MODPATH/common.sh" 0 0 0755
set_perm "$MODPATH/i18n.sh" 0 0 0755
set_perm "$MODPATH/watchdog.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/webui.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/binary-sha256" 0 0 0600

msg install.state_path
msg install.keep_official_off
msg install.reboot
msg install.install_webui
msg install.action_hint
msg install.update_hint
