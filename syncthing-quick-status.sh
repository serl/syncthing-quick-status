#!/usr/bin/env bash

if ((BASH_VERSINFO[0] < 4)); then
	echo "This script needs at least bash 4."
	missing_deps=1
fi
for dep in curl jq; do
	if ! command -v $dep &>/dev/null; then
		echo "$dep is required but not found."
		missing_deps=1
	fi
done
[[ $missing_deps ]] &&
	exit 1

if [[ -z $SYNCTHING_API_KEY ]]; then
	SYNCTHING_DEFAULT_CONFIG_FILE="$HOME/.config/syncthing/config.xml"
	if [[ ! -r "$SYNCTHING_DEFAULT_CONFIG_FILE" ]]; then
		SYNCTHING_DEFAULT_CONFIG_FILE="$HOME/.local/state/syncthing/config.xml"
 	fi
	if [[ $(uname) = Darwin ]]; then
		SYNCTHING_DEFAULT_CONFIG_FILE="$HOME/Library/Application Support/Syncthing/config.xml"
	fi
	: "${SYNCTHING_CONFIG_FILE:="$SYNCTHING_DEFAULT_CONFIG_FILE"}"
	apikey_regex='<apikey>([^<]+)</apikey>'
	apikey_line="$(grep -E "$apikey_regex" "$SYNCTHING_CONFIG_FILE")"
	[[ $apikey_line =~ $apikey_regex ]] &&
		SYNCTHING_API_KEY=${BASH_REMATCH[1]}
fi

if [[ -z $SYNCTHING_API_KEY ]]; then
	echo "No API key in env. Set one of the variables SYNCTHING_API_KEY or SYNCTHING_CONFIG_FILE and try again..."
	exit 1
fi

: "${SYNCTHING_ADDRESS:="localhost:8384"}"

COLOR_PURPLE='\e[95m'
COLOR_GRAY='\e[90m'
COLOR_GREEN='\e[92m'
COLOR_BLUE='\e[34m'
COLOR_RED='\e[31m'
COLOR_RESET='\e[0m'

RECENT_CHANGES_LIMIT=5
LOG_ENTRIES_LIMIT=15
LOG_MAX_AGE=300 # seconds

declare -A api_cache=()
function get_api_response() { # $0 api_name
	if [[ -z ${api_cache["$1"]} ]]; then
		[[ $DEBUG ]] && echo -e "${COLOR_GRAY}CALLING API: $1${COLOR_RESET}" >&2
		api_cache["$1"]="$(curl --silent --insecure -L -H "X-API-Key: $SYNCTHING_API_KEY" "http://$SYNCTHING_ADDRESS/rest/$1")"
	fi
	RESULT="${api_cache["$1"]}"
	# using stdout and piping directly to jq would jump over the cache... not sure why :/
	[[ $RESULT == "CSRF Error" ]] && return 1
	return 0
}

function jq_arg() {
	echo "$1" | jq -r "$2"
}

function call_jq() { # $0 api_name jq_commands
	get_api_response "$1" &&
		RESULT="$(jq_arg "$RESULT" "$2")" &&
		mapfile -t RESULT_ARRAY <<< "$RESULT"
}

function format_time() {
	echo "${COLOR_GRAY}$(echo "$1" | cut -d'.' -f1)${COLOR_RESET}"
}

function time_to_epoch() {
	if date --version &>/dev/null; then
		# GNU date
		date --date="$1" +%s
	else
		# macos date
		date -jf '%Y-%m-%dT%H:%M:%S' "$(echo "$1" | cut -d'.' -f1)" +%s
	fi
}

function get_messages() { # $0 api_name jq_commands message_color_control_code max_age_in_seconds
	call_jq "$1" "$2"
	RESULT="$(jq_arg "$RESULT" '.when + " " + .message' | tail -n "$LOG_ENTRIES_LIMIT")"
	local message_color="$3"
	local max_age="${4:-0}"
	local min_timestamp="$(($(date +%s) - max_age))"
	local result=
	local formatted_line=
	while IFS= read -r line; do
		[[ -z $line ]] && continue
		when="$(echo "$line" | cut -d' ' -f1)"
		message="$(echo "$line" | cut -d' ' -f2-)"
		timestamp="$(time_to_epoch "$when")"
		formatted_line="$(format_time "$when") ${message_color}$message${COLOR_RESET}"$'\n'
		[[ $max_age -gt 0 ]] && [[ $timestamp -lt $min_timestamp ]] &&
			continue
		result+="$formatted_line"
	done <<< "$RESULT"
	[[ -z $result ]] &&
		result="$formatted_line" # take the last log line in any case
	RESULT="${result%$'\n'}"
}

[[ $1 == -v ]] && VERBOSE=true

if ! call_jq "system/status" '.myID'; then
	echo "Error from Syncthing API: $RESULT"
	echo "You should probably check and change the variables SYNCTHING_API_KEY or SYNCTHING_CONFIG_FILE."
	exit 1
elif [[ -z $RESULT ]]; then
	echo "Empty response from Syncthing API."
	echo "You should probably check and change the variables SYNCTHING_ADDRESS, SYNCTHING_API_KEY or SYNCTHING_CONFIG_FILE."
	exit 1
