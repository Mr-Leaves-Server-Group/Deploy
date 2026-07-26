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
# [MLSG 自动化高级修复] 在线下载并部署 WinFixDLLs 修复包
# =========================================================
APP_ID="${SRCDS_APPID:-2394010}"
COMPAT_PFX="/home/container/.steam/steam/steamapps/compatdata/${APP_ID}/pfx"
VC_DONE_MARKER="/home/container/Pal/.vc_installed.done"
WIN_FIX_ZIP="/home/container/Pal/WinFixDLLs.zip"
WIN_FIX_URL="https://raw.githubusercontent.com/Mr-Leaves-Server-Group/Deploy/main/03-Palworld/WinFixDLLs.zip"

if [ ! -f "$VC_DONE_MARKER" ]; then
    echo "[MLSG] 未检测到初始化标记，开始下载 WinFixDLLs 修复包..."
    
    mkdir -p /home/container/Pal
    
    # 如果压缩包不存在则通过 curl 下载到 Pal 文件夹
    if [ ! -f "${WIN_FIX_ZIP}" ]; then
        curl -sSL -o "${WIN_FIX_ZIP}" "${WIN_FIX_URL}"
    fi

    if [ -f "${WIN_FIX_ZIP}" ]; then
        echo "[MLSG] 下载完成，正在解压并部署依赖文件..."
        mkdir -p /tmp/WinFixDLLs
        
        # 优先使用 unzip，如果没有则尝试 7zz 解压
        if command -v unzip &>/dev/null; then
            unzip -q "${WIN_FIX_ZIP}" -d /tmp/WinFixDLLs
        elif command -v 7zz &>/dev/null; then
            7zz x "${WIN_FIX_ZIP}" -o/tmp/WinFixDLLs &>/dev/null
        fi

        # 1. 部署 system32 运行库
        if [ -d "/tmp/WinFixDLLs/system32" ]; then
            mkdir -p "$COMPAT_PFX/drive_c/windows/system32"
            cp -rf /tmp/WinFixDLLs/system32/* "$COMPAT_PFX/drive_c/windows/system32/"
            echo "[MLSG] system32 运行库注入成功！"
        fi
        
        # 2. 部署 syswow64 运行库
        if [ -d "/tmp/WinFixDLLs/syswow64" ]; then
            mkdir -p "$COMPAT_PFX/drive_c/windows/syswow64"
            cp -rf /tmp/WinFixDLLs/syswow64/* "$COMPAT_PFX/drive_c/windows/syswow64/"
            echo "[MLSG] syswow64 运行库注入成功！"
        fi

        # 3. 部署 Binaries/Win64 文件夹中的 DLL
        TARGET_WIN64="/home/container/Pal/Binaries/Win64"
        mkdir -p "${TARGET_WIN64}"
        if [ -d "/tmp/WinFixDLLs/Win64" ]; then
            cp -rf /tmp/WinFixDLLs/Win64/* "${TARGET_WIN64}/"
            echo "[MLSG] Binaries/Win64 依赖项注入成功！"
        elif [ -d "/tmp/WinFixDLLs/Binaries/Win64" ]; then
            cp -rf /tmp/WinFixDLLs/Binaries/Win64/* "${TARGET_WIN64}/"
            echo "[MLSG] Binaries/Win64 依赖项注入成功！"
        fi

        # 清理临时解压目录与下载的 zip 包
        rm -rf /tmp/WinFixDLLs "${WIN_FIX_ZIP}"
        
        # 写入完成标记
        touch "$VC_DONE_MARKER"
        echo "[MLSG] 离线 WinFixDLLs 部署完成！标记已写入: $VC_DONE_MARKER"
    else
        echo "[MLSG] [错误] WinFixDLLs.zip 下载失败，请检查网络或直链地址。"
    fi
else
    echo "[MLSG] WinFixDLLs 运行库已完成初始化，跳过。"
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