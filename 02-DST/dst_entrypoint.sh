#!/bin/bash
# dst_entrypoint.sh — 容器 pid1
# 职责：拉起 supervisord；面板控制台输入按前缀路由到对应 shard；
#       面板 ^C(SIGINT) 时给 supervisord 发 SIGTERM，触发优雅关闭（wrapper 写 c_shutdown()）。
supervisord -c /etc/supervisor/supervisord.conf &
SUPERVISORD_PID=$!

shutdown_started=0
on_shutdown() {
    [ "$shutdown_started" = 1 ] && return
    shutdown_started=1
    kill -TERM "$SUPERVISORD_PID" 2>/dev/null   # supervisord 收 TERM → 优雅关 program → wrapper 写 c_shutdown()
    wait "$SUPERVISORD_PID" 2>/dev/null
    exit 0
}
trap on_shutdown INT TERM

while IFS= read -r line; do
    case "$line" in
        master:c_*)
            printf '%s\n' "${line#master:}" > /tmp/dst_master.fifo 2>/dev/null ;;
        caves:c_*)
            printf '%s\n' "${line#caves:}" > /tmp/dst_caves.fifo 2>/dev/null ;;
        c_*)
            printf '%s\n' "$line" > /tmp/dst_master.fifo 2>/dev/null ;;
    esac
done
