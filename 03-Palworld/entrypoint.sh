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
    echo -e "[菜菜云MLSG] $*"
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
        log "警告：未找到配置文件"
        log "请检查文件：${SETTINGS_FILE}"
        return 0
    }

    log "游戏参数配置 - 开始写入"

    ## 关闭命令错误退出：在FUSE/网络文件系统下sed -i可能出现误报错
    ## 宁可跳过单条配置修改，也不要直接终止整个容器
    set +e

    ## 工具函数：修改配置项 FieldName="value" 或 FieldName=value
    set_field() {
        local field="$1" value="$2" quote="${3:-true}"
        if [ "${quote}" = "true" ]; then
            sed -i "s/${field}=\"[^\"]*\"/${field}=\"${value}\"/" "${SETTINGS_FILE}"
        else
            # 修复：支持小数倍率匹配（原正则仅匹配整数）
            sed -i "s/${field}=[0-9.-]*/${field}=${value}/" "${SETTINGS_FILE}"
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

    # ==================== 新增封装：统一执行+打印日志 ====================
    # 使用示例：
    # apply_config "ServerDescription" "${SERVER_DESCRIPTION}" "field" true
    # apply_config "RCONEnabled" "${RCON_BOOL}" "bool"
    # apply_config "CrossplayPlatforms" "${CROSSPLAY_PLATFORMS}" "tuple"
    apply_config() {
        local ini_key="$1"
        local env_val="$2"
        local mode="$3"
        local quote_flag="${4:-true}"

        if [ -z "${env_val}" ]; then
            return 0
        fi

        case "${mode}" in
            field)
                set_field "${ini_key}" "${env_val}" "${quote_flag}"
                ;;
            bool)
                local real_val="$(to_bool "${env_val}")"
                set_bool "${ini_key}" "${real_val}"
                env_val="${real_val}"
                ;;
            tuple)
                set_tuple "${ini_key}" "${env_val}"
                ;;
        esac

        log "[配置] 写入 ${ini_key} = ${env_val}"
    }

    ## ====================== 服务器基础标识 ======================
    # ⚠️ 【被启动命令参数覆盖，INI写入失效，保留注释仅供查阅】
    # [ -n "${SERVER_NAME:-}" ] && set_field ServerName "${SERVER_NAME}"
    # [ -n "${SERVER_PASSWORD:-}" ] && set_field ServerPassword "${SERVER_PASSWORD}"
    # [ -n "${ADMIN_PASSWORD:-}" ] && set_field AdminPassword "${ADMIN_PASSWORD}"
    # [ -n "${MAX_PLAYERS:-}" ] && set_field ServerPlayerMaxNum "${MAX_PLAYERS}" false

    apply_config "ServerDescription" "${SERVER_DESCRIPTION}" "field"

    ## ====================== 网络与远程管理 ======================
    apply_config "PublicIP" "${PUBLIC_IP}" "field"
    # ⚠️ 【被启动命令参数覆盖，INI写入失效，保留注释仅供查阅】
    # [ -n "${PUBLIC_PORT:-}" ] && set_field PublicPort "${PUBLIC_PORT}" false

    apply_config "RCONEnabled" "${RCON_ENABLE}" "bool"
    apply_config "RCONPort" "${RCON_PORT}" "field" false
    apply_config "RESTAPIEnabled" "${REST_API_ENABLED}" "bool"
    apply_config "RESTAPIPort" "${REST_API_PORT}" "field" false
    apply_config "bUseAuth" "${USE_AUTH}" "bool"
    #[ -n "${BAN_LIST_URL:-}" ] && set_field BanListURL "${BAN_LIST_URL}"
    #[ -n "${REGION:-}" ] && set_field Region "${REGION}"
    apply_config "LogFormatType" "${LOG_FORMAT_TYPE}" "field"

    ## ====================== 跨平台与联机设置 ======================
    #[ -n "${ENABLE_MULTIPLAY:-}" ] && set_bool bIsMultiplay "$(to_bool "${ENABLE_MULTIPLAY}")"
    apply_config "CrossplayPlatforms" "${CROSSPLAY_PLATFORMS}" "tuple"
    #[ -n "${ALLOW_CLIENT_MOD:-}" ] && set_bool bAllowClientMod "$(to_bool "${ALLOW_CLIENT_MOD}")"

    ## ====================== 游戏核心模式 ======================
    apply_config "Difficulty" "${DIFFICULTY}" "field"
    apply_config "DeathPenalty" "${DEATH_PENALTY}" "field"
    apply_config "bHardcore" "${ENABLE_HARDCORE}" "bool"
    #[ -n "${ENABLE_PAL_LOST:-}" ] && set_bool bPalLost "$(to_bool "${ENABLE_PAL_LOST}")"
    #[ -n "${ENABLE_CHARACTER_RECREATE_IN_HARDCORE:-}" ] && set_bool bCharacterRecreateInHardcore "$(to_bool "${ENABLE_CHARACTER_RECREATE_IN_HARDCORE}")"

    ## ====================== PvP 细节配置 ======================
    apply_config "bIsPvP" "${ENABLE_PVP}" "bool"
    apply_config "bEnablePlayerToPlayerDamage" "${ENABLE_PLAYER_TO_PLAYER_DAMAGE}" "bool"
    apply_config "bEnableFriendlyFire" "${ENABLE_FRIENDLY_FIRE}" "bool"
    apply_config "bEnableDefenseOtherGuildPlayer" "${ENABLE_DEFENSE_OTHER_GUILD_PLAYER}" "bool"
    apply_config "bCanPickupOtherGuildDeathPenaltyDrop" "${ENABLE_PICKUP_OTHER_GUILD_DEATH_PENALTY_DROP}" "bool"
    #[ -n "${DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_BASE_CAMP:-}" ] && set_bool bDisplayPvPItemNumOnWorldMap_BaseCamp "$(to_bool "${DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_BASE_CAMP}")"
    #[ -n "${DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_PLAYER:-}" ] && set_bool bDisplayPvPItemNumOnWorldMap_Player "$(to_bool "${DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_PLAYER}")"
    #[ -n "${ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE:-}" ] && set_field AdditionalDropItemWhenPlayerKillingInPvPMode "${ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE}"
    apply_config "AdditionalDropItemNumWhenPlayerKillingInPvPMode" "${ADDITIONAL_DROP_ITEM_NUM_WHEN_PLAYER_KILLING_IN_PVP_MODE}" "field" false
    apply_config "bAdditionalDropItemWhenPlayerKillingInPvPMode" "${ENABLE_ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE}" "bool"

    ## ====================== 时间与全局倍率 ======================
    apply_config "DayTimeSpeedRate" "${DAYTIME_SPEED_RATE}" "field" false
    apply_config "NightTimeSpeedRate" "${NIGHTTIME_SPEED_RATE}" "field" false
    apply_config "ExpRate" "${EXP_RATE}" "field" false
    apply_config "PalCaptureRate" "${PAL_CAPTURE_RATE}" "field" false
    apply_config "PalSpawnNumRate" "${PAL_SPAWN_NUM_RATE}" "field" false
    apply_config "PalEggDefaultHatchingTime" "${PAL_EGG_HATCHING_TIME}" "field" false
    apply_config "WorkSpeedRate" "${WORK_SPEED_RATE}" "field" false
    apply_config "AutoSaveSpan" "${AUTO_SAVE_SPAN}" "field" false
    apply_config "SupplyDropSpan" "${SUPPLY_DROP_SPAN}" "field" false
    apply_config "MonsterFarmActionSpeedRate" "${MONSTER_FARM_ACTION_SPEED_RATE}" "field" false

    ## ====================== 玩家属性倍率 ======================
    apply_config "PlayerDamageRateAttack" "${PLAYER_DAMAGE_RATE_ATTACK}" "field" false
    apply_config "PlayerDamageRateDefense" "${PLAYER_DAMAGE_RATE_DEFENSE}" "field" false
    apply_config "PlayerStomachDecreaceRate" "${PLAYER_STOMACH_DECREACE_RATE}" "field" false
    apply_config "PlayerStaminaDecreaceRate" "${PLAYER_STAMINA_DECREACE_RATE}" "field" false
    apply_config "PlayerAutoHPRegeneRate" "${PLAYER_AUTO_HP_REGENE_RATE}" "field" false
    apply_config "PlayerAutoHpRegeneRateInSleep" "${PLAYER_AUTO_HP_REGENE_RATE_IN_SLEEP}" "field" false
    apply_config "ItemWeightRate" "${ITEM_WEIGHT_RATE}" "field" false
    apply_config "EquipmentDurabilityDamageRate" "${EQUIPMENT_DURABILITY_DAMAGE_RATE}" "field" false

    ## ====================== 帕鲁属性倍率 ======================
    apply_config "PalDamageRateAttack" "${PAL_DAMAGE_RATE_ATTACK}" "field" false
    apply_config "PalDamageRateDefense" "${PAL_DAMAGE_RATE_DEFENSE}" "field" false
    apply_config "PalStomachDecreaceRate" "${PAL_STOMACH_DECREACE_RATE}" "field" false
    apply_config "PalStaminaDecreaceRate" "${PAL_STAMINA_DECREACE_RATE}" "field" false
    apply_config "PalAutoHPRegeneRate" "${PAL_AUTO_HP_REGENE_RATE}" "field" false
    apply_config "PalAutoHpRegeneRateInSleep" "${PAL_AUTO_HP_REGENE_RATE_IN_SLEEP}" "field" false

    ## ====================== 建筑与采集倍率 ======================
    apply_config "BuildObjectHpRate" "${BUILD_OBJECT_HP_RATE}" "field" false
    apply_config "BuildObjectDamageRate" "${BUILD_OBJECT_DAMAGE_RATE}" "field" false
    apply_config "BuildObjectDeteriorationDamageRate" "${BUILD_OBJECT_DETERIORATION_DAMAGE_RATE}" "field" false
    apply_config "CollectionDropRate" "${COLLECTION_DROP_RATE}" "field" false
    apply_config "CollectionObjectHpRate" "${COLLECTION_OBJECT_HP_RATE}" "field" false
    apply_config "CollectionObjectRespawnSpeedRate" "${COLLECTION_OBJECT_RESPAWN_SPEED_RATE}" "field" false
    apply_config "EnemyDropItemRate" "${ENEMY_DROP_ITEM_RATE}" "field" false

    ## ====================== 掉落物品设置 ======================
    apply_config "DropItemMaxNum" "${DROP_ITEM_MAX_NUM}" "field" false
    apply_config "DropItemMaxNum_UNKO" "${DROP_ITEM_MAX_NUM_UNKO}" "field" false
    apply_config "DropItemAliveMaxHours" "${DROP_ITEM_ALIVE_MAX_HOURS}" "field" false
    #[ -n "${PHYSICS_ACTIVE_DROP_ITEM_MAX_NUM:-}" ] && set_field PhysicsActiveDropItemMaxNum "${PHYSICS_ACTIVE_DROP_ITEM_MAX_NUM}" false

    ## ====================== 基地与公会管理 ======================
    apply_config "BaseCampMaxNum" "${BASE_CAMP_MAX_NUM}" "field" false
    apply_config "BaseCampMaxNumInGuild" "${BASE_CAMP_MAX_NUM_IN_GUILD}" "field" false
    apply_config "BaseCampWorkerMaxNum" "${BASE_CAMP_WORKER_MAX_NUM}" "field" false
    apply_config "GuildPlayerMaxNum" "${GUILD_PLAYER_MAX_NUM}" "field" false
    apply_config "bAutoResetGuildNoOnlinePlayers" "${ENABLE_AUTO_RESET_GUILD_NO_ONLINE_PLAYERS}" "bool"
    apply_config "AutoResetGuildTimeNoOnlinePlayers" "${AUTO_RESET_GUILD_TIME_NO_ONLINE_PLAYERS}" "field" false
    #[ -n "${GUILD_REJOIN_COOLDOWN_MINUTES:-}" ] && set_field GuildRejoinCooldownMinutes "${GUILD_REJOIN_COOLDOWN_MINUTES}" false
    #[ -n "${MAX_GUILDS_PER_FRAME:-}" ] && set_field MaxGuildsPerFrame "${MAX_GUILDS_PER_FRAME}" false
    #[ -n "${ENABLE_INVISIBLE_OTHER_GUILD_BASE_CAMP_AREA_FX:-}" ] && set_bool bInvisibleOtherGuildBaseCampAreaFX "$(to_bool "${ENABLE_INVISIBLE_OTHER_GUILD_BASE_CAMP_AREA_FX}")"
    #[ -n "${ENABLE_BUILD_AREA_LIMIT:-}" ] && set_bool bBuildAreaLimit "$(to_bool "${ENABLE_BUILD_AREA_LIMIT}")"

    ## ====================== 敌人与入侵 ======================
    apply_config "bEnableInvaderEnemy" "${ENABLE_ENEMY}" "bool"
    apply_config "EnablePredatorBossPal" "${ENABLE_PREDATOR_BOSS_PAL}" "bool"

    ## ====================== 帕鲁箱进出口 ======================
    apply_config "bAllowGlobalPalboxExport" "${ALLOW_GLOBAL_PALBOX_EXPORT}" "bool"
    apply_config "bAllowGlobalPalboxImport" "${ALLOW_GLOBAL_PALBOX_IMPORT}" "bool"

    ## ====================== 重生与惩罚机制 ======================
    #[ -n "${BLOCK_RESPAWN_TIME:-}" ] && set_field BlockRespawnTime "${BLOCK_RESPAWN_TIME}" false
    #[ -n "${RESPAWN_PENALTY_DURATION_THRESHOLD:-}" ] && set_field RespawnPenaltyDurationThreshold "${RESPAWN_PENALTY_DURATION_THRESHOLD}" false
    #[ -n "${RESPAWN_PENALTY_TIME_SCALE:-}" ] && set_field RespawnPenaltyTimeScale "${RESPAWN_PENALTY_TIME_SCALE}" false

    ## ====================== 属性增强权限 ======================
    apply_config "bAllowEnhanceStat_Health" "${ALLOW_ENHANCE_STAT_HEALTH}" "bool"
    apply_config "bAllowEnhanceStat_Attack" "${ALLOW_ENHANCE_STAT_ATTACK}" "bool"
    apply_config "bAllowEnhanceStat_Stamina" "${ALLOW_ENHANCE_STAT_STAMINA}" "bool"
    apply_config "bAllowEnhanceStat_Weight" "${ALLOW_ENHANCE_STAT_WEIGHT}" "bool"
    apply_config "bAllowEnhanceStat_WorkSpeed" "${ALLOW_ENHANCE_STAT_WORK_SPEED}" "bool"

    ## ====================== 建筑显示 ======================
    #[ -n "${ENABLE_BUILDING_PLAYER_UID_DISPLAY:-}" ] && set_bool bEnableBuildingPlayerUIdDisplay "$(to_bool "${ENABLE_BUILDING_PLAYER_UID_DISPLAY}")"
    #[ -n "${BUILDING_NAME_DISPLAY_CACHE_TTL_SECONDS:-}" ] && set_field BuildingNameDisplayCacheTTLSeconds "${BUILDING_NAME_DISPLAY_CACHE_TTL_SECONDS}" false

    ## ====================== 性能与网络视野 ======================
    apply_config "MaxBuildingLimitNum" "${MAX_BUILDING_LIMIT_NUM}" "field" false
    #[ -n "${SERVER_REPLICATE_PAWN_CULL_DISTANCE:-}" ] && set_field ServerReplicatePawnCullDistance "${SERVER_REPLICATE_PAWN_CULL_DISTANCE}" false

    log "游戏参数配置 - 写入完成"
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