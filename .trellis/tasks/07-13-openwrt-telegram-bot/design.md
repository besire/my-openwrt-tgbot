# OpenWrt Telegram Bot Technical Design

## Summary

The project is an OpenWrt feed containing two architecture-independent packages:

- `tgbot`: BusyBox `ash` runtime, UCI schema, `procd` service, safe helpers, and
  Telegram WOL, status, reachability, and network-diagnostic behavior.
- `luci-app-tgbot`: modern LuCI JavaScript configuration and service UI. It
  depends on `tgbot`; the core package does not depend on LuCI.

The packages stay in one Trellis task because the LuCI form, runtime validation,
and Telegram behavior share one UCI contract and are released together.

## Architecture

```text
Telegram Bot API or configured compatible reverse proxy
                         ^
                         | outbound HTTPS long polling and method calls
                         v
procd -> tgbot daemon -> auth/dispatch -> status/network collectors
                         |             -> configured-device reachability
                         |             -> WOL confirmation -> etherwake -> ping
                         v
                    /etc/config/tgbot
                         ^
                         | UCI + narrowly scoped RPC/file helpers
                         v
                  luci-app-tgbot
```

The router opens no inbound port. The VPS reverse proxy remains external to this
repository and must preserve Telegram's standard `/bot<TOKEN>/<method>` paths.

## Repository Layout

```text
tgbot/
  Makefile
  files/etc/config/tgbot
  files/etc/init.d/tgbot
  files/usr/libexec/tgbot/*
luci-app-tgbot/
  Makefile
  htdocs/luci-static/resources/view/tgbot/config.js
  root/usr/share/luci/menu.d/luci-app-tgbot.json
  root/usr/share/rpcd/acl.d/luci-app-tgbot.json
  po/zh_Hans/tgbot.po
tests/
README.md
```

Both package Makefiles use the standard OpenWrt build system and declare
`PKGARCH:=all`. The build system, not project-specific packaging code, selects
`.apk` or `.ipk`.

## UCI Contract

`/etc/config/tgbot` is the sole persistent configuration source. LuCI provides
early field feedback; shell validation is authoritative before any network or
WOL action.

| Section / option | Shape | Contract |
|---|---|---|
| `config bot 'main'` | named section | Single global bot configuration |
| `enabled` | boolean | Defaults to `0` |
| `token` | secret string | Required when enabled; nonempty with no whitespace/control characters |
| `api_base_url` | HTTPS URL | Defaults to `https://api.telegram.org`; path prefix allowed; query, fragment, and userinfo forbidden; trailing slash normalized |
| `admin_id` | list of decimal IDs | At least one unique positive Telegram user ID when enabled |
| `poll_timeout` | integer | 1-50 seconds; default 50 |
| `status_interface` | list of UCI network names | Defaults to `wan`, `wan6` |
| `wake_check_delay` | integer | Initial post-WOL delay; bounded range |
| `wake_check_attempts` | integer | Bounded number of ping attempts |
| `wake_check_interval` | integer | Bounded delay between attempts |
| `config device` | anonymous repeatable section | One WOL target |
| `enabled` | boolean | Defaults to `1` |
| `name` | display string | Required, unique, bounded length, no control characters |
| `mac` | canonical MAC | Exact six-octet colon-separated address |
| `interface` | Linux interface name | Required, must not start with `-`, must exist before wake |
| `check_ip` | optional IPv4 literal | Enables bounded post-wake reachability checking |

The package installs this file as a conffile with restrictive permissions.
Secrets are never passed in `procd` arguments, environment variables, logs, or
curl command-line arguments.

## Runtime Boundaries

### Process Model

`/etc/init.d/tgbot` registers one foreground daemon with `procd`, reload
triggers, and bounded respawn. It starts only when `enabled=1` and authoritative
configuration validation succeeds. The daemon loads UCI itself so the token and
administrator list are not exposed in process arguments.

### Telegram Transport

