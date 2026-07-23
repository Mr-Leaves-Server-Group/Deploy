#!/bin/bash

# Wait for the container to fully initialize
sleep 1

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Set environment variable that holds the Internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Set environment for Steam Proton
# 兼容新路径 /opt/proton/proton + 旧软链接 /usr/local/bin/proton
if [ -f "/opt/proton/proton" ] || [ -f "/usr/local/bin/proton" ]; then
    if [ ! -z ${SRCDS_APPID} ]; then
        mkdir -p /home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container/.steam/steam"
        export STEAM_COMPAT_DATA_PATH="/home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"
        # Fix for pipx with protontricks
        export PATH=$PATH:/root/.local/bin
    else
        echo -e "----------------------------------------------------------------------------------"
        echo -e "WARNING!!! Proton needs variable SRCDS_APPID, else it will not work. Please add it"
        echo -e "Server stops now"
        echo -e "----------------------------------------------------------------------------------"
        exit 1
    fi
fi

# Switch to the container's working directory
cd /home/container || exit 1

## Update server via SteamCMD if AUTO_UPDATE is 1 or not set
if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then
    echo -e "Checking for game server updates..."
    # Check for set App ID
    if [ ! -z ${SRCDS_APPID} ]; then
        # Set default credentials if they are missing
        if [ "${STEAM_USER}" == "" ]; then
            echo -e "Steam user is not set. Defaulting to anonymous user."
            STEAM_USER=anonymous
            STEAM_PASS=""
            STEAM_AUTH=""
        fi
        # Run SteamCMD
        ./steamcmd/steamcmd.sh +force_install_dir /home/container/Palworld +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) +app_update 1007 +app_update ${SRCDS_APPID} $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) ${INSTALL_FLAGS} $( [[ "${VALIDATE}" == "1" ]] && printf %s 'validate' ) +quit
    else
        echo -e "No App ID set! Skipping check."
    fi
else
    echo -e "Skipping game server update check; Auto Update is set to 0."
fi

# ====================== 新增 Palworld 配置自动写入模块 START ======================
# 配置文件路径（Windows服务端标准路径）
SETTINGS_FILE="/home/container/Palworld/Pal/Saved/Config/WindowsServer/PalWorldSettings.ini"

# 简易日志函数
log() {
    echo -e "[CONFIG] $*"
}

## Convert "true"/"false" strings to "True"/"False" for UE ini format
to_bool() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        true|1|yes) echo "True" ;;
        *) echo "False" ;;
    esac
}

