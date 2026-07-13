#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=SC2034

set -u

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

PASS=0
FAIL=0
MOCK_INCLUDE_DEVICE=1
MOCK_ENABLED=1
MOCK_TOKEN='123456:TEST_TOKEN'
MOCK_ADMINS='123456789'
MOCK_STATUS_INTERFACES='wan wan6'
MOCK_DEVICE_ENABLED=1
MOCK_DEVICE_NAME='NAS'
MOCK_DEVICE_MAC='00:11:22:33:44:55'
MOCK_DEVICE_INTERFACE='br-lan'
MOCK_DEVICE_CHECK_IP='192.168.1.10'

config_load() { [ "$1" = tgbot ]; }

config_get() {
	destination=$1
	section=$2
	option=$3
	default=${4:-}
	value=$default
	case "$section.$option" in
		main.token) value=$MOCK_TOKEN ;;
		main.api_base_url) value=${MOCK_API_BASE_URL:-https://api.telegram.org} ;;
		main.poll_timeout) value=${MOCK_POLL_TIMEOUT:-50} ;;
		main.wake_check_delay) value=${MOCK_WAKE_CHECK_DELAY:-0} ;;
		main.wake_check_attempts) value=${MOCK_WAKE_CHECK_ATTEMPTS:-1} ;;
		main.wake_check_interval) value=${MOCK_WAKE_CHECK_INTERVAL:-1} ;;
		cfg001.name) value=$MOCK_DEVICE_NAME ;;
		cfg001.mac) value=$MOCK_DEVICE_MAC ;;
		cfg001.interface) value=$MOCK_DEVICE_INTERFACE ;;
		cfg001.check_ip) value=$MOCK_DEVICE_CHECK_IP ;;
	esac
	eval "$destination=\$value"
}

config_get_bool() {
	destination=$1
	section=$2
	option=$3
	default=${4:-0}
	value=$default
	case "$section.$option" in
		main.enabled) value=$MOCK_ENABLED ;;
		cfg001.enabled) value=$MOCK_DEVICE_ENABLED ;;
	esac
	eval "$destination=\$value"
}

config_list_foreach() {
	section=$1
	option=$2
	callback=$3
	case "$section.$option" in
		main.admin_id) values=$MOCK_ADMINS ;;
		main.status_interface) values=$MOCK_STATUS_INTERFACES ;;
		*) values= ;;
	esac
	for value in $values; do "$callback" "$value"; done
}

config_foreach() {
	callback=$1
	type=$2
	[ "$type" = device ] || return 0
	[ "$MOCK_INCLUDE_DEVICE" -eq 0 ] || "$callback" cfg001
}

export TGBOT_FUNCTIONS_SH=/dev/null
export TGBOT_JSHN_SH="$ROOT/tests/mocks/jshn.sh"
export TGBOT_JSONFILTER_BIN="$ROOT/tests/mocks/jsonfilter"
export TGBOT_CURL_BIN="$ROOT/tests/mocks/curl"
export TGBOT_UBUS_BIN="$ROOT/tests/mocks/ubus"
export TGBOT_ETHERWAKE_BIN="$ROOT/tests/mocks/etherwake"
export TGBOT_PING_BIN="$ROOT/tests/mocks/ping"
export TGBOT_SLEEP_BIN="$ROOT/tests/mocks/sleep"
export TGBOT_LIB_DIR="$ROOT/tgbot/files/usr/libexec/tgbot/lib"
export TGBOT_RUNTIME_DIR="$TMP_ROOT/runtime"
export TGBOT_CONFIRM_DIR="$TGBOT_RUNTIME_DIR/confirm"
export TGBOT_SYS_CLASS_NET="$TMP_ROOT/sys/class/net"
export TGBOT_PROC_ROOT="$ROOT/tests/fixtures/proc"
export TGBOT_THERMAL_ROOT="$ROOT/tests/fixtures/thermal"
export TGBOT_OVERLAY_PATH="$TMP_ROOT"
export MOCK_FIXTURE_DIR="$ROOT/tests/fixtures"
export MOCK_CURL_RESPONSE="$ROOT/tests/fixtures/telegram-ok.json"
export MOCK_CURL_ARGV_LOG="$TMP_ROOT/curl.argv"
export MOCK_CURL_CONFIG_LOG="$TMP_ROOT/curl.config"
export MOCK_ETHERWAKE_LOG="$TMP_ROOT/etherwake.log"
export MOCK_PING_LOG="$TMP_ROOT/ping.log"
export MOCK_SLEEP_LOG="$TMP_ROOT/sleep.log"
export MOCK_INIT_LOG="$TMP_ROOT/init.log"
export MOCK_UCI_LOG="$TMP_ROOT/uci.log"

