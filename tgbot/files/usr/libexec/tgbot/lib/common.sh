#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=SC2034,SC2153,SC3043

TGBOT_FUNCTIONS_SH=${TGBOT_FUNCTIONS_SH:-/lib/functions.sh}
TGBOT_SYS_CLASS_NET=${TGBOT_SYS_CLASS_NET:-/sys/class/net}
TGBOT_LOG_TAG=${TGBOT_LOG_TAG:-tgbot}
TGBOT_PING_BIN=${TGBOT_PING_BIN:-ping}

if ! command -v config_load >/dev/null 2>&1; then
	# shellcheck source=/dev/null
	. "$TGBOT_FUNCTIONS_SH"
fi

tgbot_log() {
	local level="$1"
	shift
	logger -t "$TGBOT_LOG_TAG" -p "daemon.$level" "$*"
}

tgbot_has_forbidden_whitespace() {
	LC_ALL=C printf '%s' "$1" | grep -q '[[:space:][:cntrl:]]'
}

tgbot_is_uint_in_range() {
	local value="$1" min="$2" max="$3"
	case "$value" in
		''|*[!0-9]*) return 1 ;;
	esac
	[ "$value" -ge "$min" ] 2>/dev/null && [ "$value" -le "$max" ] 2>/dev/null
}

tgbot_is_telegram_id() {
	case "$1" in
		''|0*|*[!0-9]*) return 1 ;;
	esac
	[ "${#1}" -le 20 ]
}

tgbot_is_token() {
	local token="$1"
	[ "${#token}" -le 256 ] || return 1
	tgbot_has_forbidden_whitespace "$token" && return 1
	printf '%s\n' "$token" | grep -Eq '^[0-9]+:[A-Za-z0-9_-]+$'
}

