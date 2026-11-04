#!/bin/bash
# dst_entrypoint.sh — 容器 pid1
# 职责：拉起 supervisord；把两个 shard 的日志文件实时转发到面板控制台（带 shard 前缀）；
#       面板控制台输入按前缀路由到对应 shard；面板停止（dst_shutdown 命令 / SIGINT/TERM）时
#       触发优雅关闭并输出过程日志（MLSG 统一日志系统：控制台带色 + MLSG-LOG/dst_entrypoint.log 落盘）。

# ================================================
# 统一日志系统（与 dst_auto_mods.sh 同风格）
# ================================================
DST_LOG_DIR="${DST_LOG_DIR:-/home/container/MLSG-LOG}"
LOG_FILE="${DST_LOG_DIR}/dst_entrypoint.log"
mkdir -p "${DST_LOG_DIR}"
touch "${LOG_FILE}"

log_filter() { sed 's/\x1b\[[0-9;]*[mGKF]//g' >> "${LOG_FILE}"; }
print_line()  { local MSG="\e[36m=========================================================\e[0m"; echo -e "${MSG}"; echo -e "${MSG}" | log_filter; }
print_info()  { local MSG="\e[32m[INFO]\e[0m $1"; echo -e "${MSG}"; echo -e "${MSG}" | log_filter; }
print_warn()  { local MSG="\e[33m[WARN]\e[0m $1"; echo -e "${MSG}"; echo -e "${MSG}" | log_filter; }
print_error() { local MSG="\e[31m[ERROR]\e[0m $1"; echo -e "${MSG}"; echo -e "${MSG}" | log_filter; }

MASTER_LOG="${MASTER_LOG:-/home/container/DoNotStarveTogether/config/server/Master/server_log.txt}"
CAVES_LOG="${CAVES_LOG:-/home/container/DoNotStarveTogether/config/server/Caves/server_log.txt}"

print_line
print_info "[entrypoint] dst_entrypoint.sh 启动（容器 pid1）"
print_info "[entrypoint] 日志文件: ${LOG_FILE}（控制台实时输出 + 落盘）"
print_line

supervisord -c /etc/supervisor/supervisord.conf &
SUPERVISORD_PID=$!
print_info "[entrypoint] supervisord started (pid=$SUPERVISORD_PID)"

# 日志转发：tail -F 等待文件出现并实时输出；sed -u 关缓冲、加 shard 前缀，控制台可区分
tail -F "$MASTER_LOG" | sed -u 's/^/[master] /' &
tail -F "$CAVES_LOG" | sed -u 's/^/[caves]  /' &
print_info "[entrypoint] 日志转发已启动: [master]/[caves] → 面板控制台"

shutdown_started=0
on_shutdown() {
    if [ "$shutdown_started" = 1 ]; then
        print_info "[entrypoint] 重复停止请求，忽略"
        return
    fi
    shutdown_started=1
    print_info "[entrypoint] 收到停止命令/信号，并行触发两 shard 优雅关闭"
    pkill -TERM -f 'dst_graceful_shard.sh' 2>/dev/null   # 并行：两 wrapper 同时写 c_shutdown()，互不拖累
    kill -TERM "$SUPERVISORD_PID" 2>/dev/null           # supervisord 收尾停 program（wrapper 已防重入）
    wait "$SUPERVISORD_PID" 2>/dev/null
    print_info "[entrypoint] supervisord 已退出，容器关闭"
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
