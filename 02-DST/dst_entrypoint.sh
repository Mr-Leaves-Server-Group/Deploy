#!/bin/bash
# dst_entrypoint.sh — 容器 pid1
# 职责：拉起 supervisord；把两个 shard 的日志文件实时转发到面板控制台（带 shard 前缀）；
#       面板控制台输入按前缀路由到对应 shard；面板停止（SIGINT/TERM）时触发优雅关闭并输出过程日志。
MASTER_LOG="${MASTER_LOG:-/home/container/DoNotStarveTogether/config/server/Master/server_log.txt}"
CAVES_LOG="${CAVES_LOG:-/home/container/DoNotStarveTogether/config/server/Caves/server_log.txt}"

supervisord -c /etc/supervisor/supervisord.conf &
SUPERVISORD_PID=$!
echo "[entrypoint] supervisord started (pid=$SUPERVISORD_PID)"

# 日志转发：tail -F 等待文件出现并实时输出；sed -u 关缓冲、加 shard 前缀，控制台可区分
tail -F "$MASTER_LOG" | sed -u 's/^/[master] /' &
tail -F "$CAVES_LOG" | sed -u 's/^/[caves]  /' &

shutdown_started=0
on_shutdown() {
    [ "$shutdown_started" = 1 ] && return
    shutdown_started=1
    echo "[entrypoint] 收到停止信号，并行触发两 shard 优雅关闭"
    pkill -TERM -f 'dst_graceful_shard.sh' 2>/dev/null   # 并行：两 wrapper 同时写 c_shutdown()，互不拖累
    kill -TERM "$SUPERVISORD_PID" 2>/dev/null           # supervisord 收尾停 program（wrapper 已防重入）
    wait "$SUPERVISORD_PID" 2>/dev/null
    echo "[entrypoint] supervisord 已退出，容器关闭"
    exit 0
}
trap on_shutdown INT TERM

while IFS= read -r line || sleep 1; do
    case "$line" in
        dst_shutdown)
            on_shutdown ;;   # 面板停止命令（egg stop 字段）→ 触发优雅关闭，绕开容器 SIGINT 失效问题
        master:c_*)
            printf '%s\n' "${line#master:}" > /tmp/dst_master.fifo 2>/dev/null ;;
        caves:c_*)
            printf '%s\n' "${line#caves:}" > /tmp/dst_caves.fifo 2>/dev/null ;;
        c_*)
            printf '%s\n' "$line" > /tmp/dst_master.fifo 2>/dev/null ;;
    esac
done