mkdir -p "$TGBOT_RUNTIME_DIR" "$TGBOT_CONFIRM_DIR" "$TGBOT_SYS_CLASS_NET/br-lan"
: >"$MOCK_ETHERWAKE_LOG"
: >"$MOCK_PING_LOG"
: >"$MOCK_SLEEP_LOG"
: >"$MOCK_INIT_LOG"
: >"$MOCK_UCI_LOG"

# shellcheck source=/dev/null
. "$TGBOT_LIB_DIR/common.sh"
# shellcheck source=/dev/null
. "$TGBOT_LIB_DIR/telegram.sh"
# shellcheck source=/dev/null
. "$TGBOT_LIB_DIR/status.sh"
# shellcheck source=/dev/null
. "$TGBOT_LIB_DIR/wol.sh"

pass() {
	PASS=$((PASS + 1))
	printf 'ok %d - %s\n' "$((PASS + FAIL))" "$1"
}

fail() {
	FAIL=$((FAIL + 1))
	printf 'not ok %d - %s\n' "$((PASS + FAIL))" "$1"
}

assert_true() {
	description=$1
	shift
	if "$@"; then pass "$description"; else fail "$description"; fi
}

assert_false() {
	description=$1
	shift
	if "$@"; then fail "$description"; else pass "$description"; fi
}

assert_equal() {
	description=$1 expected=$2 actual=$3
	if [ "$expected" = "$actual" ]; then
		pass "$description"
	else
		fail "$description (expected '$expected', got '$actual')"
	fi
}

assert_contains() {
	description=$1 haystack=$2 needle=$3
	case "$haystack" in
		*"$needle"*) pass "$description" ;;
		*) fail "$description (missing '$needle')" ;;
	esac
}

run_apply() (
	TGBOT_INIT_SCRIPT="$ROOT/tests/mocks/init-tgbot"
	TGBOT_UCI_BIN="$ROOT/tests/mocks/uci"
	export TGBOT_INIT_SCRIPT TGBOT_UCI_BIN
	# shellcheck source=/dev/null
	. "$ROOT/tgbot/files/usr/libexec/tgbot/apply" >"$TMP_ROOT/apply.out" 2>&1
)

printf 'TAP version 13\n'

assert_true 'valid IPv4 is accepted' tgbot_is_ipv4 '192.168.1.10'
assert_false 'out-of-range IPv4 is rejected' tgbot_is_ipv4 '256.1.1.1'
assert_true 'valid custom HTTPS API URL is accepted' tgbot_is_https_url 'https://relay.example/tg'
assert_true 'custom HTTPS API URL with a port is accepted' tgbot_is_https_url 'https://relay.example:8443/tg'
assert_false 'API URL userinfo is rejected' tgbot_is_https_url 'https://user@relay.example/tg'
assert_false 'API URL quote is rejected' tgbot_is_https_url 'https://relay.example/"bad'
assert_false 'API URL nonnumeric port is rejected' tgbot_is_https_url 'https://relay.example:bad/tg'
assert_false 'API URL out-of-range port is rejected' tgbot_is_https_url 'https://relay.example:65536/tg'
assert_false 'API URL empty hostname label is rejected' tgbot_is_https_url 'https://relay..example/tg'
assert_true 'Telegram token syntax is accepted' tgbot_is_token "$MOCK_TOKEN"
assert_false 'token whitespace is rejected' tgbot_is_token '123:bad token'
assert_false 'zero Telegram administrator ID is rejected' tgbot_is_telegram_id '0'
assert_false 'leading-zero Telegram administrator ID is rejected' tgbot_is_telegram_id '0123'
TGBOT_DEVICE_NAMES='NAS\nBackup'
assert_true 'device-name duplicate matching preserves backslashes' _tgbot_name_seen 'NAS\nBackup'
TGBOT_DEVICE_NAMES=