- Use `getUpdates` long polling with `limit=1`, a maximum server timeout of 50
  seconds, and only `message` and `callback_query` update types.
- Keep one update in each response so `jsonfilter` field correlation remains
  deterministic in shell.
- Write the next update offset atomically before dispatch. This favors
  at-most-once execution over replaying a WOL action after a crash.
- Preserve the offset in a mode-0700 runtime directory under `/tmp`. When no
  offset exists after boot, discard pre-start backlog before accepting new
  actions.
- Use bounded exponential retry (1 to 60 seconds) for network, HTTP, malformed
  JSON, and Telegram `ok=false` failures. Reset retry state after success.
- Generate request JSON with OpenWrt's `jshn.sh`; never concatenate unescaped
  user/config text into JSON.
- Feed curl options and the token-bearing URL through stdin config so the token
  is absent from `ps`. TLS verification remains enabled; `-k` is forbidden.
- Join the normalized base URL as `<base>/bot<TOKEN>/<method>`. Method names come
  from an internal allowlist, never Telegram input.

### Decode, Authorization, And Dispatch

One decoder owns extraction and normalization of Telegram update fields. The
dispatcher receives normalized values rather than reparsing JSON.

Before every command or callback:

1. Advance the update offset.
2. Require `chat.type == private`.
3. Match `from.id` exactly against the UCI administrator list.
4. Dispatch an exact known command/callback prefix without `eval`.

Unsupported and unauthorized updates cannot reach status or WOL functions.
Logs may record a reason and numeric update ID at an appropriate level, but not
message text, token, administrator lists, or response bodies.

Text commands and fixed `menu:<action>` callbacks converge on one exact-match
action dispatcher. `/start` and `/menu` render a fixed inline keyboard for
status, configured-device reachability, network diagnostics, and WOL. The
dispatcher never evaluates callback data or accepts an arbitrary method name.

## WOL Flow

1. `/wol` reloads valid enabled UCI devices and sends an inline target keyboard.
2. A target-selection callback looks up the UCI section again and creates a
   cryptographically random, single-use nonce file under `/tmp/tgbot/confirm`.
   The mode-0600 file binds nonce, administrator ID, chat ID, target section, and
   a 60-second expiry.
3. Telegram displays Confirm and Cancel buttons containing only the nonce.
4. Confirm atomically consumes the nonce before running any action, repeats
   authorization/config/interface validation, and invokes exactly:
   `etherwake -i <validated-interface> <validated-mac>`.
5. The reply distinguishes command failure, magic-packet sent, and target
   observed online. When `check_ip` exists, bounded `ping` attempts begin after
   the configured delay; failure to reply never changes "sent" into "online".

Old, forged, expired, reused, or cross-user callback data cannot invoke
`etherwake`. Device labels are presentation only; stable UCI section IDs and
nonce state own execution identity.

## Router Status

`/status` collects local, read-only data and formats one plain-text Chinese
message below Telegram's message size limit:

- `ubus call system board`: hostname/model and OpenWrt release/revision.
- `ubus call system info` and `/proc`: uptime, load, and memory.
- `df -kP /overlay`: overlay use, when `/overlay` exists.
- `/sys/class/thermal/thermal_zone*`: prefer CPU/SoC zones; otherwise report an
  available valid zone; report unavailable rather than failing.
- `ubus call network.interface.<name> status`: configured WAN/WAN6 state and
  assigned interface addresses.
- Current daemon state: running when it can answer the command.

No external public-IP or hardware-information service is called. Each collector
returns a normalized value or unavailable marker; the formatter does not parse
raw `ubus` payloads.

## Configured Device Reachability

`/devices` iterates the same valid enabled UCI device sections used by `/wol`.
For each target, it displays the configured name and optional check IP. A target
with a check IP receives exactly one `ping -c 1 -W 1` probe; failure is reported
as no response rather than proof that the host is offline. Targets without a
check IP are reported as not configured for checking. The command does not read
DHCP leases, neighbor tables, or probe addresses outside the allowlist.

