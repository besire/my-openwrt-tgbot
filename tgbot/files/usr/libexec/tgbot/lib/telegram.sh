#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=SC2034,SC3043

TGBOT_CURL_BIN=${TGBOT_CURL_BIN:-curl}
TGBOT_JSONFILTER_BIN=${TGBOT_JSONFILTER_BIN:-jsonfilter}
TGBOT_JSHN_SH=${TGBOT_JSHN_SH:-/usr/share/libubox/jshn.sh}
TGBOT_RUNTIME_DIR=${TGBOT_RUNTIME_DIR:-/tmp/tgbot}

if ! command -v json_init >/dev/null 2>&1; then
	# shellcheck source=/dev/null
	. "$TGBOT_JSHN_SH"
fi

telegram_json_get() {
	local file="$1" expression="$2"
	"$TGBOT_JSONFILTER_BIN" -i "$file" -e "$expression" 2>/dev/null
}

telegram_method_allowed() {
	case "$1" in
		getMe|getUpdates|sendMessage|answerCallbackQuery) return 0 ;;
		*) return 1 ;;
	esac
}

_telegram_write_curl_config() {
	local url="$1" payload="$2" response="$3" max_time="$4"
	printf '%s\n' \
		'silent' \
		'show-error' \
		'proto = "=https"' \
		'request = "POST"' \
		'connect-timeout = "10"' \
		"max-time = \"$max_time\"" \
		'header = "Content-Type: application/json"' \
		"data-binary = \"@$payload\"" \
		"url = \"$url\"" \
		"output = \"$response\"" \
		'write-out = "%{http_code}"'
}

telegram_api_call() {
	local method="$1" payload="$2" response="$3" max_time="${4:-20}"
	local url http_code ok

	TGBOT_TELEGRAM_ERROR=
	telegram_method_allowed "$method" || {
		TGBOT_TELEGRAM_ERROR='disallowed Telegram method'
		return 1
	}
	[ -r "$payload" ] || {
		TGBOT_TELEGRAM_ERROR='request payload is unavailable'
		return 1
	}

	url="$TGBOT_API_BASE_URL/bot$TGBOT_TOKEN/$method"
	: >"$response" || {
		TGBOT_TELEGRAM_ERROR='unable to create response file'
		return 1
	}
	chmod 600 "$response" 2>/dev/null || true

	if ! http_code=$(
		_telegram_write_curl_config "$url" "$payload" "$response" "$max_time" |
			"$TGBOT_CURL_BIN" --config - 2>/dev/null
	); then
		TGBOT_TELEGRAM_ERROR='Telegram transport failed'
		return 1
	fi
	[ "$http_code" = 200 ] || {
		TGBOT_TELEGRAM_ERROR="Telegram returned HTTP $http_code"
		return 1
	}

	ok=$(telegram_json_get "$response" '@.ok')
	case "$ok" in
		true|1) return 0 ;;
		*)
			TGBOT_TELEGRAM_ERROR='Telegram returned an API error'
			return 1
			;;
	esac
}

telegram_new_payload_file() {
	mktemp "$TGBOT_RUNTIME_DIR/payload.XXXXXX"
}

telegram_new_response_file() {
	mktemp "$TGBOT_RUNTIME_DIR/response.XXXXXX"
}

telegram_write_empty_payload() {
	local file="$1"
	json_init
	json_dump >"$file"
}

telegram_write_poll_payload() {
	local file="$1" offset="$2" timeout="$3"
	json_init
	json_add_int offset "$offset"
	json_add_int limit 1
	json_add_int timeout "$timeout"
	json_add_array allowed_updates
	json_add_string '' message
	json_add_string '' callback_query
	json_close_array
	json_dump >"$file"
}

telegram_write_text_payload() {
	local file="$1" chat_id="$2" message="$3"
	json_init
	json_add_string chat_id "$chat_id"
	json_add_string text "$message"
	json_dump >"$file"
}

telegram_write_callback_answer_payload() {
	local file="$1" callback_id="$2" message="${3:-}"
	json_init
	json_add_string callback_query_id "$callback_id"
	[ -z "$message" ] || json_add_string text "$message"
	json_dump >"$file"
}

telegram_call_with_writer() {
	local method="$1" writer="$2"
	shift 2
	local payload response rc=0

	payload=$(telegram_new_payload_file) || return 1
	response=$(telegram_new_response_file) || {
		rm -f "$payload"
		return 1
	}
	"$writer" "$payload" "$@" || rc=1
	if [ "$rc" -eq 0 ]; then
		telegram_api_call "$method" "$payload" "$response" || rc=1
	fi
	rm -f "$payload" "$response"
	return "$rc"
}

telegram_submit_payload() {
	local method="$1" payload="$2" response rc=0
	response=$(telegram_new_response_file) || return 1
	telegram_api_call "$method" "$payload" "$response" || rc=1
	rm -f "$response"
	return "$rc"
}

telegram_send_text() {
	telegram_call_with_writer sendMessage telegram_write_text_payload "$1" "$2"
}

telegram_answer_callback() {
	telegram_call_with_writer answerCallbackQuery telegram_write_callback_answer_payload "$1" "${2:-}"
}

telegram_test_api() {
	local payload response rc=0
	payload=$(telegram_new_payload_file) || return 1
	response=$(telegram_new_response_file) || {
		rm -f "$payload"
		return 1
	}
	telegram_write_empty_payload "$payload"
	if telegram_api_call getMe "$payload" "$response"; then
		TGBOT_BOT_USERNAME=$(telegram_json_get "$response" '@.result.username')
	else
		rc=1
	fi
	rm -f "$payload" "$response"
	return "$rc"
}

telegram_poll() {
	local offset="$1" timeout="$2" response="$3" payload rc=0
	payload=$(telegram_new_payload_file) || return 1
	telegram_write_poll_payload "$payload" "$offset" "$timeout"
	telegram_api_call getUpdates "$payload" "$response" "$((timeout + 15))" || rc=1
	rm -f "$payload"
	return "$rc"
}

telegram_decode_update() {
	local response="$1"

	TGBOT_UPDATE_ID=$(telegram_json_get "$response" '@.result[0].update_id')
	case "$TGBOT_UPDATE_ID" in
		''|*[!0-9]*) return 2 ;;
	esac

	TGBOT_CALLBACK_ID=$(telegram_json_get "$response" '@.result[0].callback_query.id')
	if [ -n "$TGBOT_CALLBACK_ID" ]; then
		TGBOT_UPDATE_KIND=callback
		TGBOT_USER_ID=$(telegram_json_get "$response" '@.result[0].callback_query.from.id')
		TGBOT_CHAT_ID=$(telegram_json_get "$response" '@.result[0].callback_query.message.chat.id')
		TGBOT_CHAT_TYPE=$(telegram_json_get "$response" '@.result[0].callback_query.message.chat.type')
		TGBOT_CALLBACK_DATA=$(telegram_json_get "$response" '@.result[0].callback_query.data')
		TGBOT_MESSAGE_TEXT=
	else
		TGBOT_UPDATE_KIND=message
		TGBOT_USER_ID=$(telegram_json_get "$response" '@.result[0].message.from.id')
		TGBOT_CHAT_ID=$(telegram_json_get "$response" '@.result[0].message.chat.id')
		TGBOT_CHAT_TYPE=$(telegram_json_get "$response" '@.result[0].message.chat.type')
		TGBOT_MESSAGE_TEXT=$(telegram_json_get "$response" '@.result[0].message.text')
		TGBOT_CALLBACK_DATA=
	fi
	return 0
}