fi
local_device_id="$RESULT"
call_jq "system/config" '.devices | map(select(.deviceID == "'"$local_device_id"'"))[] | .name'
local_device_name="$RESULT"
echo -n "Local device: $local_device_name"
[[ $VERBOSE ]] && echo -en " ${COLOR_GRAY}($local_device_id)${COLOR_RESET}"
echo $'\n'

echo "Devices:"
call_jq "system/config" '.devices[] | .deviceID'
for device_id in $RESULT; do
	[[ $device_id == "$local_device_id" ]] && continue
	call_jq "system/config" '.devices | map(select(.deviceID == "'"$device_id"'"))[]'
	device_config="$RESULT"
	device_name="$(jq_arg "$device_config" '.name')"
	echo -n "$device_name: "
	call_jq "system/connections" '.connections["'"$device_id"'"]'
	device_status="$RESULT"
	status="${COLOR_PURPLE}disconnected${COLOR_RESET}"
	if [ "$(jq_arg "$device_status" '.paused')" == "true" ]; then
		status="${COLOR_GRAY}paused${COLOR_RESET}"
	elif [ "$(jq_arg "$device_status" '.connected')" == "true" ]; then
		status="${COLOR_GREEN}$(jq_arg "$device_status" '.type')${COLOR_RESET}"
	fi
	echo -en "$status"
	[[ $VERBOSE ]] && echo -en " ${COLOR_GRAY}($device_id)${COLOR_RESET}"
	echo
done

echo -e "\nFolders:"
call_jq "system/config" '.folders[] | .id'
for folder_id in "${RESULT_ARRAY[@]}"; do
	call_jq "system/config" '.folders | map(select(.id == "'"$folder_id"'"))[]'
	folder_config="$RESULT"
	folder_label="$(jq_arg "$folder_config" '.label')"
	if [ "$folder_label" ]; then
		[[ $VERBOSE ]] && folder_label+=" ${COLOR_GRAY}($folder_id)${COLOR_RESET}"
	else
		folder_label="$folder_id"
	fi
	echo -en "$folder_label: "
	folder_status=
	need_bytes=0
	folder_paused="$(jq_arg "$folder_config" '.paused')"
	[[ $folder_paused == true ]] && folder_status="paused"
	if [[ -z $folder_status ]]; then
		call_jq "db/status?folder=${folder_id// /+}" '.state'
		folder_status="$RESULT"
		call_jq "db/status?folder=${folder_id// /+}" '.errors'
		folder_errors="$RESULT"
		call_jq "db/status?folder=${folder_id// /+}" '.needBytes'
		need_bytes="$RESULT"
	fi
	case "$folder_status" in
		paused)
			folder_status="${COLOR_GRAY}$folder_status${COLOR_RESET}"
			;;
		idle)
			if [[ $folder_errors -gt 0 ]]; then
				folder_status="${COLOR_RED}$folder_errors failed items${COLOR_RESET}"
			elif [[ $need_bytes -gt 0 ]]; then
				need_bytes_formatted="$(numfmt --to=iec-i --suffix=B "$need_bytes")"
				folder_status="${COLOR_RED}out of sync${COLOR_RESET} ($need_bytes_formatted)"
			else
				folder_status="${COLOR_GREEN}up to date${COLOR_RESET}"
			fi
			;;
		scanning|syncing)
			folder_status="${COLOR_BLUE}$folder_status${COLOR_RESET}"
			;;
	esac
	echo -e "$folder_status"
done

echo -e "\nRecent changes:"
call_jq "events/disk?limit=$RECENT_CHANGES_LIMIT&timeout=1" '.[] | .id'
for event_id in $RESULT; do
	call_jq "events/disk?limit=$RECENT_CHANGES_LIMIT&timeout=1" '. | map(select(.id == '"$event_id"'))[]'
	event="$RESULT"

	when="$(jq_arg "$event" '.time')"
	path="$(jq_arg "$event" '.data.path')"

	folder_id="$(jq_arg "$event" '.data.folderID')"
	call_jq "system/config" '.folders | map(select(.id == "'"$folder_id"'"))[].label'
	folder_label="${RESULT:-$folder_id}"

	action="$(jq_arg "$event" '.data.action')"
	action_color='?'
	case "$action" in
		added) action_color=${COLOR_GREEN}+ ;;
		deleted) action_color=${COLOR_RED}- ;;
		modified) action_color=${COLOR_BLUE}\# ;;
	esac

	device_id_prefix="$(jq_arg "$event" '.data.modifiedBy')"
	call_jq "system/config" '.devices | map(select(.deviceID | startswith("'"$device_id_prefix"'")))[].name'
	device_name="${RESULT:-$device_id_prefix}"

	echo -e "$(format_time "$when") ${COLOR_GRAY}$device_name${COLOR_RESET} $folder_label ${action_color}$path${COLOR_RESET}"
done

if [[ $VERBOSE ]]; then
	get_messages "system/log" '.messages[]?' '' "$LOG_MAX_AGE"
	echo -e "\nLast log entries:"
	echo -e "$RESULT"
fi
get_messages "system/error" '.errors[]?' "$COLOR_RED"
if [[ $RESULT ]]; then
	echo -e "\nERRORS:"
	echo -e "$RESULT"
fi

if [[ $DEBUG ]]; then
	echo -e "\ncached responses:"
	for k in "${!api_cache[@]}"; do
		echo "$k"
	done
fi
