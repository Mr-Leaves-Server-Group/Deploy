#!/bin/bash

# 等待容器完成初始化
sleep 1

# 默认时区环境变量为 UTC
TZ=${TZ:-UTC}
export TZ

# 设置保存容器内部Docker IP的环境变量
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Steam Proton运行环境配置
# 兼容新路径 /opt/proton/proton 以及旧软链接 /usr/local/bin/proton
if [ -f "/usr/local/bin/proton" ]; then
    if [ ! -z ${SRCDS_APPID} ]; then
        mkdir -p /home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container/.steam/steam"
        export STEAM_COMPAT_DATA_PATH="/home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"
        # 修复protontricks使用pipx时路径问题
        export PATH=$PATH:/root/.local/bin
    else
        echo -e "----------------------------------------------------------------------------------"
        echo -e "警告!!! 使用Proton必须配置SRCDS_APPID环境变量，否则无法正常运行，请补充该参数"
        echo -e "服务即将停止"
        echo -e "----------------------------------------------------------------------------------"
        exit 1
    fi
fi

# 切换至容器工作目录
cd /home/container || exit 1

## 如果AUTO_UPDATE为空或者等于1，则通过SteamCMD更新服务器文件
if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then
    echo -e "正在检查游戏服务器更新..."
    # 判断是否设置应用ID
    if [ ! -z ${SRCDS_APPID} ]; then
        # 缺失账号信息时填充默认值
        if [ "${STEAM_USER}" == "" ]; then
            echo -e "未设置Steam账号，将使用匿名账号登录"
            STEAM_USER=anonymous
            STEAM_PASS=""
            STEAM_AUTH=""
        fi
        # 执行SteamCMD更新命令
        ./steamcmd/steamcmd.sh +force_install_dir /home/container +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) +app_update 1007 +app_update ${SRCDS_APPID} $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) ${INSTALL_FLAGS} $( [[ "${VALIDATE}" == "1" ]] && printf %s 'validate' ) +quit
    else
        echo -e "未配置应用ID，跳过更新检测"
    fi
else
    echo -e "已关闭自动更新，跳过服务器文件检查"
fi

# =========================================================
# [MLSG 附加环境配置] 修复卡死与日志转发系统
# =========================================================

# 1. 全局注入 Proton 修复参数（面板启动命令里就不需要写 env 了）
export PROTON_NO_FSYNC=1
export PROTON_NO_ESYNC=1
export WINEDLLOVERRIDES="xalia.exe=d,xalia64.exe=d,xalia=d"

# 2. Palworld 原生日志准备与后台转发
PAL_LOG_DIR="/home/container/Pal/Saved/Logs"
mkdir -p "$PAL_LOG_DIR"
touch "$PAL_LOG_DIR/Pal.log"
tail -F "$PAL_LOG_DIR/Pal.log" &

# 3. PalDefender 日志归档与后台动态捕捉
PD_LOG_DIR="/home/container/Pal/Binaries/Win64/PalDefender/Logs"
PD_ARCHIVE_DIR="${PD_LOG_DIR}/History_Logs"

echo "[MLSG-INIT] 正在清理并归档历史日志..."
if [ -d "$PD_LOG_DIR" ]; then
    mkdir -p "$PD_ARCHIVE_DIR"
    # 将旧的 .log 文件移动到归档目录
    find "$PD_LOG_DIR" -maxdepth 1 -name "*.log" -type f -exec mv {} "$PD_ARCHIVE_DIR/" \;
fi

# 挂起一个后台进程，蹲守新生成的 PalDefender 日志
(
    while true; do
        NEW_LOG=$(find "$PD_LOG_DIR" -maxdepth 1 -name "*.log" -type f 2>/dev/null | head -n 1)
        if [ -n "$NEW_LOG" ]; then
            echo "[MLSG-INIT] 检测到反作弊日志: $(basename "$NEW_LOG")，开启转发"
            tail -F "$NEW_LOG"
            break
        fi
        sleep 1
    done
) &
# =========================================================

# 替换启动参数变量
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')

# 启动游戏服务器
echo -e "正在启动服务器..."
echo -e ":/home/container$ ${MODIFIED_STARTUP}"
eval ${MODIFIED_STARTUP}