tgbot_load_config
assert_true 'strict mock configuration is valid' tgbot_validate_config strict
MOCK_DEVICE_INTERFACE='-i'
tgbot_load_config
assert_false 'option-like WOL interface is rejected' tgbot_validate_config strict
MOCK_DEVICE_INTERFACE='br-lan'

MOCK_ENABLED=0
MOCK_DEVICE_MAC='invalid-mac'
: >"$MOCK_INIT_LOG"
: >"$MOCK_UCI_LOG"
assert_true 'disabled service can be applied despite invalid device settings' run_apply
assert_equal 'disabled apply stops and disables the service' 'stop
disable' "$(cat "$MOCK_INIT_LOG")"
assert_equal 'disabled apply commits only the tgbot configuration' 'commit tgbot' "$(cat "$MOCK_UCI_LOG")"

MOCK_INIT_DISABLE_EXIT=1
export MOCK_INIT_DISABLE_EXIT
: >"$MOCK_INIT_LOG"
assert_false 'disabled apply reports init disable failures' run_apply
unset MOCK_INIT_DISABLE_EXIT

MOCK_ENABLED=1
MOCK_DEVICE_MAC='00:11:22:33:44:55'
MOCK_UCI_EXIT=1
export MOCK_UCI_EXIT
: >"$MOCK_INIT_LOG"
: >"$MOCK_UCI_LOG"
assert_false 'enabled apply reports UCI commit failures' run_apply
assert_equal 'service is not enabled after commit failure' '' "$(cat "$MOCK_INIT_LOG")"
unset MOCK_UCI_EXIT

MOCK_INIT_ENABLE_EXIT=1
export MOCK_INIT_ENABLE_EXIT
: >"$MOCK_INIT_LOG"
assert_false 'enabled apply reports init enable failures' run_apply
assert_equal 'restart is skipped after enable failure' 'enable' "$(cat "$MOCK_INIT_LOG")"
unset MOCK_INIT_ENABLE_EXIT

MOCK_INIT_RESTART_EXIT=1
export MOCK_INIT_RESTART_EXIT
: >"$MOCK_INIT_LOG"
assert_false 'enabled apply reports init restart failures' run_apply
assert_equal 'enabled apply attempts enable before restart' 'enable
restart' "$(cat "$MOCK_INIT_LOG")"
unset MOCK_INIT_RESTART_EXIT

assert_true 'message update decodes' telegram_decode_update "$ROOT/tests/fixtures/update-message.json"
assert_equal 'message update ID is normalized' 42 "$TGBOT_UPDATE_ID"
assert_equal 'message user ID is normalized' 123456789 "$TGBOT_USER_ID"
assert_equal 'message command text is normalized' /status "$TGBOT_MESSAGE_TEXT"
assert_true 'callback update decodes' telegram_decode_update "$ROOT/tests/fixtures/update-callback.json"
assert_equal 'callback data is normalized' wol_select:cfg001 "$TGBOT_CALLBACK_DATA"

MOCK_API_BASE_URL='https://relay.example/tg'
tgbot_load_config
payload="$TMP_ROOT/payload.json"
response="$TMP_ROOT/response.json"
printf '%s\n' '{}' >"$payload"
assert_true 'Telegram API call succeeds through mock curl' telegram_api_call getMe "$payload" "$response"
curl_argv=$(cat "$MOCK_CURL_ARGV_LOG")
curl_config=$(cat "$MOCK_CURL_CONFIG_LOG")
case "$curl_argv" in
	*"$MOCK_TOKEN"*) fail 'bot token is absent from curl argv' ;;
	*) pass 'bot token is absent from curl argv' ;;
