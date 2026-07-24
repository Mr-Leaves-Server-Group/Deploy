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
if [ -f "/opt/proton/proton" ] || [ -f "/usr/local/bin/proton" ]; then
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

# ====================== 新增幻兽帕鲁配置自动写入模块 开始 ======================
# 配置文件路径（Windows服务端标准路径）
SETTINGS_FILE="/home/container/Pal/Saved/Config/WindowsServer/PalWorldSettings.ini"

# 简易日志输出函数
log() {
    echo -e "[配置模块] $*"
}

## 将字符串 "true"/"false" 转换为UE配置文件所需的 "True"/"False" 格式
to_bool() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        true|1|yes) echo "True" ;;
        *) echo "False" ;;
    esac
}

## -----------------------------------------------------------------------------
## 读取环境变量并写入 PalWorldSettings.ini
## 幻兽帕鲁从该配置文件读取身份、网络相关参数，而非启动命令参数
## 使用sed修改OptionSettings元组内指定配置项
## 注意：幻兽帕鲁1.0版本共有119项配置，这里仅处理常用核心配置
## 倍率类（经验、捕获倍率等）如需精细调整可直接编辑ini文件
## -----------------------------------------------------------------------------
update_settings() {
    [ -f "${SETTINGS_FILE}" ] || {
        log "警告：未找到PalWorldSettings.ini，跳过配置注入"
        return 0
    }

    log "开始从环境变量加载并写入服务器配置"

    ## 关闭命令错误退出：在FUSE/网络文件系统下sed -i可能出现误报错
    ## 宁可跳过单条配置修改，也不要直接终止整个容器
    set +e

    ## 工具函数：修改配置项 FieldName="value" 或 FieldName=value
    set_field() {
        local field="$1" value="$2" quote="${3:-true}"
        if [ "${quote}" = "true" ]; then
            sed -i "s/${field}=\"[^\"]*\"/${field}=\"${value}\"/" "${SETTINGS_FILE}"
        else
            sed -i "s/${field}=[0-9]*/${field}=${value}/" "${SETTINGS_FILE}"
        fi
    }

    ## 工具函数：修改布尔类型配置（True/False）
    set_bool() {
        local field="$1" value="$2"
        sed -i "s/${field}=\(True\|False\)/${field}=${value}/" "${SETTINGS_FILE}"
    }

    ## 工具函数：修改元组配置，例如 CrossplayPlatforms=(Steam,Xbox,PS5,Mac)
    set_tuple() {
        local field="$1" value="$2"
        sed -i "s/${field}=([^)]*)/${field}=(${value})/" "${SETTINGS_FILE}"
    }

    ## 服务器基础标识
    [ -n "${SERVER_NAME:-}" ] && set_field ServerName "${SERVER_NAME}"
    [ -n "${SERVER_DESCRIPTION:-}" ] && set_field ServerDescription "${SERVER_DESCRIPTION}"
    [ -n "${ADMIN_PASSWORD:-}" ] && set_field AdminPassword "${ADMIN_PASSWORD}"
    [ -n "${SERVER_PASSWORD:-}" ] && set_field ServerPassword "${SERVER_PASSWORD}"
    [ -n "${MAX_PLAYERS:-}" ] && set_field ServerPlayerMaxNum "${MAX_PLAYERS}" false

    ## 网络设置（1.0版本RCON与REST API同样在ini内配置）
    [ -n "${RCON_ENABLED:-}" ] && set_bool RCONEnabled "$(to_bool "${RCON_ENABLED}")"
    [ -n "${RCON_PORT:-}" ] && set_field RCONPort "${RCON_PORT}" false
    [ -n "${REST_API_ENABLED:-}" ] && set_bool RESTAPIEnabled "$(to_bool "${REST_API_ENABLED}")"
    [ -n "${REST_API_PORT:-}" ] && set_field RESTAPIPort "${REST_API_PORT}" false

    ## 公网IP/端口（用于NAT/多网卡环境，仅对外广播，不会变更监听端口）
    [ -n "${PUBLIC_IP:-}" ] && set_field PublicIP "${PUBLIC_IP}"
    [ -n "${PUBLIC_PORT:-}" ] && set_field PublicPort "${PUBLIC_PORT}" false

    ## 跨平台联机（1.0版本通过PalWorldSettings.ini中的CrossplayPlatforms元组控制）
    [ -n "${CROSSPLAY_PLATFORMS:-}" ] && set_tuple CrossplayPlatforms "${CROSSPLAY_PLATFORMS}"

    ## PVP设置（1.0版本需要同时启用以下三项才能生效）
    if [ "${ENABLE_PVP:-false}" = "true" ]; then
        set_bool bIsPvP True
        set_bool bEnablePlayerToPlayerDamage True
        set_bool bEnableDefenseOtherGuildPlayer True
        log "已开启PVP（同步启用bIsPvP + bEnablePlayerToPlayerDamage + bEnableDefenseOtherGuildPlayer）"
    fi

    ## 游戏倍率配置（环境变量非空时才覆盖，否则沿用ini默认值）
    [ -n "${DIFFICULTY:-}" ] && set_field Difficulty "${DIFFICULTY}"
    [ -n "${EXP_RATE:-}" ] && set_field ExpRate "${EXP_RATE}" false
    [ -n "${PAL_CAPTURE_RATE:-}" ] && set_field PalCaptureRate "${PAL_CAPTURE_RATE}" false
    [ -n "${PAL_SPAWN_NUM_RATE:-}" ] && set_field PalSpawnNumRate "${PAL_SPAWN_NUM_RATE}" false
    [ -n "${PAL_EGG_HATCHING_TIME:-}" ] && set_field PalEggDefaultHatchingTime "${PAL_EGG_HATCHING_TIME}" false
    [ -n "${WORK_SPEED_RATE:-}" ] && set_field WorkSpeedRate "${WORK_SPEED_RATE}" false
    [ -n "${DAYTIME_SPEED_RATE:-}" ] && set_field DayTimeSpeedRate "${DAYTIME_SPEED_RATE}" false
    [ -n "${NIGHTTIME_SPEED_RATE:-}" ] && set_field NightTimeSpeedRate "${NIGHTTIME_SPEED_RATE}" false
    [ -n "${COLLECTION_DROP_RATE:-}" ] && set_field CollectionDropRate "${COLLECTION_DROP_RATE}" false
    [ -n "${ENEMY_DROP_ITEM_RATE:-}" ] && set_field EnemyDropItemRate "${ENEMY_DROP_ITEM_RATE}" false
    [ -n "${DEATH_PENALTY:-}" ] && set_field DeathPenalty "${DEATH_PENALTY}"

    ## 帕鲁与玩家属性消耗倍率
    [ -n "${PAL_STOMACH_DECREACE_RATE:-}" ] && set_field PalStomachDecreaceRate "${PAL_STOMACH_DECREACE_RATE}" false
    [ -n "${PAL_STAMINA_DECREACE_RATE:-}" ] && set_field PalStaminaDecreaceRate "${PAL_STAMINA_DECREACE_RATE}" false
    [ -n "${PLAYER_STOMACH_DECREACE_RATE:-}" ] && set_field PlayerStomachDecreaceRate "${PLAYER_STOMACH_DECREACE_RATE}" false
    [ -n "${PLAYER_STAMINA_DECREACE_RATE:-}" ] && set_field PlayerStaminaDecreaceRate "${PLAYER_STAMINA_DECREACE_RATE}" false
    [ -n "${PAL_DAMAGE_RATE_ATTACK:-}" ] && set_field PalDamageRateAttack "${PAL_DAMAGE_RATE_ATTACK}" false
    [ -n "${PAL_DAMAGE_RATE_DEFENSE:-}" ] && set_field PalDamageRateDefense "${PAL_DAMAGE_RATE_DEFENSE}" false
    [ -n "${PLAYER_DAMAGE_RATE_ATTACK:-}" ] && set_field PlayerDamageRateAttack "${PLAYER_DAMAGE_RATE_ATTACK}" false
    [ -n "${PLAYER_DAMAGE_RATE_DEFENSE:-}" ] && set_field PlayerDamageRateDefense "${PLAYER_DAMAGE_RATE_DEFENSE}" false

    ## 基地/公会上限设置
    [ -n "${BASE_CAMP_MAX_NUM:-}" ] && set_field BaseCampMaxNum "${BASE_CAMP_MAX_NUM}" false
    [ -n "${BASE_CAMP_WORKER_MAX_NUM:-}" ] && set_field BaseCampWorkerMaxNum "${BASE_CAMP_WORKER_MAX_NUM}" false
    [ -n "${GUILD_PLAYER_MAX_NUM:-}" ] && set_field GuildPlayerMaxNum "${GUILD_PLAYER_MAX_NUM}" false
    [ -n "${DROP_ITEM_MAX_NUM:-}" ] && set_field DropItemMaxNum "${DROP_ITEM_MAX_NUM}" false

    ## 入侵敌人开关（关闭后可降低内存占用，适合低配置服务器）
    [ -n "${ENABLE_INVADER_ENEMY:-}" ] && set_bool bEnableInvaderEnemy "$(to_bool "${ENABLE_INVADER_ENEMY}")"

    ## 恢复严格错误检测，脚本后续命令出错即退出
    set -e
}

# 执行配置更新函数
update_settings
# ====================== 新增幻兽帕鲁配置自动写入模块 结束 ======================

# 替换启动参数变量
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')

# 启动游戏服务器
echo -e "正在启动服务器..."
echo -e ":/home/container$ ${MODIFIED_STARTUP}"
eval ${MODIFIED_STARTUP}