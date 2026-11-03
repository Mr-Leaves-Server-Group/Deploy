#!/bin/bash
# dst_graceful_shard.sh <master|caves>
# 作用：supervisord 直接以本脚本为 program 主进程（不再经 /bin/sh -c 外壳）。
#       收到 SIGTERM 时把 c_shutdown() 写入游戏控制台 fifo，等待游戏保存后退出；
#       信号只到达本脚本，游戏进程收不到信号，可完整执行保存。
#       参数 SERVER_PORT/MAX_PLAYERS 由容器环境注入（egg），本脚本读取并组参。
SHARD="${1:-master}"
SAVE_TIMEOUT="${SAVE_TIMEOUT:-60}"   # 保存兜底秒数（实测 c_shutdown 到退出仅 3-4s）
GAME_BIN="${GAME_BIN:-./dontstarve_dedicated_server_nullrenderer_x64}"
SERVER_PORT="${SERVER_PORT:-10999}"
MAX_PLAYERS="${MAX_PLAYERS:-16}"

case "$SHARD" in
    caves)  GAME_PORT=11000; GAME_SHARD=Caves ;;
    master) GAME_PORT="$SERVER_PORT"; GAME_SHARD=Master ;;
    *)      echo "unknown shard: $SHARD" >&2; exit 1 ;;
esac

FIFO="/tmp/dst_${SHARD}.fifo"
rm -f "$FIFO"
mkfifo "$FIFO"
exec 9<>"$FIFO"          # 读写端常开：游戏 open 读端不阻塞，写 fd 9 即投递到游戏控制台

"$GAME_BIN" -bind_ip 0.0.0.0 -port "$GAME_PORT" -persistent_storage_root /home/container/DoNotStarveTogether -conf_dir config -cluster server -players "$MAX_PLAYERS" -shard "$GAME_SHARD" <"$FIFO" &
GAME_PID=$!

shutdown_started=0
on_shutdown() {
    [ "$shutdown_started" = 1 ] && return
    shutdown_started=1
    printf 'c_shutdown()\n' >&9
}
trap on_shutdown TERM INT

waited=0
while kill -0 "$GAME_PID" 2>/dev/null; do
    if [ "$shutdown_started" = 1 ]; then
        # 保存阶段：轮询等待 + 超时兜底（shell 里无法给 wait 加超时，只能探测）
        waited=$((waited + 1))
        if [ "$waited" -ge "$SAVE_TIMEOUT" ]; then
            kill -9 "$GAME_PID" 2>/dev/null
            break
        fi
        sleep 1
    else
        # 正常运行：wait 事件驱动，游戏退出/崩溃立即感知（trap 会打断 wait，循环重新判断）
        wait "$GAME_PID" 2>/dev/null
    fi
done
wait "$GAME_PID" 2>/dev/null
exit 0
