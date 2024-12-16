#!/bin/bash

# This script is used to updates Arma 3 mods
# Main purpose of this is to update server mods via account with SteamGuard enabled
# It counts that server is running in pterodactyl panel 
# Egg: ghcr.io/parkervcp/games:arma3

# Part of this script is taken from entrypoint.sh script from above mentioned egg, credits are below
## File: Pterodactyl Arma 3 Image - entrypoint.sh
## Author: David Wolfe (Red-Thirten)
## Contributors: Aussie Server Hosts (https://aussieserverhosts.com/), Stephen White (SilK)
## Date: 2022/11/26

# Color Codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# First argument is pterodactyl volume path, second is steam username, third is mod list filename, for password you will be prompted -> for security reasons

VOLUME_PATH=$1
GAME_ID=107410 # Arma 3 game ID
WORKSHOP_DIR="$VOLUME_PATH/steamapps/workshop"
STEAMCMD="$VOLUME_PATH/steamcmd/steamcmd.sh"
STEAM_USER=$2
MOD_LIST="$VOLUME_PATH/$3"
IMAGE_NAME="ghcr.io/parkervcp/games:arma3"
STEAMCMD_ATTEMPTS=3
STEAMCMD_LOG="/tmp/steamcmd.log"



if [ "$#" -ne 3 ]; then
    echo -e "${RED}Illegal number of parameters${NC}"
    echo -e "${YELLOW}Usage: ./auto_updater.sh <VOLUME_PATH> <STEAM_USER> <MOD_LIST>${NC}"
    exit 1
fi

# Must be run under root
if [ $(id -u) -ne 0 ]; then
    echo -e "${RED}This script must be run as root${NC}"
    exit 1
fi

chown -R root:root $VOLUME_PATH

read -sp "Enter password for $STEAM_USER: " password
echo ""

if [ -z "$password" ]; then
    echo -e "${RED}Password cannot be empty${NC}"
    exit 1
fi

# Check for steamcmd, mod list and volume path
if [ ! -f "$VOLUME_PATH/steamcmd/steamcmd.sh" ]; then
    echo -e "${RED}SteamCMD not found in $VOLUME_PATH${NC}"
    exit 1
fi

if [ ! -f "$MOD_LIST" ]; then
    echo -e "${RED}Mod list not found in $VOLUME_PATH${NC}"
    exit 1
fi

# Check if server is running
docker ps | grep $IMAGE_NAME > /dev/null
if [ $? == 0 ]; then
    echo -e "${RED}Server is running, please stop it before updating mods${NC}"
    exit 1
fi

if [[ -f ${MOD_LIST} ]] && [[ -n "$(cat ${MOD_LIST} | grep 'Created by Arma 3 Launcher')" ]]; then # If the mod list file exists and is valid, parse and add mods to the client-side mods list
    CLIENT_MODS+=$(cat ${MOD_LIST} | grep 'id=' | cut -d'=' -f3 | cut -d'"' -f1 | xargs printf '@%s;')
elif [[ -n "${MOD_LIST}" ]]; then # If MOD_FILE is not null, warn user file is missing or invalid
    echo -e "\n${RED}[ERROR]: Arma 3 Modlist file \"${CYAN}${MOD_LIST}${RED}\" could not be found, or is invalid!${NC}"
    echo -e "\t  Ensure your uploaded modlist's file name matches your Startup Parameter."
    echo -e "\t  Only files exported from an Arma 3 Launcher are permitted."

    exit 1
fi

echo -e "\n${GREEN}[UPDATE]:${NC} Checking all ${CYAN}Steam Workshop mods${NC} for updates..."

# ===== Function to update mods via steamCMD =====

