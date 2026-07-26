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
if [ -f "/usr/local/bin/proton" ]; then
    if [ ! -z ${SRCDS_APPID} ]; then
        mkdir -p /home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container/.steam/steam"
        export STEAM_COMPAT_DATA_PATH="/home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"
        export PATH=$PATH:/root/.local/bin:/home/container/.local/bin:/usr/sbin
    else
        echo -e "----------------------------------------------------------------------------------"
        echo -e "[MLSG] 警告!!! 使用Proton必须配置SRCDS_APPID环境变量，否则无法正常运行，请补充该参数"
        echo -e "[MLSG] 服务即将停止"
        echo -e "----------------------------------------------------------------------------------"
        exit 1
    fi
fi

# 切换至容器工作目录
cd /home/container || exit 1

## 如果AUTO_UPDATE为空或者等于1，则通过SteamCMD更新服务器文件
if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then
    echo -e "[MLSG] 正在检查游戏服务器更新..."
    if [ ! -z ${SRCDS_APPID} ]; then
        if [ "${STEAM_USER}" == "" ]; then
            echo -e "[MLSG] 未设置Steam账号，将使用匿名账号登录"
            STEAM_USER=anonymous
            STEAM_PASS=""
            STEAM_AUTH=""
        fi
        ./steamcmd/steamcmd.sh +force_install_dir /home/container +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) +app_update 1007 +app_update ${SRCDS_APPID} $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) ${INSTALL_FLAGS} $( [[ "${VALIDATE}" == "1" ]] && printf %s 'validate' ) +quit
    else
        echo -e "[MLSG] 未配置应用ID，跳过更新检测"
    fi
else
    echo -e "[MLSG] 已关闭自动更新，跳过服务器文件检查"
fi

# =========================================================
# [MLSG 自动化高级修复] 直接部署离线打包的 VC++ 运行库 DLL
# =========================================================
APP_ID="${SRCDS_APPID:-2394010}"
COMPAT_PFX="/home/container/.steam/steam/steamapps/compatdata/${APP_ID}/pfx"
VC_DONE_MARKER="/home/container/Pal/.vc_installed.done"

if [ ! -f "$VC_DONE_MARKER" ]; then
    echo "[MLSG] 未检测到 VC++ 运行库初始化标记，开始部署离线 DLL..."
    
    mkdir -p /home/container/Pal
    mkdir -p "$COMPAT_PFX/drive_c/windows/system32"
    mkdir -p "$COMPAT_PFX/drive_c/windows/syswow64"

    if [ -f "/tmp/WinFixDLLs.zip" ]; then
        # 创建临时解压目录
        mkdir -p /tmp/WinFixDLLs
        
        # 优先使用 unzip，如果没有则尝试 7zz 解压
        if command -v unzip &>/dev/null; then
            unzip -q /tmp/WinFixDLLs.zip -d /tmp/WinFixDLLs
        elif command -v 7zz &>/dev/null; then
            7zz x /tmp/WinFixDLLs.zip -o/tmp/WinFixDLLs &>/dev/null
        fi

        # 对应拷贝 system32 文件
        if [ -d "/tmp/WinFixDLLs/system32" ]; then
            cp -rf /tmp/WinFixDLLs/system32/* "$COMPAT_PFX/drive_c/windows/system32/"
            echo "[MLSG] system32 运行库注入成功！"
        fi
        
        # 对应拷贝 syswow64 文件
        if [ -d "/tmp/WinFixDLLs/syswow64" ]; then
            cp -rf /tmp/WinFixDLLs/syswow64/* "$COMPAT_PFX/drive_c/windows/syswow64/"
            echo "[MLSG] syswow64 运行库注入成功！"
        fi

        # 清理临时文件
        rm -rf /tmp/WinFixDLLs /tmp/WinFixDLLs.zip
        
        # 写入完成标记
        touch "$VC_DONE_MARKER"
        echo "[MLSG] 离线 VC++ 运行库 DLL 部署完成！标记已写入: $VC_DONE_MARKER"
    else
        echo "[MLSG] [警告] 未找到 /tmp/WinFixDLLs.zip，跳过离线运行库部署。"
    fi
else
    echo "[MLSG] VC++ 运行库已完成初始化，跳过。"
fi

# =========================================================
# [MLSG 附加环境配置] 修复卡死与日志转发/归档系统
# =========================================================

# 0. 归档并清理旧的游戏原生控制台日志
CONSOLE_LOG_DIR="/home/container/Pal/Saved/Logs"
CONSOLE_ARCHIVE_DIR="${CONSOLE_LOG_DIR}/History_Logs"
mkdir -p "${CONSOLE_LOG_DIR}" "${CONSOLE_ARCHIVE_DIR}"

if [ -f "${CONSOLE_LOG_DIR}/PalServer-Console.log" ]; then
    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    mv "${CONSOLE_LOG_DIR}/PalServer-Console.log" "${CONSOLE_ARCHIVE_DIR}/PalServer-Console_${TIMESTAMP}.log"
    echo "[MLSG] 已归档历史控制台日志: PalServer-Console_${TIMESTAMP}.log"
fi

# 1. 全局注入 Proton / Wine 运行环境变量
export PROTON_NO_FSYNC=1
export PROTON_NO_ESYNC=1
export WINEFSYNC=0 
export WINEESYNC=0
export WINEDLLOVERRIDES="winmm=n,b;d3d9=n,b;dwmapi=n,b;xalia.exe=d;xalia64.exe=d;xalia=d;concrt140=n,b;msvcp140=n,b;msvcp140_1=n,b;msvcp140_2=n,b;msvcp140_atomic_wait=n,b;msvcp140_codecvt_ids=n,b;ucrtbase=n,b;vccorlib140=n,b;vcomp140=n,b;vcruntime140=n,b;vcruntime140_1=n,b"

# 自动清理遗留的损坏临时存档！防止死锁
echo "[MLSG] 正在扫描并清理遗留的 .new_tmp 临时文件..."
if [ -d "/home/container/Pal/Saved/SaveGames" ]; then
    find /home/container/Pal/Saved/SaveGames -type f -name "*.new_tmp" -exec rm -f {} \;
    echo "[MLSG] 临时文件清理完毕，确保存档环境干净。"
fi

# 2. PalDefender 日志归档与后台动态捕捉
PD_LOG_DIR="/home/container/Pal/Binaries/Win64/PalDefender/Logs"
PD_ARCHIVE_DIR="${PD_LOG_DIR}/History_Logs"

echo "[MLSG] 正在清理并归档 PalDefender 历史日志..."
if [ -d "$PD_LOG_DIR" ]; then
    mkdir -p "$PD_ARCHIVE_DIR"
    find "$PD_LOG_DIR" -maxdepth 1 -name "*.log" -type f -exec mv {} "$PD_ARCHIVE_DIR/" \;
fi

(
    while true; do
        NEW_LOG=$(find "$PD_LOG_DIR" -maxdepth 1 -name "*.log" -type f 2>/dev/null | head -n 1)
        if [ -n "$NEW_LOG" ]; then
            echo "[MLSG] 检测到反作弊日志: $(basename "$NEW_LOG")，开启转发"
            tail -F "$NEW_LOG"
            break
        fi
        sleep 1
    done
) &
# =========================================================

# 替换启动参数变量
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')

# 启动游戏服务器（同时输出到控制台并实时写入 PalServer-Console.log）
echo -e "[MLSG] 正在启动服务器..."
echo -e ":/home/container$ ${MODIFIED_STARTUP}"
eval ${MODIFIED_STARTUP} 2>&1 | tee "${CONSOLE_LOG_DIR}/PalServer-Console.log"