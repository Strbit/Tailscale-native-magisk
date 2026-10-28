#!/system/bin/sh
#
# Native Tailscale TUN - 守护进程看护器。
#
# 由 service.sh 在开机时以 init 子进程身份启动，因此处于 system cgroup，
# 不会被「划掉 KernelSU / Magisk 管理器」这类应用级清理波及。
#
# 作用：定期检查 tailscaled 是否存活。若被外部杀掉（例如管理器应用退出时
# 连带清理），由本看护器重新拉起；重新拉起的进程会继承本进程的 system
# cgroup 归属，从而获得和开机启动相同的免疫效果。
#
# 用户主动「停止」时 webui.sh 会写 daemon-stopped 标记，看护器据此跳过重启，
# 不会和用户操作打架。

MODDIR="${0%/*}"
. "$MODDIR/common.sh"
. "$MODDIR/i18n.sh"

echo "$$" > "$WATCHDOG_PIDFILE"

# 每 15 秒巡检一次；间隔足够长，不会造成明显唤醒开销。
INTERVAL=15

while :; do
    sleep "$INTERVAL"

    # 用户主动停止：尊重意图，不做重启。
    if [ -f "$DAEMON_STOPPED_MARKER" ]; then
        continue
    fi

    # 守护进程安好，无需处理。
    if pid_is_ours; then
        continue
    fi

    # 有别的 tailscaled 在跑（非本模块管理），不抢夺。
    if pidof tailscaled >/dev/null 2>&1; then
        continue
    fi

    echo "$(date): $(msg watchdog.restarting)" >> "$LOGFILE"
    start_daemon >/dev/null 2>&1 || true
done