function RunSteamCMD(){
    if [[ -f "${STEAMCMD_LOG}" ]]; then
        rm -f "${STEAMCMD_LOG:?}"
    fi

    if ! [[ "$1" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[ERROR]: Invalid modID ($1) provided. Skipping...${NC}"
        return 0
    fi

    updateAttempt=0
    while (( $updateAttempt < $STEAMCMD_ATTEMPTS )); do # Loop for specified number of attempts
        # Increment attempt counter
        updateAttempt=$((updateAttempt+1))

        if (( $updateAttempt > 1 )); then # Notify if not first attempt
            echo -e "\t  ${YELLOW}Re-Attempting download/update in 3 seconds...${NC} (Attempt ${CYAN}${updateAttempt}${NC} of ${CYAN}${STEAMCMD_ATTEMPTS}${NC})\n"
            sleep 3
        fi
        echo "Downloading mod $1"
        ${STEAMCMD} +force_install_dir $VOLUME_PATH "+login \"${STEAM_USER}\" \"${STEAM_PASS}\"" +workshop_download_item $GAME_ID $1 +quit | tee -a "${STEAMCMD_LOG}"

        # Error checking for SteamCMD
        steamcmdExitCode=${PIPESTATUS[0]}
        loggedErrors=$(grep -i "error\|failed" "${STEAMCMD_LOG}" | grep -iv "setlocal\|SDL\|steamservice\|thread")
        if [[ -n ${loggedErrors} ]]; then # Catch errors (ignore setlocale, SDL, steamservice, and thread priority warnings)
            # Soft errors
            if [[ -n $(grep -i "Timeout downloading item" "${STEAMCMD_LOG}") ]]; then # Mod download timeout
                echo -e "\n${YELLOW}[UPDATE]: ${NC}Timeout downloading Steam Workshop mod: \"${CYAN}${modName}${NC}\" (${CYAN}${1}${NC})"
                echo -e "\t  (This is expected for particularly large mods)"
            elif [[ -n $(grep -i "0x402\|0x6\|0x602" "${STEAMCMD_LOG}") ]]; then # Connection issue with Steam
                echo -e "\n${YELLOW}[UPDATE]: ${NC}Connection issue with Steam servers."
                echo -e "\t  (Steam servers may currently be down, or a connection cannot be made reliably)"
            # Hard errors
            elif [[ -n $(grep -i "Password check for AppId" "${STEAMCMD_LOG}") ]]; then # Incorrect beta branch password
                echo -e "\n${RED}[UPDATE]: ${YELLOW}Incorrect password given for beta branch. ${CYAN}Skipping download...${NC}"
                echo -e "\t  (Check your \"[ADVANCED] EXTRA FLAGS FOR STEAMCMD\" startup parameter)"
                break
            # Fatal errors
            elif [[ -n $(grep -i "Invalid Password\|two-factor\|No subscription" "${STEAMCMD_LOG}") ]]; then # Wrong username/password, Steam Guard is turned on, or host is using anonymous account
                echo -e "\n${RED}[UPDATE]: Cannot login to Steam - Improperly configured account and/or credentials"
                echo -e "\t  ${YELLOW}Please contact your administrator/host and give them the following message:${NC}"
                echo -e "\t  ${CYAN}Your Egg, or your client's server, is not configured with valid Steam credentials.${NC}"
                echo -e "\t  ${CYAN}Either the username/password is wrong, or Steam Guard is not properly configured"
                echo -e "\t  ${CYAN}according to this egg's documentation/README.${NC}\n"
                exit 1
            elif [[ -n $(grep -i "Download item" "${STEAMCMD_LOG}") ]]; then # Steam account does not own base game for mod downloads, or unknown
                echo -e "\n${RED}[UPDATE]: Cannot download mod - Download failed"
                echo -e "\t  ${YELLOW}While unknown, this error is likely due to your host's Steam account not owning the base game.${NC}"
                echo -e "\t  ${YELLOW}(Please contact your administrator/host if this issue persists)${NC}\n"
                exit 1
            elif [[ -n $(grep -i "0x202\|0x212" "${STEAMCMD_LOG}") ]]; then # Not enough disk space
                echo -e "\n${RED}[UPDATE]: Unable to complete download - Not enough storage"
                echo -e "\t  ${YELLOW}You have run out of your allotted disk space.${NC}"
                echo -e "\t  ${YELLOW}Please contact your administrator/host for potential storage upgrades.${NC}\n"
                exit 1
            elif [[ -n $(grep -i "0x606" "${STEAMCMD_LOG}") ]]; then # Disk write failure
                echo -e "\n${RED}[UPDATE]: Unable to complete download - Disk write failure"
                echo -e "\t  ${YELLOW}This is normally caused by directory permissions issues,"
                echo -e "\t  ${YELLOW}but could be a more serious hardware issue.${NC}"
                echo -e "\t  ${YELLOW}(Please contact your administrator/host if this issue persists)${NC}\n"
                exit 1
            else # Unknown caught error
                echo -e "\n${RED}[UPDATE]: ${YELLOW}An unknown error has occurred with SteamCMD. ${CYAN}Skipping download...${NC}"
                echo -e "SteamCMD Errors:\n${loggedErrors}"
                echo -e "\t  ${YELLOW}(Please contact your administrator/host if this issue persists)${NC}\n"
                break
            fi
        elif [[ $steamcmdExitCode != 0 ]]; then # Unknown fatal error
            echo -e "\n${RED}[UPDATE]: SteamCMD has crashed for an unknown reason!${NC} (Exit code: ${CYAN}${steamcmdExitCode}${NC})"
            echo -e "\t  ${YELLOW}(Please contact your administrator/host for support)${NC}\n"
            echo -e "SteamCMD Errors:\n${loggedErrors}"
            exit $steamcmdExitCode
        else # Success!
            # Move the downloaded mod to the root directory, and replace existing mod if needed
            mkdir -p ${VOLUME_PATH}/@${1}
            rm -rf ${VOLUME_PATH}/@${1}/*
            mv -f ${WORKSHOP_DIR}/content/$GAME_ID/$1/* ${VOLUME_PATH}/@${1}/
            rm -d ${WORKSHOP_DIR}/content/$GAME_ID/$1
            # Make the mods contents all lowercase
            ModsLowercase @${1}
            # Move any .bikey's to the keys directory
            echo -e "\t  Moving any mod ${CYAN}.bikey${NC} files to the ${CYAN}~/keys/${NC} folder..."
            find ${VOLUME_PATH}/@$1 -name "*.bikey" -type f -exec cp {} ./keys \;
            echo -e "\n${GREEN}[UPDATE]: ${NC}Mod download/update for \"${CYAN}${modName}${NC}\" (${CYAN}${1}${NC}) ${GREEN}completed successfully!${NC}"
            break
        fi
        if (( $updateAttempt == $STEAMCMD_ATTEMPTS )); then # Notify if failed last attempt
            if [[ $1 == 0 ]]; then # Server
                echo -e "\t  ${RED}Final attempt made! ${YELLOW}Unable to complete game server update. ${CYAN}Skipping...${NC}"
                echo -e "\t  (Please try again at a later time)"
                sleep 3
            else # Mod
                echo -e "\t  ${RED}Final attempt made! ${YELLOW}Unable to complete mod download/update. ${CYAN}Skipping...${NC}"
                echo -e "\t  (You may try again later, or manually upload this mod to your server via SFTP)"
                sleep 3
            fi
        fi
    done
}

function ModsLowercase() {
    echo -e "\n\t  Making mod ${CYAN}$1${NC} files/folders lowercase..."
    for SRC in `find ${VOLUME_PATH}/$1 -depth`
    do
        DST=`dirname "${SRC}"`/`basename "${SRC}" | tr '[A-Z]' '[a-z]'`
        if [ "${SRC}" != "${DST}" ]
        then
            [ ! -e "${DST}" ] && mv -T "${SRC}" "${DST}"
        fi
    done
}

function RemoveDuplicates() { #[Input: str - Output: printf of new str]
    if [[ -n $1 ]]; then # If nothing to compare, skip to prevent extra semicolon being returned
        echo $1 | sed -e 's/;/\n/g' | sort -u | xargs printf '%s;'
    fi
}

allMods+=$CLIENT_MODS
allMods=$(RemoveDuplicates ${allMods}) # Remove duplicate mods from allMods, if present
allMods=$(echo $allMods | sed -e 's/;/ /g') # Convert from string to array

# Update mods
for modID in $(echo $allMods | sed -e 's/@//g')
    do
        # If the update time is valid and newer than the local directory's creation date, or the mod hasn't been downloaded yet, download the mod
        if [[ ! -d $modDir ]] || [[ ( -n $latestUpdate ) && ( $latestUpdate =~ ^[0-9]+$ ) && ( $latestUpdate > $(find $modDir | head -1 | xargs stat -c%Y) ) ]]; then
            # Get the mod's name from the Workshop page as well
            modName=$(curl -sL https://steamcommunity.com/sharedfiles/filedetails/changelog/$modID | grep 'workshopItemTitle' | cut -d'>' -f2 | cut -d'<' -f1)
            if [[ -z $modName ]]; then # Set default name if unavailable
                modName="[NAME UNAVAILABLE]"
            fi
            if [[ ! -d $modDir ]]; then
                echo -e "\n${GREEN}[UPDATE]:${NC} Downloading new Mod: \"${CYAN}${modName}${NC}\" (${CYAN}${modID}${NC})"
            else
                echo -e "\n${GREEN}[UPDATE]:${NC} Mod update found for: \"${CYAN}${modName}${NC}\" (${CYAN}${modID}${NC})"
            fi
            if [[ -n $latestUpdate ]] && [[ $latestUpdate =~ ^[0-9]+$ ]]; then # Notify last update date, if valid
                echo -e "\t  Mod was last updated: ${CYAN}$(date -d @${latestUpdate})${NC}"
            fi
            
            # Delete SteamCMD appworkshop cache before running to avoid mod download failures
            echo -e "\t  Clearing SteamCMD appworkshop cache..."
            rm -f ${WORKSHOP_DIR}/appworkshop_$GAME_ID.acf
            
            echo -e "\t  Attempting mod update/download via SteamCMD...\n"
            RunSteamCMD $modID
        fi
    done

chown -R pterodactyl:pterodactyl $VOLUME_PATH

echo -e "\n${GREEN}[UPDATE]:${NC} All ${CYAN}Steam Workshop mods${NC} have been checked for updates!"