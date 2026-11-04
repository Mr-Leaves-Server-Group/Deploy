#!/bin/bash
# dst_graceful_shard.sh <master|caves>
# 作用：supervisord 直接以本脚本为 program 主进程（不再经 /bin/sh -c 外壳）。
#       收到 SIGTERM 时把 c_shutdown() 写入游戏控制台 fifo，等待游戏保存后退出；
#       信号只到达本脚本，游戏进程收不到信号，可完整执行保存。
#       参数 SERVER_PORT/MAX_PLAYERS 由容器环境注入（egg），本脚本读取并组参。
#       日志：MLSG 统一日志系统（控制台带色 + MLSG-LOG/dst_graceful.log 无色落盘）。

# ================================================
# 统一日志系统（与 dst_auto_mods.sh 同风格）
# ================================================
DST_LOG_DIR="${DST_LOG_DIR:-/home/container/MLSG-LOG}"
LOG_FILE="${DST_LOG_DIR}/dst_graceful.log"
mkdir -p "${DST_LOG_DIR}"
touch "${LOG_FILE}"

log_filter() { sed 's/\x1b\[[0-9;]*[mGKF]//g' >> "${LOG_FILE}"; }
print_line()  { local MSG="\e[36m=========================================================\e[0m"; echo -e "${MSG}"; echo -e "${MSG}" | log_filter; }
print_info()  { local MSG="\e[32m[INFO]\e[0m $1"; echo -e "${MSG}"; echo -e "${MSG}" | log_filter; }
print_warn()  { local MSG="\e[33m[WARN]\e[0m $1"; echo -e "${MSG}"; echo -e "${MSG}" | log_filter; }
print_error() { local MSG="\e[31m[ERROR]\e[0m $1"; echo -e "${MSG}"; echo -e "${MSG}" | log_filter; }

SHARD="${1:-master}"
SAVE_TIMEOUT="${SAVE_TIMEOUT:-60}"   # 保存兜底秒数（实测 c_shutdown 到退出仅 3-4s）
GAME_BIN="${GAME_BIN:-./dontstarve_dedicated_server_nullrenderer_x64}"
SERVER_PORT="${SERVER_PORT:-10999}"
MAX_PLAYERS="${MAX_PLAYERS:-16}"

case "$SHARD" in
    caves)  GAME_PORT=11000; GAME_SHARD=Caves ;;
    master) GAME_PORT="$SERVER_PORT"; GAME_SHARD=Master ;;
    *)      print_error "[$SHARD] unknown shard: $SHARD"; exit 1 ;;
esac

print_line
print_info "[$SHARD] dst_graceful_shard.sh 启动（bin=$GAME_BIN port=$GAME_PORT shard=$GAME_SHARD）"
print_info "[$SHARD] 日志文件: ${LOG_FILE}（保存兜底 ${SAVE_TIMEOUT}s）"
print_line

FIFO="/tmp/dst_${SHARD}.fifo"
rm -f "$FIFO"
mkfifo "$FIFO"
exec 9<>"$FIFO"          # 读写端常开：游戏 open 读端不阻塞，写 fd 9 即投递到游戏控制台

"$GAME_BIN" -bind_ip 0.0.0.0 -port "$GAME_PORT" -persistent_storage_root /home/container/DoNotStarveTogether -conf_dir config -cluster server -players "$MAX_PLAYERS" -shard "$GAME_SHARD" <"$FIFO" &
GAME_PID=$!
print_info "[$SHARD] 游戏进程已启动（pid=$GAME_PID），等待信号..."

shutdown_started=0
on_shutdown() {
    if [ "$shutdown_started" = 1 ]; then
        print_info "[$SHARD] 重复停止信号，忽略（c_shutdown() 已投递）"
        return
    fi
    shutdown_started=1
    print_info "[$SHARD] 收到停止信号（TERM/INT），投递 c_shutdown() 到游戏控制台"
    printf 'c_shutdown()\n' >&9
}
trap on_shutdown TERM INT

waited=0
while kill -0 "$GAME_PID" 2>/dev/null; do
    if [ "$shutdown_started" = 1 ]; then
        # 保存阶段：轮询等待 + 超时兜底（shell 里无法给 wait 加超时，只能探测）
        waited=$((waited + 1))
        if [ "$waited" -ge "$SAVE_TIMEOUT" ]; then
            print_error "[$SHARD] 等待游戏保存超过 ${SAVE_TIMEOUT}s，强制结束（存档可能不完整）"
            kill -9 "$GAME_PID" 2>/dev/null
            break
        fi
        if [ $((waited % 10)) -eq 0 ]; then
            print_warn "[$SHARD] 仍在等待游戏保存（已 ${waited}s / 上限 ${SAVE_TIMEOUT}s）"
        fi
        sleep 1
    else
        # 正常运行：wait 事件驱动，游戏退出/崩溃立即感知（trap 会打断 wait，循环重新判断）
        wait "$GAME_PID" 2>/dev/null
    fi
done
wait "$GAME_PID" 2>/dev/null
print_info "[$SHARD] 游戏进程已退出，wrapper 结束"
exit 0