## -----------------------------------------------------------------------------
## Apply environment variables to PalWorldSettings.ini
## Palworld reads identity/network settings from this file, not CLI args.
## We use sed to update specific fields in the OptionSettings tuple.
## Note: Palworld 1.0 has 119 config keys — we only manage the high-value ones
## here. For gameplay rates (EXP, capture, etc.) edit the ini directly.
## -----------------------------------------------------------------------------
update_settings() {
    [ -f "${SETTINGS_FILE}" ] || {
        log "WARN: PalWorldSettings.ini not found, skip config injection"
        return 0
    }

    log "Applying server settings from environment variables"

    ## Disable exit-on-error: sed -i can fail on FUSE/network filesystems
    ## even when the underlying file is writable. We'd rather skip one
    ## broken setting than kill the entire container.
    set +e

    ## Helper: replace a FieldName="value" or FieldName=value in the ini
    set_field() {
        local field="$1" value="$2" quote="${3:-true}"
        if [ "${quote}" = "true" ]; then
            sed -i "s/${field}=\"[^\"]*\"/${field}=\"${value}\"/" "${SETTINGS_FILE}"
        else
            sed -i "s/${field}=[0-9]*/${field}=${value}/" "${SETTINGS_FILE}"
        fi
    }

    ## Helper: replace boolean fields (True/False)
    set_bool() {
        local field="$1" value="$2"
        sed -i "s/${field}=\(True\|False\)/${field}=${value}/" "${SETTINGS_FILE}"
    }

    ## Helper: replace tuple fields like CrossplayPlatforms=(Steam,Xbox,PS5,Mac)
    set_tuple() {
        local field="$1" value="$2"
        sed -i "s/${field}=([^)]*)/${field}=(${value})/" "${SETTINGS_FILE}"
    }

    ## Server identity
    [ -n "${SERVER_NAME:-}" ] && set_field ServerName "${SERVER_NAME}"
    [ -n "${SERVER_DESCRIPTION:-}" ] && set_field ServerDescription "${SERVER_DESCRIPTION}"
    [ -n "${ADMIN_PASSWORD:-}" ] && set_field AdminPassword "${ADMIN_PASSWORD}"
    [ -n "${SERVER_PASSWORD:-}" ] && set_field ServerPassword "${SERVER_PASSWORD}"
    [ -n "${MAX_PLAYERS:-}" ] && set_field ServerPlayerMaxNum "${MAX_PLAYERS}" false

    ## Network (1.0: RCON and REST API are also configurable in the ini)
    [ -n "${RCON_ENABLED:-}" ] && set_bool RCONEnabled "$(to_bool "${RCON_ENABLED}")"
    [ -n "${RCON_PORT:-}" ] && set_field RCONPort "${RCON_PORT}" false
    [ -n "${REST_API_ENABLED:-}" ] && set_bool RESTAPIEnabled "$(to_bool "${REST_API_ENABLED}")"
    [ -n "${REST_API_PORT:-}" ] && set_field RESTAPIPort "${REST_API_PORT}" false

    ## Public IP/port (for NAT/multi-homed setups — only advertises, doesn't change listen port)
    [ -n "${PUBLIC_IP:-}" ] && set_field PublicIP "${PUBLIC_IP}"
    [ -n "${PUBLIC_PORT:-}" ] && set_field PublicPort "${PUBLIC_PORT}" false

    ## Crossplay (1.0: CrossplayPlatforms tuple in PalWorldSettings.ini)
    [ -n "${CROSSPLAY_PLATFORMS:-}" ] && set_tuple CrossplayPlatforms "${CROSSPLAY_PLATFORMS}"

    ## PvP (1.0: requires all three toggles on together)
    if [ "${ENABLE_PVP:-false}" = "true" ]; then
        set_bool bIsPvP True
        set_bool bEnablePlayerToPlayerDamage True
        set_bool bEnableDefenseOtherGuildPlayer True
        log "PvP enabled (bIsPvP + bEnablePlayerToPlayerDamage + bEnableDefenseOtherGuildPlayer)"
    fi

    ## Gameplay multipliers (only set if non-empty — otherwise ini defaults apply)
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

    ## Pal/player stat rates
    [ -n "${PAL_STOMACH_DECREACE_RATE:-}" ] && set_field PalStomachDecreaceRate "${PAL_STOMACH_DECREACE_RATE}" false
    [ -n "${PAL_STAMINA_DECREACE_RATE:-}" ] && set_field PalStaminaDecreaceRate "${PAL_STAMINA_DECREACE_RATE}" false
    [ -n "${PLAYER_STOMACH_DECREACE_RATE:-}" ] && set_field PlayerStomachDecreaceRate "${PLAYER_STOMACH_DECREACE_RATE}" false
    [ -n "${PLAYER_STAMINA_DECREACE_RATE:-}" ] && set_field PlayerStaminaDecreaceRate "${PLAYER_STAMINA_DECREACE_RATE}" false
    [ -n "${PAL_DAMAGE_RATE_ATTACK:-}" ] && set_field PalDamageRateAttack "${PAL_DAMAGE_RATE_ATTACK}" false
    [ -n "${PAL_DAMAGE_RATE_DEFENSE:-}" ] && set_field PalDamageRateDefense "${PAL_DAMAGE_RATE_DEFENSE}" false
    [ -n "${PLAYER_DAMAGE_RATE_ATTACK:-}" ] && set_field PlayerDamageRateAttack "${PLAYER_DAMAGE_RATE_ATTACK}" false
    [ -n "${PLAYER_DAMAGE_RATE_DEFENSE:-}" ] && set_field PlayerDamageRateDefense "${PLAYER_DAMAGE_RATE_DEFENSE}" false

    ## Base/guild limits
    [ -n "${BASE_CAMP_MAX_NUM:-}" ] && set_field BaseCampMaxNum "${BASE_CAMP_MAX_NUM}" false
    [ -n "${BASE_CAMP_WORKER_MAX_NUM:-}" ] && set_field BaseCampWorkerMaxNum "${BASE_CAMP_WORKER_MAX_NUM}" false
    [ -n "${GUILD_PLAYER_MAX_NUM:-}" ] && set_field GuildPlayerMaxNum "${GUILD_PLAYER_MAX_NUM}" false
    [ -n "${DROP_ITEM_MAX_NUM:-}" ] && set_field DropItemMaxNum "${DROP_ITEM_MAX_NUM}" false

    ## Invader enemy (disabling halves RAM — useful for constrained servers)
    [ -n "${ENABLE_INVADER_ENEMY:-}" ] && set_bool bEnableInvaderEnemy "$(to_bool "${ENABLE_INVADER_ENEMY}")"

    ## Restore strict error handling for the rest of the script
    set -e
}

# 执行配置更新
update_settings
# ====================== 新增 Palworld 配置自动写入模块 END ======================

# Replace Startup Variables
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')

# Run the Server
echo -e "Starting server..."
echo -e ":/home/container$ ${MODIFIED_STARTUP}"
eval ${MODIFIED_STARTUP}