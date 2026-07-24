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

    ## ====================== 服务器基础信息 ======================
    [ -n "${SERVER_NAME:-}" ] && set_field ServerName "${SERVER_NAME}"
    [ -n "${SERVER_DESCRIPTION:-}" ] && set_field ServerDescription "${SERVER_DESCRIPTION}"
    [ -n "${ADMIN_PASSWORD:-}" ] && set_field AdminPassword "${ADMIN_PASSWORD}"
    [ -n "${SERVER_PASSWORD:-}" ] && set_field ServerPassword "${SERVER_PASSWORD}"
    [ -n "${MAX_PLAYERS:-}" ] && set_field ServerPlayerMaxNum "${MAX_PLAYERS}" false
    [ -n "${COOP_PLAYER_MAX_NUM:-}" ] && set_field CoopPlayerMaxNum "${COOP_PLAYER_MAX_NUM}" false
    [ -n "${REGION:-}" ] && set_field Region "${REGION}"
    [ -n "${LOG_FORMAT_TYPE:-}" ] && set_field LogFormatType "${LOG_FORMAT_TYPE}"

    ## ====================== 网络与远程管理 ======================
    [ -n "${PUBLIC_IP:-}" ] && set_field PublicIP "${PUBLIC_IP}"
    [ -n "${PUBLIC_PORT:-}" ] && set_field PublicPort "${PUBLIC_PORT}" false
    [ -n "${RCON_ENABLED:-}" ] && set_bool RCONEnabled "$(to_bool "${RCON_ENABLED}")"
    [ -n "${RCON_PORT:-}" ] && set_field RCONPort "${RCON_PORT}" false
    [ -n "${REST_API_ENABLED:-}" ] && set_bool RESTAPIEnabled "$(to_bool "${REST_API_ENABLED}")"
    [ -n "${REST_API_PORT:-}" ] && set_field RESTAPIPort "${REST_API_PORT}" false
    [ -n "${USE_AUTH:-}" ] && set_bool bUseAuth "$(to_bool "${USE_AUTH}")"
    [ -n "${BAN_LIST_URL:-}" ] && set_field BanListURL "${BAN_LIST_URL}"

    ## ====================== 跨平台与联机设置 ======================
    [ -n "${ENABLE_MULTIPLAY:-}" ] && set_bool bIsMultiplay "$(to_bool "${ENABLE_MULTIPLAY}")"
    [ -n "${CROSSPLAY_PLATFORMS:-}" ] && set_tuple CrossplayPlatforms "${CROSSPLAY_PLATFORMS}"
    [ -n "${ALLOW_CLIENT_MOD:-}" ] && set_bool bAllowClientMod "$(to_bool "${ALLOW_CLIENT_MOD}")"

    ## ====================== 游戏核心模式 ======================
    [ -n "${DIFFICULTY:-}" ] && set_field Difficulty "${DIFFICULTY}"
    [ -n "${DEATH_PENALTY:-}" ] && set_field DeathPenalty "${DEATH_PENALTY}"
    [ -n "${ENABLE_HARDCORE:-}" ] && set_bool bHardcore "$(to_bool "${ENABLE_HARDCORE}")"
    [ -n "${ENABLE_PAL_LOST:-}" ] && set_bool bPalLost "$(to_bool "${ENABLE_PAL_LOST}")"
    [ -n "${ENABLE_CHARACTER_RECREATE_IN_HARDCORE:-}" ] && set_bool bCharacterRecreateInHardcore "$(to_bool "${ENABLE_CHARACTER_RECREATE_IN_HARDCORE}")"

    ## ====================== PvP 细节配置 ======================
    [ -n "${ENABLE_PLAYER_TO_PLAYER_DAMAGE:-}" ] && set_bool bEnablePlayerToPlayerDamage "$(to_bool "${ENABLE_PLAYER_TO_PLAYER_DAMAGE}")"
    [ -n "${ENABLE_FRIENDLY_FIRE:-}" ] && set_bool bEnableFriendlyFire "$(to_bool "${ENABLE_FRIENDLY_FIRE}")"
    [ -n "${ENABLE_DEFENSE_OTHER_GUILD_PLAYER:-}" ] && set_bool bEnableDefenseOtherGuildPlayer "$(to_bool "${ENABLE_DEFENSE_OTHER_GUILD_PLAYER}")"
    [ -n "${ENABLE_PICKUP_OTHER_GUILD_DEATH_PENALTY_DROP:-}" ] && set_bool bCanPickupOtherGuildDeathPenaltyDrop "$(to_bool "${ENABLE_PICKUP_OTHER_GUILD_DEATH_PENALTY_DROP}")"
    [ -n "${DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_BASE_CAMP:-}" ] && set_bool bDisplayPvPItemNumOnWorldMap_BaseCamp "$(to_bool "${DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_BASE_CAMP}")"
    [ -n "${DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_PLAYER:-}" ] && set_bool bDisplayPvPItemNumOnWorldMap_Player "$(to_bool "${DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_PLAYER}")"
    [ -n "${ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE:-}" ] && set_field AdditionalDropItemWhenPlayerKillingInPvPMode "${ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE}"
    [ -n "${ADDITIONAL_DROP_ITEM_NUM_WHEN_PLAYER_KILLING_IN_PVP_MODE:-}" ] && set_field AdditionalDropItemNumWhenPlayerKillingInPvPMode "${ADDITIONAL_DROP_ITEM_NUM_WHEN_PLAYER_KILLING_IN_PVP_MODE}" false
    [ -n "${ENABLE_ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE:-}" ] && set_bool bAdditionalDropItemWhenPlayerKillingInPvPMode "$(to_bool "${ENABLE_ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE}")"

    # PvP 一键开启（优先级高于单独配置，同步启用三项核心开关）
    if [ "${ENABLE_PVP:-false}" = "true" ]; then
        set_bool bIsPvP True
        set_bool bEnablePlayerToPlayerDamage True
        set_bool bEnableDefenseOtherGuildPlayer True
        log "已一键开启PVP（同步启用bIsPvP + bEnablePlayerToPlayerDamage + bEnableDefenseOtherGuildPlayer）"
    fi

    ## ====================== 随机化设置 ======================
    [ -n "${RANDOMIZER_TYPE:-}" ] && set_field RandomizerType "${RANDOMIZER_TYPE}"
    [ -n "${RANDOMIZER_SEED:-}" ] && set_field RandomizerSeed "${RANDOMIZER_SEED}"
    [ -n "${ENABLE_RANDOMIZER_PAL_LEVEL_RANDOM:-}" ] && set_bool bIsRandomizerPalLevelRandom "$(to_bool "${ENABLE_RANDOMIZER_PAL_LEVEL_RANDOM}")"

    ## ====================== 时间与全局倍率 ======================
    [ -n "${DAYTIME_SPEED_RATE:-}" ] && set_field DayTimeSpeedRate "${DAYTIME_SPEED_RATE}" false
    [ -n "${NIGHTTIME_SPEED_RATE:-}" ] && set_field NightTimeSpeedRate "${NIGHTTIME_SPEED_RATE}" false
    [ -n "${EXP_RATE:-}" ] && set_field ExpRate "${EXP_RATE}" false
    [ -n "${PAL_CAPTURE_RATE:-}" ] && set_field PalCaptureRate "${PAL_CAPTURE_RATE}" false
    [ -n "${PAL_SPAWN_NUM_RATE:-}" ] && set_field PalSpawnNumRate "${PAL_SPAWN_NUM_RATE}" false
    [ -n "${PAL_EGG_HATCHING_TIME:-}" ] && set_field PalEggDefaultHatchingTime "${PAL_EGG_HATCHING_TIME}" false
    [ -n "${WORK_SPEED_RATE:-}" ] && set_field WorkSpeedRate "${WORK_SPEED_RATE}" false
    [ -n "${AUTO_SAVE_SPAN:-}" ] && set_field AutoSaveSpan "${AUTO_SAVE_SPAN}" false
    [ -n "${SUPPLY_DROP_SPAN:-}" ] && set_field SupplyDropSpan "${SUPPLY_DROP_SPAN}" false
    [ -n "${MONSTER_FARM_ACTION_SPEED_RATE:-}" ] && set_field MonsterFarmActionSpeedRate "${MONSTER_FARM_ACTION_SPEED_RATE}" false

    ## ====================== 玩家属性倍率 ======================
    [ -n "${PLAYER_DAMAGE_RATE_ATTACK:-}" ] && set_field PlayerDamageRateAttack "${PLAYER_DAMAGE_RATE_ATTACK}" false
    [ -n "${PLAYER_DAMAGE_RATE_DEFENSE:-}" ] && set_field PlayerDamageRateDefense "${PLAYER_DAMAGE_RATE_DEFENSE}" false
    [ -n "${PLAYER_STOMACH_DECREACE_RATE:-}" ] && set_field PlayerStomachDecreaceRate "${PLAYER_STOMACH_DECREACE_RATE}" false
    [ -n "${PLAYER_STAMINA_DECREACE_RATE:-}" ] && set_field PlayerStaminaDecreaceRate "${PLAYER_STAMINA_DECREACE_RATE}" false
    [ -n "${PLAYER_AUTO_HP_REGENE_RATE:-}" ] && set_field PlayerAutoHPRegeneRate "${PLAYER_AUTO_HP_REGENE_RATE}" false
    [ -n "${PLAYER_AUTO_HP_REGENE_RATE_IN_SLEEP:-}" ] && set_field PlayerAutoHpRegeneRateInSleep "${PLAYER_AUTO_HP_REGENE_RATE_IN_SLEEP}" false
    [ -n "${ITEM_WEIGHT_RATE:-}" ] && set_field ItemWeightRate "${ITEM_WEIGHT_RATE}" false
    [ -n "${EQUIPMENT_DURABILITY_DAMAGE_RATE:-}" ] && set_field EquipmentDurabilityDamageRate "${EQUIPMENT_DURABILITY_DAMAGE_RATE}" false

    ## ====================== 帕鲁属性倍率 ======================
    [ -n "${PAL_DAMAGE_RATE_ATTACK:-}" ] && set_field PalDamageRateAttack "${PAL_DAMAGE_RATE_ATTACK}" false
    [ -n "${PAL_DAMAGE_RATE_DEFENSE:-}" ] && set_field PalDamageRateDefense "${PAL_DAMAGE_RATE_DEFENSE}" false
    [ -n "${PAL_STOMACH_DECREACE_RATE:-}" ] && set_field PalStomachDecreaceRate "${PAL_STOMACH_DECREACE_RATE}" false
    [ -n "${PAL_STAMINA_DECREACE_RATE:-}" ] && set_field PalStaminaDecreaceRate "${PAL_STAMINA_DECREACE_RATE}" false
    [ -n "${PAL_AUTO_HP_REGENE_RATE:-}" ] && set_field PalAutoHPRegeneRate "${PAL_AUTO_HP_REGENE_RATE}" false
    [ -n "${PAL_AUTO_HP_REGENE_RATE_IN_SLEEP:-}" ] && set_field PalAutoHpRegeneRateInSleep "${PAL_AUTO_HP_REGENE_RATE_IN_SLEEP}" false

    ## ====================== 建筑与采集倍率 ======================
    [ -n "${BUILD_OBJECT_HP_RATE:-}" ] && set_field BuildObjectHpRate "${BUILD_OBJECT_HP_RATE}" false
    [ -n "${BUILD_OBJECT_DAMAGE_RATE:-}" ] && set_field BuildObjectDamageRate "${BUILD_OBJECT_DAMAGE_RATE}" false
    [ -n "${BUILD_OBJECT_DETERIORATION_DAMAGE_RATE:-}" ] && set_field BuildObjectDeteriorationDamageRate "${BUILD_OBJECT_DETERIORATION_DAMAGE_RATE}" false
    [ -n "${COLLECTION_DROP_RATE:-}" ] && set_field CollectionDropRate "${COLLECTION_DROP_RATE}" false
    [ -n "${COLLECTION_OBJECT_HP_RATE:-}" ] && set_field CollectionObjectHpRate "${COLLECTION_OBJECT_HP_RATE}" false
    [ -n "${COLLECTION_OBJECT_RESPAWN_SPEED_RATE:-}" ] && set_field CollectionObjectRespawnSpeedRate "${COLLECTION_OBJECT_RESPAWN_SPEED_RATE}" false
    [ -n "${ENEMY_DROP_ITEM_RATE:-}" ] && set_field EnemyDropItemRate "${ENEMY_DROP_ITEM_RATE}" false

    ## ====================== 掉落物品设置 ======================
    [ -n "${DROP_ITEM_MAX_NUM:-}" ] && set_field DropItemMaxNum "${DROP_ITEM_MAX_NUM}" false
    [ -n "${DROP_ITEM_MAX_NUM_UNKO:-}" ] && set_field DropItemMaxNum_UNKO "${DROP_ITEM_MAX_NUM_UNKO}" false
    [ -n "${DROP_ITEM_ALIVE_MAX_HOURS:-}" ] && set_field DropItemAliveMaxHours "${DROP_ITEM_ALIVE_MAX_HOURS}" false
    [ -n "${PHYSICS_ACTIVE_DROP_ITEM_MAX_NUM:-}" ] && set_field PhysicsActiveDropItemMaxNum "${PHYSICS_ACTIVE_DROP_ITEM_MAX_NUM}" false

    ## ====================== 基地与公会管理 ======================
    [ -n "${BASE_CAMP_MAX_NUM:-}" ] && set_field BaseCampMaxNum "${BASE_CAMP_MAX_NUM}" false
    [ -n "${BASE_CAMP_MAX_NUM_IN_GUILD:-}" ] && set_field BaseCampMaxNumInGuild "${BASE_CAMP_MAX_NUM_IN_GUILD}" false
    [ -n "${BASE_CAMP_WORKER_MAX_NUM:-}" ] && set_field BaseCampWorkerMaxNum "${BASE_CAMP_WORKER_MAX_NUM}" false
    [ -n "${GUILD_PLAYER_MAX_NUM:-}" ] && set_field GuildPlayerMaxNum "${GUILD_PLAYER_MAX_NUM}" false
    [ -n "${ENABLE_AUTO_RESET_GUILD_NO_ONLINE_PLAYERS:-}" ] && set_bool bAutoResetGuildNoOnlinePlayers "$(to_bool "${ENABLE_AUTO_RESET_GUILD_NO_ONLINE_PLAYERS}")"
    [ -n "${AUTO_RESET_GUILD_TIME_NO_ONLINE_PLAYERS:-}" ] && set_field AutoResetGuildTimeNoOnlinePlayers "${AUTO_RESET_GUILD_TIME_NO_ONLINE_PLAYERS}" false
    [ -n "${GUILD_REJOIN_COOLDOWN_MINUTES:-}" ] && set_field GuildRejoinCooldownMinutes "${GUILD_REJOIN_COOLDOWN_MINUTES}" false
    [ -n "${MAX_GUILDS_PER_FRAME:-}" ] && set_field MaxGuildsPerFrame "${MAX_GUILDS_PER_FRAME}" false
    [ -n "${ENABLE_INVISIBLE_OTHER_GUILD_BASE_CAMP_AREA_FX:-}" ] && set_bool bInvisibleOtherGuildBaseCampAreaFX "$(to_bool "${ENABLE_INVISIBLE_OTHER_GUILD_BASE_CAMP_AREA_FX}")"
    [ -n "${ENABLE_BUILD_AREA_LIMIT:-}" ] && set_bool bBuildAreaLimit "$(to_bool "${ENABLE_BUILD_AREA_LIMIT}")"

    ## ====================== 敌人与入侵 ======================
    [ -n "${ENABLE_INVADER_ENEMY:-}" ] && set_bool bEnableInvaderEnemy "$(to_bool "${ENABLE_INVADER_ENEMY}")"
    [ -n "${ENABLE_PREDATOR_BOSS_PAL:-}" ] && set_bool EnablePredatorBossPal "$(to_bool "${ENABLE_PREDATOR_BOSS_PAL}")"
    [ -n "${ENABLE_ACTIVE_UNKO:-}" ] && set_bool bActiveUNKO "$(to_bool "${ENABLE_ACTIVE_UNKO}")"

    ## ====================== 瞄准辅助 ======================
    [ -n "${ENABLE_AIM_ASSIST_PAD:-}" ] && set_bool bEnableAimAssistPad "$(to_bool "${ENABLE_AIM_ASSIST_PAD}")"
    [ -n "${ENABLE_AIM_ASSIST_KEYBOARD:-}" ] && set_bool bEnableAimAssistKeyboard "$(to_bool "${ENABLE_AIM_ASSIST_KEYBOARD}")"

    ## ====================== 存档与数据一致性 ======================
    [ -n "${USE_BACKUP_SAVE_DATA:-}" ] && set_bool bIsUseBackupSaveData "$(to_bool "${USE_BACKUP_SAVE_DATA}")"
    [ -n "${PLAYER_DATA_PAL_STORAGE_UPDATE_CHECK_TICK_INTERVAL:-}" ] && set_field PlayerDataPalStorageUpdateCheckTickInterval "${PLAYER_DATA_PAL_STORAGE_UPDATE_CHECK_TICK_INTERVAL}" false
    [ -n "${ITEM_CONTAINER_FORCE_MARK_DIRTY_INTERVAL:-}" ] && set_field ItemContainerForceMarkDirtyInterval "${ITEM_CONTAINER_FORCE_MARK_DIRTY_INTERVAL}" false
    [ -n "${ITEM_CORRUPTION_MULTIPLIER:-}" ] && set_field ItemCorruptionMultiplier "${ITEM_CORRUPTION_MULTIPLIER}" false

    ## ====================== 旅行与玩家交互 ======================
    [ -n "${ENABLE_NON_LOGIN_PENALTY:-}" ] && set_bool bEnableNonLoginPenalty "$(to_bool "${ENABLE_NON_LOGIN_PENALTY}")"
    [ -n "${ENABLE_FAST_TRAVEL:-}" ] && set_bool bEnableFastTravel "$(to_bool "${ENABLE_FAST_TRAVEL}")"
    [ -n "${ENABLE_FAST_TRAVEL_ONLY_BASE_CAMP:-}" ] && set_bool bEnableFastTravelOnlyBaseCamp "$(to_bool "${ENABLE_FAST_TRAVEL_ONLY_BASE_CAMP}")"
    [ -n "${ENABLE_START_LOCATION_SELECT_BY_MAP:-}" ] && set_bool bIsStartLocationSelectByMap "$(to_bool "${ENABLE_START_LOCATION_SELECT_BY_MAP}")"
    [ -n "${ENABLE_EXIST_PLAYER_AFTER_LOGOUT:-}" ] && set_bool bExistPlayerAfterLogout "$(to_bool "${ENABLE_EXIST_PLAYER_AFTER_LOGOUT}")"
    [ -n "${SHOW_PLAYER_LIST:-}" ] && set_bool bShowPlayerList "$(to_bool "${SHOW_PLAYER_LIST}")"
    [ -n "${SHOW_JOIN_LEFT_MESSAGE:-}" ] && set_bool bIsShowJoinLeftMessage "$(to_bool "${SHOW_JOIN_LEFT_MESSAGE}")"
    [ -n "${CHAT_POST_LIMIT_PER_MINUTE:-}" ] && set_field ChatPostLimitPerMinute "${CHAT_POST_LIMIT_PER_MINUTE}" false

    ## ====================== 帕鲁箱进出口 ======================
    [ -n "${ALLOW_GLOBAL_PALBOX_EXPORT:-}" ] && set_bool bAllowGlobalPalboxExport "$(to_bool "${ALLOW_GLOBAL_PALBOX_EXPORT}")"
    [ -n "${ALLOW_GLOBAL_PALBOX_IMPORT:-}" ] && set_bool bAllowGlobalPalboxImport "$(to_bool "${ALLOW_GLOBAL_PALBOX_IMPORT}")"

    ## ====================== 科技禁用列表 ======================
    [ -n "${DENY_TECHNOLOGY_LIST:-}" ] && set_tuple DenyTechnologyList "${DENY_TECHNOLOGY_LIST}"

    ## ====================== 重生与惩罚机制 ======================
    [ -n "${BLOCK_RESPAWN_TIME:-}" ] && set_field BlockRespawnTime "${BLOCK_RESPAWN_TIME}" false
    [ -n "${RESPAWN_PENALTY_DURATION_THRESHOLD:-}" ] && set_field RespawnPenaltyDurationThreshold "${RESPAWN_PENALTY_DURATION_THRESHOLD}" false
    [ -n "${RESPAWN_PENALTY_TIME_SCALE:-}" ] && set_field RespawnPenaltyTimeScale "${RESPAWN_PENALTY_TIME_SCALE}" false

    ## ====================== 属性增强权限 ======================
    [ -n "${ALLOW_ENHANCE_STAT_HEALTH:-}" ] && set_bool bAllowEnhanceStat_Health "$(to_bool "${ALLOW_ENHANCE_STAT_HEALTH}")"
    [ -n "${ALLOW_ENHANCE_STAT_ATTACK:-}" ] && set_bool bAllowEnhanceStat_Attack "$(to_bool "${ALLOW_ENHANCE_STAT_ATTACK}")"
    [ -n "${ALLOW_ENHANCE_STAT_STAMINA:-}" ] && set_bool bAllowEnhanceStat_Stamina "$(to_bool "${ALLOW_ENHANCE_STAT_STAMINA}")"
    [ -n "${ALLOW_ENHANCE_STAT_WEIGHT:-}" ] && set_bool bAllowEnhanceStat_Weight "$(to_bool "${ALLOW_ENHANCE_STAT_WEIGHT}")"
    [ -n "${ALLOW_ENHANCE_STAT_WORK_SPEED:-}" ] && set_bool bAllowEnhanceStat_WorkSpeed "$(to_bool "${ALLOW_ENHANCE_STAT_WORK_SPEED}")"

    ## ====================== 公会自动管理 ======================
    [ -n "${AUTO_TRANSFER_MASTER_CHECK_INTERVAL_SECONDS:-}" ] && set_field AutoTransferMasterCheckIntervalSeconds "${AUTO_TRANSFER_MASTER_CHECK_INTERVAL_SECONDS}" false
    [ -n "${AUTO_TRANSFER_MASTER_THRESHOLD_DAYS:-}" ] && set_field AutoTransferMasterThresholdDays "${AUTO_TRANSFER_MASTER_THRESHOLD_DAYS}" false

    ## ====================== 语音聊天 ======================
    [ -n "${ENABLE_VOICE_CHAT:-}" ] && set_bool bEnableVoiceChat "$(to_bool "${ENABLE_VOICE_CHAT}")"
    [ -n "${VOICE_CHAT_MAX_VOLUME_DISTANCE:-}" ] && set_field VoiceChatMaxVolumeDistance "${VOICE_CHAT_MAX_VOLUME_DISTANCE}" false
    [ -n "${VOICE_CHAT_ZERO_VOLUME_DISTANCE:-}" ] && set_field VoiceChatZeroVolumeDistance "${VOICE_CHAT_ZERO_VOLUME_DISTANCE}" false

    ## ====================== 建筑显示 ======================
    [ -n "${ENABLE_BUILDING_PLAYER_UID_DISPLAY:-}" ] && set_bool bEnableBuildingPlayerUIdDisplay "$(to_bool "${ENABLE_BUILDING_PLAYER_UID_DISPLAY}")"
    [ -n "${BUILDING_NAME_DISPLAY_CACHE_TTL_SECONDS:-}" ] && set_field BuildingNameDisplayCacheTTLSeconds "${BUILDING_NAME_DISPLAY_CACHE_TTL_SECONDS}" false

    ## ====================== 性能与网络视野 ======================
    [ -n "${MAX_BUILDING_LIMIT_NUM:-}" ] && set_field MaxBuildingLimitNum "${MAX_BUILDING_LIMIT_NUM}" false
    [ -n "${SERVER_REPLICATE_PAWN_CULL_DISTANCE:-}" ] && set_field ServerReplicatePawnCullDistance "${SERVER_REPLICATE_PAWN_CULL_DISTANCE}" false

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