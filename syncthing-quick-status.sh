#!/bin/bash

if [ -z "$SYNCTHING_API_KEY" ]; then
	: ${SYNCTHING_CONFIG_FILE:="$HOME/.config/syncthing/config.xml"}
	apikey_regex='^\s+<apikey>([^<]+)</apikey>$'
	apikey_line="$(grep -E "$apikey_regex" "$SYNCTHING_CONFIG_FILE")"
	[[ $apikey_line =~ $apikey_regex ]] &&
		SYNCTHING_API_KEY=${BASH_REMATCH[1]}
fi

if [ -z "$SYNCTHING_API_KEY" ]; then
	echo "No API key in env. Set one of the variables SYNCTHING_API_KEY or SYNCTHING_CONFIG_FILE and try again..."
	exit 1
fi

: ${SYNCTHING_ADDRESS:="localhost:8384"}

COLOR_PURPLE='\e[95m'
COLOR_GRAY='\e[90m'
COLOR_GREEN='\e[92m'
COLOR_BLUE='\e[34m'
COLOR_RED='\e[31m'
COLOR_RESET='\e[0m'

declare -A api_cache=()
function get_api_response() { # $0 api_name
	if [ -z "${api_cache["$1"]}" ]; then
		[ "$DEBUG" ] && echo -e "${COLOR_GRAY}CALLING API: $1${COLOR_RESET}" >&2
		api_cache["$1"]="$(curl --silent -H "X-API-Key: $SYNCTHING_API_KEY" "http://$SYNCTHING_ADDRESS/rest/$1")"
	fi
	RESULT="${api_cache["$1"]}"
	# using stdout and piping direclty to jq would jump over the cache... not sure why :/
}

function jq_arg() {
	echo "$1" | jq -r "$2"
}

function call_jq() { # $0 api_name jq_commands
	get_api_response "$1"
	RESULT="$(jq_arg "$RESULT" "$2")"
}

function get_messages() { # $0 api_name jq_commands message_color_control_code max_age_in_seconds
	call_jq "$1" "$2"
	RESULT="$(jq_arg "$RESULT" '.when + " " + .message')"
	local message_color="$3"
	local max_age="${4:-0}"
	local min_timestamp="$(($(date +%s) - $max_age))"
	local result=
	local formatted_line=
	while IFS= read -r line; do
		[ -z "$line" ] && continue
		when="$(echo "$line" | cut -d' ' -f1)"
		message="$(echo "$line" | cut -d' ' -f2-)"
		timestamp="$(date --date="$when" +%s)"
		when="$(echo "$when" | cut -d'.' -f1)"
		formatted_line="${COLOR_GRAY}$when${COLOR_RESET} ${message_color}$message${COLOR_RESET}"$'\n'
		[ $max_age -gt 0 ] && [ $timestamp -lt $min_timestamp ] &&
			continue
		result+="$formatted_line"
	done <<< "$RESULT"
	[ -z "$result" ] &&
		result="$formatted_line" # take the last log line in any case
	RESULT="${result%$'\n'}"
}

call_jq "system/status" '.myID'
local_device_id="$RESULT"
call_jq "system/config" '.devices | map(select(.deviceID == "'$local_device_id'"))[] | .name'
local_device_name="$RESULT"
echo -e "Local device: $local_device_name ${COLOR_GRAY}($local_device_id)${COLOR_RESET}\n"

echo "Devices:"
call_jq "system/config" '.devices[] | .deviceID'
for device_id in $RESULT; do
	[ "$device_id" == "$local_device_id" ] && continue
	call_jq "system/config" '.devices | map(select(.deviceID == "'$device_id'"))[]'
	device_config="$RESULT"
	device_name="$(jq_arg "$device_config" '.name')"
	echo -n "$device_name: "
	call_jq "system/connections" '.connections["'$device_id'"]'
	device_status="$RESULT"
	status="${COLOR_PURPLE}disconnected${COLOR_RESET}"
	if [ "$(jq_arg "$device_status" '.paused')" == "true" ]; then
		status="${COLOR_GRAY}paused${COLOR_RESET}"
	elif [ "$(jq_arg "$device_status" '.connected')" == "true" ]; then
		status="${COLOR_GREEN}$(jq_arg "$device_status" '.type')${COLOR_RESET}"
	fi
	echo -e "$status ${COLOR_GRAY}($device_id)${COLOR_RESET}"
done

echo -e "\nFolders:"
call_jq "system/config" '.folders[] | .id'
for folder_id in $RESULT; do
	call_jq "system/config" '.folders | map(select(.id == "'"$folder_id"'"))[]'
	folder_config="$RESULT"
	folder_label="$(jq_arg "$folder_config" '.label')"
	if [ "$folder_label" ]; then
		folder_label+=" ${COLOR_GRAY}($folder_id)${COLOR_RESET}"
	else
		folder_label="$folder_id"
	fi
	echo -en "$folder_label: "
	folder_status=
	need_bytes=0
	folder_paused="$(jq_arg "$folder_config" '.paused')"
	[ "$folder_paused" == "true" ] && folder_status="paused"
	if [ -z "$folder_status" ]; then
		call_jq "db/status?folder=$folder_id" '.state'
		folder_status="$RESULT"
		call_jq "db/status?folder=$folder_id" '.needBytes'
		need_bytes="$RESULT"
		need_bytes_formatted=
		[ "$need_bytes" -gt 0 ] &&
			need_bytes_formatted="$(numfmt --to=iec-i --suffix=B "$need_bytes")"
	fi
	case "$folder_status" in
		paused)
			folder_status="${COLOR_GRAY}$folder_status${COLOR_RESET}"
			;;
		idle)
			[ "$need_bytes" -eq 0 ] &&
				folder_status="${COLOR_GREEN}up to date${COLOR_RESET}" ||
				folder_status="${COLOR_RED}out of sync${COLOR_RESET}"
			;;
		scanning|syncing)
			folder_status="${COLOR_BLUE}$folder_status${COLOR_RESET}"
			;;
	esac
	[ "$need_bytes" -gt 0 ] && folder_status+=" ($need_bytes_formatted)"
	echo -e "$folder_status"
done

get_messages "system/log" '.messages[]?' '' 300
echo -e "\nLast log entries:"
echo -e "$RESULT"
get_messages "system/error" '.errors[]?' "$COLOR_RED"
if [ "$RESULT" ]; then
	echo -e "\nERRORS:"
	echo -e "$RESULT"
fi

if [ "$DEBUG" ]; then
	echo -e "\ncached responses:"
	for k in "${!api_cache[@]}"; do
		echo "$k"
	done
fi