esac
assert_contains 'custom API URL uses standard bot method path' "$curl_config" "https://relay.example/tg/bot$MOCK_TOKEN/getMe"

MOCK_CURL_HTTP_CODE=502
export MOCK_CURL_HTTP_CODE
assert_false 'non-200 Telegram response is rejected' telegram_api_call getMe "$payload" "$response"
assert_equal 'HTTP failure has a bounded diagnostic' 'Telegram returned HTTP 502' "$TGBOT_TELEGRAM_ERROR"
unset MOCK_CURL_HTTP_CODE
MOCK_CURL_RESPONSE="$ROOT/tests/fixtures/telegram-error.json"
export MOCK_CURL_RESPONSE
assert_false 'Telegram ok=false response is rejected' telegram_api_call getMe "$payload" "$response"
MOCK_CURL_RESPONSE="$ROOT/tests/fixtures/telegram-ok.json"
export MOCK_CURL_RESPONSE
MOCK_API_BASE_URL='https://api.telegram.org'

wol_reset_confirmation_state
nonce=$(wol_create_confirmation 123456789 123456789 cfg001)
assert_false 'confirmation is bound to its administrator' wol_consume_confirmation "$nonce" 999 123456789
nonce=$(wol_create_confirmation 123456789 123456789 cfg001)
assert_true 'fresh confirmation is consumed once' wol_consume_confirmation "$nonce" 123456789 123456789
assert_equal 'confirmation resolves the configured section' cfg001 "$TGBOT_CONFIRM_SECTION"
assert_false 'consumed confirmation cannot be reused' wol_consume_confirmation "$nonce" 123456789 123456789
assert_false 'forged confirmation is rejected' wol_consume_confirmation aaaaaaaaaaaaaaaaaaaaaaaa 123456789 123456789
expired=bbbbbbbbbbbbbbbbbbbbbbbb
printf '123456789\n123456789\ncfg001\n1\n' >"$TGBOT_CONFIRM_DIR/$expired"
assert_false 'expired confirmation is rejected' wol_consume_confirmation "$expired" 123456789 123456789

telegram_send_text() { printf '%s\n' "$2" >>"$TMP_ROOT/messages.log"; }
MOCK_PING_EXIT=0
export MOCK_PING_EXIT
: >"$MOCK_ETHERWAKE_LOG"
tgbot_load_config
assert_true 'confirmed WOL invokes the executor' wol_execute_confirmed 123456789 cfg001
assert_equal 'etherwake receives only validated interface and MAC' '-i br-lan 00:11:22:33:44:55' "$(cat "$MOCK_ETHERWAKE_LOG")"
assert_contains 'online result is reported separately' "$(cat "$TMP_ROOT/messages.log")" 'NAS 已检测为在线。'
MOCK_DEVICE_INTERFACE='-bad'
: >"$MOCK_ETHERWAKE_LOG"
assert_false 'invalid WOL config never invokes etherwake' wol_execute_confirmed 123456789 cfg001
assert_equal 'etherwake log remains empty after invalid config' '' "$(cat "$MOCK_ETHERWAKE_LOG")"
MOCK_DEVICE_INTERFACE='br-lan'
MOCK_DEVICE_MAC='00:11:22:33:44:GG'
: >"$MOCK_ETHERWAKE_LOG"
assert_false 'invalid MAC never invokes the WOL executor' wol_execute_confirmed 123456789 cfg001
assert_equal 'etherwake log remains empty after invalid MAC' '' "$(cat "$MOCK_ETHERWAKE_LOG")"
MOCK_DEVICE_MAC='00:11:22:33:44:55'
: >"$MOCK_ETHERWAKE_LOG"
assert_false 'unknown WOL target is rejected' wol_execute_confirmed 123456789 cfg999
assert_equal 'unknown target never invokes etherwake' '' "$(cat "$MOCK_ETHERWAKE_LOG")"

