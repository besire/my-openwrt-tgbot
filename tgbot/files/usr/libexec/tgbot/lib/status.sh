#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=SC2034,SC3043

TGBOT_JSONFILTER_BIN=${TGBOT_JSONFILTER_BIN:-jsonfilter}
TGBOT_UBUS_BIN=${TGBOT_UBUS_BIN:-ubus}
TGBOT_PROC_ROOT=${TGBOT_PROC_ROOT:-/proc}
TGBOT_THERMAL_ROOT=${TGBOT_THERMAL_ROOT:-/sys/class/thermal}
TGBOT_OVERLAY_PATH=${TGBOT_OVERLAY_PATH:-/overlay}
TGBOT_RUNTIME_DIR=${TGBOT_RUNTIME_DIR:-/tmp/tgbot}

_status_json_get() {
	"$TGBOT_JSONFILTER_BIN" -i "$1" -e "$2" 2>/dev/null
}

_status_human_kib() {
	awk -v kib="$1" 'BEGIN {
		if (kib >= 1048576) printf "%.1f GiB", kib / 1048576
		else if (kib >= 1024) printf "%.1f MiB", kib / 1024
		else printf "%d KiB", kib
	}'
}

_status_uptime() {
	awk '{
		seconds = int($1)
		days = int(seconds / 86400); seconds %= 86400
		hours = int(seconds / 3600); seconds %= 3600
		minutes = int(seconds / 60)
		if (days > 0) printf "%dd %02dh %02dm", days, hours, minutes
		else printf "%02dh %02dm", hours, minutes
	}' "$TGBOT_PROC_ROOT/uptime" 2>/dev/null
}

_status_memory() {
	awk '
		$1 == "MemTotal:" { total = $2; found_total = 1 }
		$1 == "MemAvailable:" { available = $2; found_available = 1 }
		END {
			if (found_total && found_available && total > 0)
				printf "%d %d", total - available, total
		}
	' "$TGBOT_PROC_ROOT/meminfo" 2>/dev/null
}

_status_temperature() {
	local zone type value best='' best_priority=0 priority
	for zone in "$TGBOT_THERMAL_ROOT"/thermal_zone*; do
		[ -r "$zone/temp" ] || continue
		IFS= read -r value <"$zone/temp" || continue
		case "$value" in ''|*[!0-9-]*) continue ;; esac
		[ "$value" -ge 0 ] 2>/dev/null || continue
		type=
		[ ! -r "$zone/type" ] || IFS= read -r type <"$zone/type"
		case "$type" in
			*[Cc][Pp][Uu]*|*[Ss][Oo][Cc]*) priority=2 ;;
			*) priority=1 ;;
		esac
		if [ "$priority" -gt "$best_priority" ]; then
			best=$value
			best_priority=$priority
		fi
	done
	[ -n "$best" ] || return 1
	awk -v milli="$best" 'BEGIN { printf "%.1f C", milli / 1000 }'
}

_status_network_line() {
	local network="$1" file up ipv4 ipv6 addresses state
	file=$(mktemp "$TGBOT_RUNTIME_DIR/network.XXXXXX") || return 1
	if ! "$TGBOT_UBUS_BIN" call "network.interface.$network" status >"$file" 2>/dev/null; then
		rm -f "$file"
		printf '%s: 不可用\n' "$network"
		return 0
	fi
	up=$(_status_json_get "$file" '@.up')
	ipv4=$(_status_json_get "$file" "@['ipv4-address'][*].address")
	ipv6=$(_status_json_get "$file" "@['ipv6-address'][*].address")
	addresses=$(printf '%s\n%s\n' "$ipv4" "$ipv6" | awk 'NF { if (out != "") out = out ", "; out = out $0 } END { print out }')
	rm -f "$file"
	case "$up" in true|1) state='在线' ;; *) state='离线' ;; esac
	[ -z "$addresses" ] && printf '%s: %s\n' "$network" "$state" || printf '%s: %s (%s)\n' "$network" "$state" "$addresses"
}

tgbot_collect_status() {
	local board_file hostname model release uptime load memory used total overlay temperature networks='' network
	local overlay_used overlay_rest overlay_total overlay_percent

	board_file=$(mktemp "$TGBOT_RUNTIME_DIR/board.XXXXXX") || return 1
	if "$TGBOT_UBUS_BIN" call system board >"$board_file" 2>/dev/null; then
		hostname=$(_status_json_get "$board_file" '@.hostname')
		model=$(_status_json_get "$board_file" '@.model')
		release=$(_status_json_get "$board_file" '@.release.description')
	fi
	rm -f "$board_file"

	[ -n "$hostname" ] || hostname='不可用'
	[ -n "$model" ] || model='不可用'
	[ -n "$release" ] || release='不可用'
	uptime=$(_status_uptime)
	[ -n "$uptime" ] || uptime='不可用'
	load=$(awk '{ print $1 " / " $2 " / " $3 }' "$TGBOT_PROC_ROOT/loadavg" 2>/dev/null)
	[ -n "$load" ] || load='不可用'
	memory=$(_status_memory)
	if [ -n "$memory" ]; then
		used=${memory%% *}
		total=${memory#* }
		used=$(_status_human_kib "$used")
		total=$(_status_human_kib "$total")
		memory="$used / $total"
	else
		memory='不可用'
	fi

	overlay=$(df -kP "$TGBOT_OVERLAY_PATH" 2>/dev/null | awk 'NR > 1 { used = $3; total = $2; percent = $5 } END { if (total > 0) print used, total, percent }')
	if [ -n "$overlay" ]; then
		overlay_used=${overlay%% *}
		overlay_rest=${overlay#* }
		overlay_total=${overlay_rest%% *}
		overlay_percent=${overlay_rest#* }
		overlay="$(_status_human_kib "$overlay_used") / $(_status_human_kib "$overlay_total") ($overlay_percent)"
	else
		overlay='不可用'
	fi
	temperature=$(_status_temperature 2>/dev/null) || temperature='不可用'

	for network in $TGBOT_STATUS_INTERFACES; do
		networks="${networks}$(_status_network_line "$network")
"
	done
	TGBOT_STATUS_TEXT=$(printf '路由器状态\n设备: %s (%s)\n固件: %s\n运行时间: %s\n负载: %s\n内存: %s\nOverlay: %s\n温度: %s\n%sBot: 运行中' \
		"$hostname" "$model" "$release" "$uptime" "$load" "$memory" "$overlay" "$temperature" "$networks")
}
