#!/bin/bash
# dst_entrypoint.sh — 饥荒联机版游戏启动（容器 pid1）
# 职责：拉起 supervisord；把地面/洞穴两个 shard 的游戏日志实时转发到面板控制台（原样显示，不加前缀）；
#       面板控制台输入按前缀路由到对应 shard；面板停止（dst_shutdown 命令 / SIGINT/TERM）时
#       触发优雅关闭并输出过程日志（MLSG 统一日志系统：仅我们脚本日志走统一格式，控制台带色 + MLSG-LOG/startup.log 落盘）。

# ================================================
# 统一日志系统（与 dst_auto_mods.sh 同风格）
# ================================================
DST_LOG_DIR="${DST_LOG_DIR:-/home/container/MLSG-LOG}"
LOG_FILE="${DST_LOG_DIR}/startup.log"
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
print_info "[游戏启动] 饥荒联机版游戏启动（容器 pid1）"
print_info "[游戏启动] 日志文件: ${LOG_FILE}（控制台实时输出 + 落盘）"
print_line

supervisord -c /etc/supervisor/supervisord.conf &
SUPERVISORD_PID=$!
print_info "[游戏启动] supervisord 已启动 (pid=$SUPERVISORD_PID)"

# 游戏日志转发：tail -F 等待文件出现并实时输出到面板控制台，保持游戏原始格式（不加任何前缀）
tail -F "$MASTER_LOG" &
tail -F "$CAVES_LOG" &
print_info "[游戏启动] 游戏日志转发已启动: 地面/洞穴 → 面板控制台（原样显示）"

CMD_HINT="[游戏启动] 控制台指令：master:xxx → 地面服；caves:xxx → 洞穴服；不带前缀默认发送到地面服"

# 等待两 shard 真正就绪：master/caves 游戏日志出现 "Sim paused"
# （supervisord RUNNING 只代表进程已拉起，不代表游戏加载完成——真正启动到 Sim paused 才算就绪）
M_READY=0
C_READY=0
for i in $(seq 1 60); do
    [ "$M_READY" = "0" ] && { grep -q 'Sim paused' "$MASTER_LOG" 2>/dev/null && M_READY=1; }
    [ "$C_READY" = "0" ] && { grep -q 'Sim paused' "$CAVES_LOG" 2>/dev/null && C_READY=1; }
    if [ "$M_READY" = "1" ] && [ "$C_READY" = "1" ]; then
        print_line
        print_info "[游戏启动] 两 shard 已就绪（Sim paused）: 地面/洞穴"
        print_info "$CMD_HINT"
        print_line
        break
    fi
    if [ "$i" -eq 60 ]; then
        STATUS=$(supervisorctl -c /etc/supervisor/supervisord.conf -s http://127.0.0.1:9001 status 2>/dev/null | awk '{print $1"="$2}' | tr '\n' ' ')
        STATUS_DISPLAY=$(printf '%s' "$STATUS" | sed 's/master/地面/g; s/caves/洞穴/g')
        print_warn "[游戏启动] 60s 内未等到两 shard Sim paused，当前状态: ${STATUS_DISPLAY:-supervisorctl 无输出}"
    fi
    sleep 1
done

# 指令提示周期重复显示（游戏日志实时滚屏会刷掉一次性提示；仅控制台，不重复落盘）
(
    while true; do
        sleep 60
        echo -e "\e[36m=========================================================\e[0m"
        echo -e "\e[32m[INFO]\e[0m $CMD_HINT"
        echo -e "\e[36m=========================================================\e[0m"
    done
) &
HINT_LOOP_PID=$!

shutdown_started=0
on_shutdown() {
    if [ "$shutdown_started" = 1 ]; then
        print_info "[游戏启动] 重复停止请求，忽略"
        return
    fi
    shutdown_started=1
    kill "$HINT_LOOP_PID" 2>/dev/null
    print_info "[游戏启动] 收到停止命令/信号，并行触发两 shard 优雅关闭"
    pkill -TERM -f 'dst_graceful_shard.sh' 2>/dev/null   # 并行：两 wrapper 同时写 c_shutdown()，互不拖累
    kill -TERM "$SUPERVISORD_PID" 2>/dev/null           # supervisord 收尾停 program（wrapper 已防重入）
    wait "$SUPERVISORD_PID" 2>/dev/null
    print_info "[游戏启动] supervisord 已退出，容器关闭"
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