tgbot_collect_status
assert_contains 'status includes board model' "$TGBOT_STATUS_TEXT" 'Airoha AN7581'
assert_contains 'status includes firmware revision' "$TGBOT_STATUS_TEXT" 'r1804-2a845ee80c'
assert_contains 'status includes temperature' "$TGBOT_STATUS_TEXT" '52.5 C'
assert_contains 'status includes WAN address' "$TGBOT_STATUS_TEXT" '198.51.100.10'
assert_contains 'status includes WAN IPv6 address' "$TGBOT_STATUS_TEXT" '2001:db8::10'
assert_contains 'status degrades unavailable WAN6 to offline' "$TGBOT_STATUS_TEXT" 'wan6: 离线'

TGBOT_SOURCE_ONLY=1
export TGBOT_SOURCE_ONLY
# shellcheck source=/dev/null
. "$ROOT/tgbot/files/usr/libexec/tgbot/tgbotd"
assert_equal 'retry backoff doubles below cap' 16 "$(tgbot_backoff_next 8)"
assert_equal 'retry backoff is capped' 60 "$(tgbot_backoff_next 60)"

tgbot_log() { :; }
dispatch_count=0
tgbot_dispatch_message() { dispatch_count=$((dispatch_count + 1)); }
TGBOT_UPDATE_ID=100
TGBOT_UPDATE_KIND=message
TGBOT_USER_ID=123456789
TGBOT_CHAT_TYPE=group
tgbot_dispatch_update
assert_equal 'group messages are never dispatched' 0 "$dispatch_count"
TGBOT_CHAT_TYPE=private
TGBOT_USER_ID=999
tgbot_dispatch_update
assert_equal 'non-administrator messages are never dispatched' 0 "$dispatch_count"
TGBOT_USER_ID=123456789
tgbot_dispatch_update
assert_equal 'authorized private messages are dispatched' 1 "$dispatch_count"

telegram_answer_callback() { printf '%s\n' "$2" >>"$TMP_ROOT/callbacks.log"; }
nonce=$(wol_create_confirmation 123456789 123456789 cfg001)
: >"$MOCK_ETHERWAKE_LOG"
wol_handle_callback callback-1 "wol_cancel:$nonce" 123456789 123456789
assert_equal 'cancelled confirmation never invokes etherwake' '' "$(cat "$MOCK_ETHERWAKE_LOG")"
assert_false 'cancelled confirmation cannot be reused' wol_consume_confirmation "$nonce" 123456789 123456789

: >"$TMP_ROOT/callbacks.log"
TGBOT_UPDATE_KIND=callback
TGBOT_CALLBACK_ID='callback-2'
TGBOT_CALLBACK_DATA='wol_confirm:aaaaaaaaaaaaaaaaaaaaaaaa'
TGBOT_CHAT_TYPE=group
tgbot_dispatch_update
assert_equal 'group callbacks are never dispatched' '' "$(cat "$TMP_ROOT/callbacks.log")"
TGBOT_CHAT_TYPE=private
TGBOT_USER_ID=999
tgbot_dispatch_update
assert_equal 'non-administrator callbacks are never dispatched' '' "$(cat "$TMP_ROOT/callbacks.log")"
TGBOT_USER_ID=123456789
tgbot_dispatch_update
assert_contains 'authorized private callbacks are dispatched' "$(cat "$TMP_ROOT/callbacks.log")" '确认已失效。'

TGBOT_OFFSET_FILE="$TMP_ROOT/offset"
export TGBOT_OFFSET_FILE
assert_true 'next update offset is written atomically' tgbot_write_offset 101
assert_equal 'stored update offset is readable' 101 "$(tgbot_read_offset)"

printf '1..%d\n' "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
