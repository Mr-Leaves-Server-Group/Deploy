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
    # 判断是否设置应用ID
    if [ ! -z ${SRCDS_APPID} ]; then
        # 缺失账号信息时填充默认值
        if [ "${STEAM_USER}" == "" ]; then
            echo -e "[MLSG] 未设置Steam账号，将使用匿名账号登录"
            STEAM_USER=anonymous
            STEAM_PASS=""
            STEAM_AUTH=""
        fi
        # 执行SteamCMD更新命令
        ./steamcmd/steamcmd.sh +force_install_dir /home/container +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) +app_update 1007 +app_update ${SRCDS_APPID} $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) ${INSTALL_FLAGS} $( [[ "${VALIDATE}" == "1" ]] && printf %s 'validate' ) +quit
    else
        echo -e "[MLSG] 未配置应用ID，跳过更新检测"
    fi
else
    echo -e "[MLSG] 已关闭自动更新，跳过服务器文件检查"
fi

# =========================================================
# [MLSG 自动修复] 自动通过 Protontricks/Winetricks/模板复制 初始化 VC++ 2022 运行库
# =========================================================
APP_ID="${SRCDS_APPID:-2394010}"
COMPAT_PFX="/home/container/.steam/steam/steamapps/compatdata/${APP_ID}/pfx"
TARGET_SYS32="${COMPAT_PFX}/drive_c/windows/system32"
TEMPLATE_SYS32="/usr/local/bin/files/share/default_pfx/drive_c/windows/system32"
VCRUN_DONE_MARKER="/home/container/.vcrun2022_installed.done"

# 1. 动态搜寻并补全 PATH 中的 wineserver 目录路径，防止 winetricks 提示 warning: wineserver not found!
WINESERVER_BIN=$(find /opt /usr /home -name "wineserver" 2>/dev/null | head -n 1)
if [ -n "$WINESERVER_BIN" ]; then
    export PATH="$(dirname "$WINESERVER_BIN"):$PATH"
fi

# 2. 检查并补充 VC 运行库 DLL
if [ ! -f "$VCRUN_DONE_MARKER" ] || [ ! -f "${TARGET_SYS32}/vcruntime140.dll" ]; then
    echo "[MLSG] 未检测到完整的 VC++ 2022 运行库，开始执行 Proton 运行库修复..."
    
    # 确保 Proton 的 system32 目标目录存在
    mkdir -p "${TARGET_SYS32}"

    # 尝试 1: Protontricks 尝试
    if command -v protontricks &>/dev/null; then
        echo "[MLSG] 正在尝试通过 Protontricks 静默安装 vcrun2022..."
        protontricks --unattended "$APP_ID" vcrun2022
    fi

    # 尝试 2: Winetricks 尝试
    if [ ! -f "${TARGET_SYS32}/vcruntime140.dll" ] && command -v winetricks &>/dev/null; then
        echo "[MLSG] 正在尝试通过 Winetricks 回退方案安装 vcrun2022..."
        WINEPREFIX="$COMPAT_PFX" winetricks -q vcrun2022
    fi

    # 尝试 3: 强制直接从镜像模板/系统基础路径复制 DLL 兜底（保证 100% 成功）
    if [ ! -f "${TARGET_SYS32}/vcruntime140.dll" ]; then
        echo "[MLSG] protontricks/winetricks 执行未生成 DLL，启动模板文件直接复制兜底方案..."
        if [ -d "$TEMPLATE_SYS32" ]; then
            cp -f "$TEMPLATE_SYS32"/vcruntime140*.dll "$TARGET_SYS32/" 2>/dev/null
            cp -f "$TEMPLATE_SYS32"/msvcp140*.dll "$TARGET_SYS32/" 2>/dev/null
            cp -f "$TEMPLATE_SYS32"/vcomp140*.dll "$TARGET_SYS32/" 2>/dev/null
            cp -f "$TEMPLATE_SYS32"/concrt140*.dll "$TARGET_SYS32/" 2>/dev/null
            cp -f "$TEMPLATE_SYS32"/ucrtbase.dll "$TARGET_SYS32/" 2>/dev/null
        fi
    fi

    # 校验最终修复状态
    if [ -f "${TARGET_SYS32}/vcruntime140.dll" ]; then
        touch "$VCRUN_DONE_MARKER"
        echo "[MLSG] VC++ 2022 运行库 / DLL 修复成功！标记文件已生成: $VCRUN_DONE_MARKER"
    else
        echo "[MLSG] [警告] 运行库修复未能补齐 vcruntime140.dll，请检查 Docker 镜像模板文件！"
    fi
else
    echo "[MLSG] 检测到 VC++ 2022 运行库已完成初始化，跳过修复程序。"
fi

# 3. 自动修正 Saved 存档与备份目录权限，防止 save 时触发 Failed copy from backup 报错
if [ -d "/home/container/Pal/Saved" ]; then
    echo "[MLSG] 正在修正 Pal/Saved 目录权限以确保存档备份正常执行..."
    chmod -R 777 /home/container/Pal/Saved
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

# 1. 全局注入 Proton / Wine 运行环境变量，修复卡死/save覆盖问题
export PROTON_NO_FSYNC=1
export PROTON_NO_ESYNC=1
export WINEFSYNC=0 
export WINEESYNC=0
export WINEDLLOVERRIDES="winmm=n,b,d3d9=n,b,dwmapi=n,b,xalia.exe=d,xalia64.exe=d,xalia=d,concrt140=n,b,msvcp140=n,b,msvcp140_1=n,b,msvcp140_2=n,b,msvcp140_atomic_wait=n,b,msvcp140_codecvt_ids=n,b,ucrtbase=n,b,vccorlib140=n,b,vcomp140=n,b,vcruntime140=n,b,vcruntime140_1=n,b"

# [新增] 自动清理遗留的损坏临时存档！防止死锁
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