## Local Network Diagnostics

`/network` queries the existing `status_interface` list through
`ubus call network.interface.<name> status`. It reports interface state,
protocol, L3 device, assigned addresses, default IPv4/IPv6 gateways, and DNS
servers when present. One bounded IPv4 default-gateway ping adds a local
reachability result. Missing interfaces or fields are nonfatal, and no external
connectivity or public-IP service is contacted.

## LuCI Application

The app appears under Services and uses native LuCI `form`, `uci`, `rpc`, `poll`,
and `ui` modules. It has an unframed configuration layout with:

- General settings: enable toggle, password-style token input, API base URL,
  administrator ID list, polling and reachability limits.
- Status settings: WAN/WAN6 interface list.
- WOL devices: editable grid for enabled, name, MAC, interface, and optional
  check IP.
- Runtime actions: service state, Test API, and Save/Apply. Helpers expose fixed
  operations and ignore arbitrary arguments.

The RPC ACL grants only UCI access to `tgbot`, read access needed for interface
choices/service status, and execution of fixed project helpers. It does not
grant a generic shell. English source labels are translated by `po/zh_Hans`.

## Packaging And Compatibility

- Primary build reference: `YYH2913/openwrt` branch
  `xr1710g-6.18-integration`, commit `2a845ee80c`, target `airoha/an7581`,
  `apk-tools 3.0.5`.
- Secondary build reference: OpenWrt 24.10 SDK for `.ipk` compatibility.
- Core dependencies: `curl`, `ca-bundle`, `jsonfilter`, `libubox`/`jshn`,
  `ubus`, `uci`, `etherwake`, and `coreutils-od`; BusyBox provides `ash`, `awk`,
  `ping`, `tr`, and basic filesystem tools. `od` is explicit because the
  reference firmware's custom BusyBox configuration disables that applet.
- `luci-app-tgbot` depends on `tgbot` and modern `luci-base`.
- Core, LuCI, and translation packages use the same explicit semantic version
  and OpenWrt release suffix instead of LuCI's generated timestamp/hash form.
- The service is installed disabled. Installation never starts network activity
  before a user supplies valid configuration and explicitly enables it.
- Locally built unsigned packages require either a trusted repository signing
  key or an explicit one-time untrusted local install; this is documented and
  never bypassed silently.

## Validation Strategy

- Host tests use command mocks for UCI, ubus, curl, etherwake, and ping.
- Fixtures cover Telegram messages, callback queries, malformed/error replies,
  missing status metrics, and UCI edge cases.
- Security regressions cover unauthorized/group updates, forged/expired/reused
  confirmations, shell metacharacters, JSON escaping, token leakage in process
  arguments/logs, invalid API URLs, and retry bounds.
- Shell is checked with ShellCheck and exercised with BusyBox-compatible `ash`.
- LuCI JavaScript and JSON manifests receive syntax/structure checks; validation
  rules are tested against the same valid/invalid fixture table as shell where
  practical.
- Package builds run against both the matching APK buildroot/SDK and an OpenWrt
  24.10 IPK SDK. Final WOL behavior requires a real OpenWrt/LAN smoke test.

## Rollout And Rollback

Install `tgbot` first, then `luci-app-tgbot`; configure while disabled, run the
API test, enable, and verify `/status` before WOL. Preserve `/etc/config/tgbot`
on upgrades. Rollback disables/stops the service, reinstalls the previous
packages or removes both packages, and restores the prior conffile. No firmware
or network configuration migration is required.

## Trade-offs

- Shell minimizes router footprint but requires strict structured boundaries;
  `limit=1` accepts lower throughput for reliable JSON correlation.
- At-most-once offset handling may drop an update during a narrow crash window;
  this is preferable to replaying a wake action.
- Ping can produce false offline results; replies always preserve the stronger
  fact that the magic packet was sent.
- One source supports both package generations, but build artifacts are produced
  and tested separately rather than claimed universal.
