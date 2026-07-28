#!/bin/bash

# 等待容器完全初始化
sleep 1

# 默认时区为 UTC
TZ=${TZ:-UTC}
export TZ

# 获取容器内网IP
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Steam Proton 环境变量配置
if [ -f "/usr/local/bin/proton" ]; then
    if [ ! -z ${SRCDS_APPID} ]; then
	    mkdir -p /home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container/.steam/steam"
        export STEAM_COMPAT_DATA_PATH="/home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"
        # 修复 protontricks pipx 路径问题
        export PATH=$PATH:/root/.local/bin
    else
        echo -e "----------------------------------------------------------------------------------"
        echo -e "[MLSG] 警告!!! Proton 需要 SRCDS_APPID 环境变量，否则无法正常运行，请补充该变量"
        echo -e "[MLSG] 服务端即将停止运行"
        echo -e "----------------------------------------------------------------------------------"
        exit 1
        fi
fi

# 切换至容器工作目录
cd /home/container || exit 1

## 自动更新开启时通过 SteamCMD 更新服务端（未设置或等于1视为开启）
if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then
    echo -e "[MLSG] 正在检查游戏服务端更新..."
    # 检测应用ID是否配置
    if [ ! -z ${SRCDS_APPID} ]; then
        # 未配置Steam账号时使用匿名账号
        if [ "${STEAM_USER}" == "" ]; then
            echo -e "[MLSG] 未设置Steam账号，将使用匿名账号登录"
            STEAM_USER=anonymous
            STEAM_PASS=""
            STEAM_AUTH=""
        fi
        # 执行SteamCMD更新
        ./steamcmd/steamcmd.sh +force_install_dir /home/container +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) +app_update 1007 +app_update ${SRCDS_APPID} $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) ${INSTALL_FLAGS} $( [[ "${VALIDATE}" == "1" ]] && printf %s 'validate' ) +quit
    else
        echo -e "[MLSG] 未配置应用ID，跳过更新检测"
    fi
else
    echo -e "[MLSG] 已关闭自动更新，跳过服务端更新检测"
fi

## PalDefender 日志归档逻辑
PD_LOG_DIR="/home/container/Palworld/Pal/Binaries/Win64/PalDefender/Logs"
PD_ARCHIVE_DIR="${PD_LOG_DIR}/History_Logs"

echo "[MLSG] 正在归档清理 PalDefender 历史日志..."
if [ -d "$PD_LOG_DIR" ]; then
    mkdir -p "$PD_ARCHIVE_DIR"
    find "$PD_LOG_DIR" -maxdepth 1 -name "*.log" -type f -exec mv {} "$PD_ARCHIVE_DIR/" \;
fi

(
    while true; do
        NEW_LOG=$(find "$PD_LOG_DIR" -maxdepth 1 -name "*.log" -type f 2>/dev/null | head -n 1)
        if [ -n "$NEW_LOG" ]; then
            echo "[MLSG] 检测到反作弊日志文件: $(basename "$NEW_LOG")，开始实时输出日志"
            tail -F "$NEW_LOG"
            break
        fi
        sleep 1
    done
) &

# 替换启动变量占位符
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')

# 启动服务
echo -e "[MLSG] 正在启动游戏服务端..."
echo -e "[MLSG] :/home/container$ ${MODIFIED_STARTUP}"
eval ${MODIFIED_STARTUP}