tgbot_is_https_url() {
	local url="$1" rest authority host port

	[ "${#url}" -le 512 ] || return 1
	tgbot_has_forbidden_whitespace "$url" && return 1
	case "$url" in
		https://*) ;;
		*) return 1 ;;
	esac
	case "$url" in
		*'?'*|*'#'*|*'"'*|*\\*) return 1 ;;
	esac

	rest=${url#https://}
	authority=${rest%%/*}
	[ -n "$authority" ] || return 1
	case "$authority" in
		*@*|:*|*'['*|*']'*) return 1 ;;
	esac
	host=$authority
	case "$authority" in
		*:*)
			host=${authority%:*}
			port=${authority##*:}
			case "$host" in *:*) return 1 ;; esac
			tgbot_is_uint_in_range "$port" 1 65535 || return 1
			;;
	esac
	[ "${#host}" -le 253 ] || return 1
	printf '%s\n' "$host" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' || return 1
	case "$host" in *'..'*|*'.-'*|*'-.'*) return 1 ;; esac
	return 0
}

tgbot_normalize_base_url() {
	local url="$1"
	while [ "${url%/}" != "$url" ]; do
		url=${url%/}
	done
	printf '%s\n' "$url"
}

tgbot_is_mac() {
	printf '%s\n' "$1" | grep -Eq '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'
}

tgbot_is_interface_name() {
	local name="$1"
	[ "${#name}" -le 15 ] || return 1
	printf '%s\n' "$name" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
}

tgbot_is_network_name() {
	local name="$1"
	[ "${#name}" -le 64 ] || return 1
	printf '%s\n' "$name" | grep -Eq '^[A-Za-z0-9_]+$'
}

tgbot_is_section_id() {
	local name="$1"
	[ "${#name}" -le 64 ] || return 1
	printf '%s\n' "$name" | grep -Eq '^[A-Za-z0-9_]+$'
}

tgbot_is_ipv4() {
	printf '%s\n' "$1" | awk -F. '
		NF != 4 { invalid = 1 }
		{
			for (i = 1; i <= 4; i++) {
				if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255)
					invalid = 1
			}
		}
		END { exit invalid }
	'
}

tgbot_is_device_name() {
	local name="$1" size
	[ -n "$name" ] || return 1
	LC_ALL=C printf '%s' "$name" | grep -q '[[:cntrl:]]' && return 1
	size=$(LC_ALL=C printf '%s' "$name" | wc -c)
	[ "$size" -le 48 ]
}

tgbot_load_device() {
	local section="$1"
	tgbot_is_section_id "$section" || return 1

	TGBOT_DEVICE_SECTION=$section
	config_get_bool TGBOT_DEVICE_ENABLED "$section" enabled 1
	config_get TGBOT_DEVICE_NAME "$section" name ''
	config_get TGBOT_DEVICE_MAC "$section" mac ''
	config_get TGBOT_DEVICE_INTERFACE "$section" interface ''
	config_get TGBOT_DEVICE_CHECK_IP "$section" check_ip ''
}

tgbot_validate_loaded_device() {
	TGBOT_DEVICE_ERROR=
	[ "$TGBOT_DEVICE_ENABLED" -eq 1 ] || TGBOT_DEVICE_ERROR='device is disabled'
	[ -n "$TGBOT_DEVICE_ERROR" ] || tgbot_is_device_name "$TGBOT_DEVICE_NAME" || TGBOT_DEVICE_ERROR='invalid device name'
	[ -n "$TGBOT_DEVICE_ERROR" ] || tgbot_is_mac "$TGBOT_DEVICE_MAC" || TGBOT_DEVICE_ERROR='invalid MAC address'
	[ -n "$TGBOT_DEVICE_ERROR" ] || tgbot_is_interface_name "$TGBOT_DEVICE_INTERFACE" || TGBOT_DEVICE_ERROR='invalid interface'
	if [ -z "$TGBOT_DEVICE_ERROR" ] && [ ! -d "$TGBOT_SYS_CLASS_NET/$TGBOT_DEVICE_INTERFACE" ]; then
		TGBOT_DEVICE_ERROR='interface does not exist'
	fi
	if [ -z "$TGBOT_DEVICE_ERROR" ] && [ -n "$TGBOT_DEVICE_CHECK_IP" ] && ! tgbot_is_ipv4 "$TGBOT_DEVICE_CHECK_IP"; then
		TGBOT_DEVICE_ERROR='invalid check IP'
	fi
	[ -z "$TGBOT_DEVICE_ERROR" ]
}

_tgbot_append_admin() {
	local value="$1"
	TGBOT_ADMIN_IDS="${TGBOT_ADMIN_IDS}${TGBOT_ADMIN_IDS:+ }$value"
}

_tgbot_append_status_interface() {
	local value="$1"
	TGBOT_STATUS_INTERFACES="${TGBOT_STATUS_INTERFACES}${TGBOT_STATUS_INTERFACES:+ }$value"
}

tgbot_load_config() {
	TGBOT_ENABLED=0
	TGBOT_TOKEN=
	TGBOT_API_BASE_URL=https://api.telegram.org
	TGBOT_ADMIN_IDS=
	TGBOT_STATUS_INTERFACES=
	TGBOT_POLL_TIMEOUT=50
	TGBOT_WAKE_CHECK_DELAY=5
	TGBOT_WAKE_CHECK_ATTEMPTS=6
	TGBOT_WAKE_CHECK_INTERVAL=5

	config_load tgbot || return 1
	config_get_bool TGBOT_ENABLED main enabled 0
	config_get TGBOT_TOKEN main token ''
	config_get TGBOT_API_BASE_URL main api_base_url 'https://api.telegram.org'
	config_get TGBOT_POLL_TIMEOUT main poll_timeout 50
	config_get TGBOT_WAKE_CHECK_DELAY main wake_check_delay 5
	config_get TGBOT_WAKE_CHECK_ATTEMPTS main wake_check_attempts 6
	config_get TGBOT_WAKE_CHECK_INTERVAL main wake_check_interval 5
	config_list_foreach main admin_id _tgbot_append_admin
	config_list_foreach main status_interface _tgbot_append_status_interface
	[ -n "$TGBOT_STATUS_INTERFACES" ] || TGBOT_STATUS_INTERFACES='wan wan6'
	TGBOT_API_BASE_URL=$(tgbot_normalize_base_url "$TGBOT_API_BASE_URL")
}

tgbot_is_admin() {
	local wanted="$1" admin
	for admin in $TGBOT_ADMIN_IDS; do
		[ "$admin" = "$wanted" ] && return 0
	done
	return 1
}

TGBOT_VALIDATION_ERRORS=
TGBOT_DEVICE_NAMES=

tgbot_validation_error() {
	TGBOT_VALIDATION_ERRORS="${TGBOT_VALIDATION_ERRORS}${TGBOT_VALIDATION_ERRORS:+
}$1"
}

_tgbot_name_seen() {
	printf '%s\n' "$TGBOT_DEVICE_NAMES" | grep -F -x -q -e "$1"
}

_tgbot_validate_device() {
	local section="$1"

	if ! tgbot_load_device "$section"; then
		tgbot_validation_error "device has an invalid section ID: $section"
		return
	fi
	[ "$TGBOT_DEVICE_ENABLED" -eq 1 ] || return 0
	if ! tgbot_validate_loaded_device; then
		tgbot_validation_error "device $section: $TGBOT_DEVICE_ERROR"
	fi
	if tgbot_is_device_name "$TGBOT_DEVICE_NAME"; then
		_tgbot_name_seen "$TGBOT_DEVICE_NAME" && tgbot_validation_error "device name is duplicated: $TGBOT_DEVICE_NAME"
		TGBOT_DEVICE_NAMES="${TGBOT_DEVICE_NAMES}${TGBOT_DEVICE_NAMES:+
}$TGBOT_DEVICE_NAME"
	fi
}

tgbot_validate_config() {
	local mode="${1:-normal}" admin network seen_admin=

	TGBOT_VALIDATION_ERRORS=
	TGBOT_DEVICE_NAMES=

	if [ "$mode" = strict ] || [ "$TGBOT_ENABLED" -eq 1 ]; then
		tgbot_is_token "$TGBOT_TOKEN" || tgbot_validation_error 'bot token is missing or invalid'
		[ -n "$TGBOT_ADMIN_IDS" ] || tgbot_validation_error 'at least one administrator ID is required'
	elif [ -n "$TGBOT_TOKEN" ]; then
		tgbot_is_token "$TGBOT_TOKEN" || tgbot_validation_error 'bot token is invalid'
	fi

	tgbot_is_https_url "$TGBOT_API_BASE_URL" || tgbot_validation_error 'Telegram API base URL must be a valid HTTPS URL'
	tgbot_is_uint_in_range "$TGBOT_POLL_TIMEOUT" 1 50 || tgbot_validation_error 'poll timeout must be between 1 and 50'
	tgbot_is_uint_in_range "$TGBOT_WAKE_CHECK_DELAY" 0 120 || tgbot_validation_error 'wake check delay must be between 0 and 120'
	tgbot_is_uint_in_range "$TGBOT_WAKE_CHECK_ATTEMPTS" 1 20 || tgbot_validation_error 'wake check attempts must be between 1 and 20'
	tgbot_is_uint_in_range "$TGBOT_WAKE_CHECK_INTERVAL" 1 60 || tgbot_validation_error 'wake check interval must be between 1 and 60'

	for admin in $TGBOT_ADMIN_IDS; do
		tgbot_is_telegram_id "$admin" || tgbot_validation_error "invalid administrator ID: $admin"
		case " $seen_admin " in
			*" $admin "*) tgbot_validation_error "administrator ID is duplicated: $admin" ;;
			*) seen_admin="${seen_admin}${seen_admin:+ }$admin" ;;
		esac
	done

	for network in $TGBOT_STATUS_INTERFACES; do
		tgbot_is_network_name "$network" || tgbot_validation_error "invalid status interface: $network"
	done

	config_foreach _tgbot_validate_device device
	[ -z "$TGBOT_VALIDATION_ERRORS" ]
}

tgbot_print_validation_errors() {
	[ -n "$TGBOT_VALIDATION_ERRORS" ] || return 0
	printf '%s\n' "$TGBOT_VALIDATION_ERRORS"
}
