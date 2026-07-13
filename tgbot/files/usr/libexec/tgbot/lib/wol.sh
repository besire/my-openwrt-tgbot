#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=SC2034,SC3043

TGBOT_RUNTIME_DIR=${TGBOT_RUNTIME_DIR:-/tmp/tgbot}
TGBOT_CONFIRM_DIR=${TGBOT_CONFIRM_DIR:-$TGBOT_RUNTIME_DIR/confirm}
TGBOT_ETHERWAKE_BIN=${TGBOT_ETHERWAKE_BIN:-/usr/bin/etherwake}
TGBOT_PING_BIN=${TGBOT_PING_BIN:-ping}
TGBOT_SLEEP_BIN=${TGBOT_SLEEP_BIN:-sleep}

wol_reset_confirmation_state() {
	local file
	mkdir -p "$TGBOT_CONFIRM_DIR" || return 1
	chmod 700 "$TGBOT_CONFIRM_DIR" 2>/dev/null || true
	for file in "$TGBOT_CONFIRM_DIR"/*; do
		[ ! -f "$file" ] || rm -f "$file" || return 1
	done
	return 0
}

_wol_add_target_button() {
	local section="$1"
	if ! tgbot_load_device "$section" || ! tgbot_validate_loaded_device; then
		return
	fi
	json_add_array ''
	json_add_object ''
	json_add_string text "$TGBOT_DEVICE_NAME"
	json_add_string callback_data "wol_select:$section"
	json_close_object
	json_close_array
	TGBOT_WOL_TARGET_COUNT=$((TGBOT_WOL_TARGET_COUNT + 1))
}

wol_send_target_keyboard() {
	local chat_id="$1" payload rc=0
	payload=$(telegram_new_payload_file) || return 1
	TGBOT_WOL_TARGET_COUNT=0

	json_init
	json_add_string chat_id "$chat_id"
	json_add_string text '请选择需要唤醒的设备：'
	json_add_object reply_markup
	json_add_array inline_keyboard
	config_foreach _wol_add_target_button device
	json_close_array
	json_close_object
	json_dump >"$payload"

	if [ "$TGBOT_WOL_TARGET_COUNT" -eq 0 ]; then
		rm -f "$payload"
		telegram_send_text "$chat_id" '没有可用的 WOL 设备，请先在 LuCI 中配置。'
		return
	fi
	telegram_submit_payload sendMessage "$payload" || rc=1
	rm -f "$payload"
	return "$rc"
}

wol_new_nonce() {
	local nonce attempts=0
	while [ "$attempts" -lt 5 ]; do
		nonce=$(od -An -N12 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
		case "$nonce" in
			????????????????????????)
				[ -e "$TGBOT_CONFIRM_DIR/$nonce" ] || {
					printf '%s\n' "$nonce"
					return 0
				}
				;;
		esac
		attempts=$((attempts + 1))
	done
	return 1
}

wol_create_confirmation() {
	local user_id="$1" chat_id="$2" section="$3" nonce expires temporary
	nonce=$(wol_new_nonce) || return 1
	expires=$(($(date +%s) + 60))
	temporary="$TGBOT_CONFIRM_DIR/.$nonce.$$"
	(
		umask 077
		printf '%s\n%s\n%s\n%s\n' "$user_id" "$chat_id" "$section" "$expires" >"$temporary"
	) || return 1
	mv "$temporary" "$TGBOT_CONFIRM_DIR/$nonce" || {
		rm -f "$temporary"
		return 1
	}
	printf '%s\n' "$nonce"
}

wol_consume_confirmation() {
	local nonce="$1" user_id="$2" chat_id="$3" source claimed
	local saved_user saved_chat saved_section expires now
	case "$nonce" in
		????????????????????????) ;;
		*) return 1 ;;
	esac
	case "$nonce" in *[!0-9a-f]*) return 1 ;; esac

	source="$TGBOT_CONFIRM_DIR/$nonce"
	claimed="$TGBOT_CONFIRM_DIR/.$nonce.claimed.$$"
	mv "$source" "$claimed" 2>/dev/null || return 1
	{
		IFS= read -r saved_user
		IFS= read -r saved_chat
		IFS= read -r saved_section
		IFS= read -r expires
	} <"$claimed"
	rm -f "$claimed"

	now=$(date +%s)
	[ "$saved_user" = "$user_id" ] || return 1
	[ "$saved_chat" = "$chat_id" ] || return 1
	tgbot_is_section_id "$saved_section" || return 1
	tgbot_is_uint_in_range "$expires" 1 2147483647 || return 1
	[ "$now" -le "$expires" ] || return 1
	TGBOT_CONFIRM_SECTION=$saved_section
}

wol_send_confirmation() {
	local chat_id="$1" user_id="$2" section="$3" nonce payload rc=0
	if ! tgbot_load_device "$section" || ! tgbot_validate_loaded_device; then
		telegram_send_text "$chat_id" '该设备配置无效或已禁用。'
		return 1
	fi
	nonce=$(wol_create_confirmation "$user_id" "$chat_id" "$section") || {
		telegram_send_text "$chat_id" '无法创建确认操作，请稍后重试。'
		return 1
	}
	payload=$(telegram_new_payload_file) || return 1

	json_init
	json_add_string chat_id "$chat_id"
	json_add_string text "确认唤醒 $TGBOT_DEVICE_NAME？"
	json_add_object reply_markup
	json_add_array inline_keyboard
	json_add_array ''
	json_add_object ''
	json_add_string text '确认'
	json_add_string callback_data "wol_confirm:$nonce"
	json_close_object
	json_add_object ''
	json_add_string text '取消'
	json_add_string callback_data "wol_cancel:$nonce"
	json_close_object
	json_close_array
	json_close_array
	json_close_object
	json_dump >"$payload"

	telegram_submit_payload sendMessage "$payload" || rc=1
	rm -f "$payload"
	return "$rc"
}

wol_check_reachable() {
	local ip="$1" attempt=1
	"$TGBOT_SLEEP_BIN" "$TGBOT_WAKE_CHECK_DELAY"
	while [ "$attempt" -le "$TGBOT_WAKE_CHECK_ATTEMPTS" ]; do
		"$TGBOT_PING_BIN" -c 1 -W 1 "$ip" >/dev/null 2>&1 && return 0
		[ "$attempt" -eq "$TGBOT_WAKE_CHECK_ATTEMPTS" ] || "$TGBOT_SLEEP_BIN" "$TGBOT_WAKE_CHECK_INTERVAL"
		attempt=$((attempt + 1))
	done
	return 1
}

wol_execute_confirmed() {
	local chat_id="$1" section="$2" name check_ip
	if ! tgbot_load_device "$section" || ! tgbot_validate_loaded_device; then
		telegram_send_text "$chat_id" '设备配置已变化，未发送唤醒包。'
		return 1
	fi
	name=$TGBOT_DEVICE_NAME
	check_ip=$TGBOT_DEVICE_CHECK_IP

	if ! "$TGBOT_ETHERWAKE_BIN" -i "$TGBOT_DEVICE_INTERFACE" "$TGBOT_DEVICE_MAC" >/dev/null 2>&1; then
		telegram_send_text "$chat_id" "唤醒 $name 失败：etherwake 执行错误。"
		return 1
	fi
	telegram_send_text "$chat_id" "已向 $name 发送魔术包。"
	[ -n "$check_ip" ] || return 0

	if wol_check_reachable "$check_ip"; then
		telegram_send_text "$chat_id" "$name 已检测为在线。"
	else
		telegram_send_text "$chat_id" "魔术包已发送，但暂未检测到 $name 在线。"
	fi
}

wol_handle_callback() {
	local callback_id="$1" data="$2" user_id="$3" chat_id="$4" value
	case "$data" in
		wol_select:*)
			value=${data#wol_select:}
			telegram_answer_callback "$callback_id" '请选择确认或取消。' || true
			wol_send_confirmation "$chat_id" "$user_id" "$value"
			;;
		wol_confirm:*)
			value=${data#wol_confirm:}
			if wol_consume_confirmation "$value" "$user_id" "$chat_id"; then
				telegram_answer_callback "$callback_id" '正在发送唤醒包。' || true
				wol_execute_confirmed "$chat_id" "$TGBOT_CONFIRM_SECTION"
			else
				telegram_answer_callback "$callback_id" '确认已失效。' || true
			fi
			;;
		wol_cancel:*)
			value=${data#wol_cancel:}
			if wol_consume_confirmation "$value" "$user_id" "$chat_id"; then
				telegram_answer_callback "$callback_id" '已取消。' || true
				telegram_send_text "$chat_id" '已取消唤醒操作。'
			else
				telegram_answer_callback "$callback_id" '确认已失效。' || true
			fi
			;;
		*) telegram_answer_callback "$callback_id" '不支持或已失效的操作。' || true ;;
	esac
}
