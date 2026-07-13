# OpenWrt Telegram Bot

`tgbot` is a small OpenWrt-native Telegram bot for read-only router status and
Wake-on-LAN through `etherwake`. It runs under BusyBox `ash`, is managed by
`procd`, and has an optional modern LuCI application.

## Packages

- `tgbot`: core bot, UCI configuration, service, and runtime helpers.
- `luci-app-tgbot`: LuCI configuration and service page.
- `luci-i18n-tgbot-zh-cn`: Simplified Chinese LuCI translations, generated
  automatically while building the LuCI package.

Both packages are architecture-independent OpenWrt feed packages. The same
source produces `.apk` on APK-based OpenWrt and `.ipk` on OpenWrt 24.10.

## Build As A Local Feed

Add this repository to the OpenWrt buildroot or SDK `feeds.conf`:

```text
src-link tgbot /absolute/path/to/my-openwrt-tgbot
```

Then install the feed metadata and build both packages:

```sh
./scripts/feeds update tgbot
./scripts/feeds install -a -p tgbot
make package/tgbot/compile V=s
make package/luci-app-tgbot/compile V=s
```

The primary APK build reference is `YYH2913/openwrt`, branch
`xr1710g-6.18-integration`, commit `2a845ee80c`, for `airoha/an7581`. Use the
firmware's matching source tree or SDK for reproducible packages.

Source-level package compatibility is checked against that exact commit. Local
package builds are verified with OpenWrt 25.12.5 (`apk-tools 3.0.5`) for APK
generation and OpenWrt 24.10.7 for IPK generation. The YYH2913 releases publish
firmware images but no matching SDK, so the generic APK build is a `noarch`
format check; installation on revision `2a845ee80c` remains a separate required
smoke test.

## Installation

Install locally built APK files with an explicit trust decision, or sign a
private repository with a key trusted by the router:

```sh
apk add --allow-untrusted ./tgbot-*.apk
apk add --allow-untrusted ./luci-app-tgbot-*.apk
apk add --allow-untrusted ./luci-i18n-tgbot-zh-cn-*.apk
```

For an IPK-based release:

```sh
opkg install ./tgbot_*.ipk
opkg install ./luci-app-tgbot_*.ipk
opkg install ./luci-i18n-tgbot-zh-cn_*.ipk
```

The service is disabled in UCI by default. Configure it under
**Services > Telegram Bot**, test the API connection, then enable it.

LuCI is optional. For a core-only installation, edit `/etc/config/tgbot` while
the service is disabled, then run:

```sh
/usr/libexec/tgbot/validate --strict
/usr/libexec/tgbot/test-api
/usr/libexec/tgbot/apply
```

Set `option enabled '1'` before `apply` when the validation and API checks pass.
The helper commits only the `tgbot` UCI configuration and updates its `procd`
service state.

## Telegram API Reverse Proxy

`api_base_url` defaults to `https://api.telegram.org`. A custom HTTPS URL may
include a path prefix, but it must preserve Telegram's standard request layout:

```text
<api_base_url>/bot<BOT_TOKEN>/<METHOD>
```

The project does not deploy or manage the reverse proxy. TLS certificate
verification is always enabled.

## Security Model

- Only private chats from configured numeric Telegram user IDs are accepted.
- WOL targets are an explicit UCI allowlist.
- Every wake requires a fresh, single-use confirmation.
- Telegram input is never evaluated as shell code.
- The bot token is not passed through process arguments or logs.
- The LuCI ACL exposes fixed bot operations, not a generic shell.

## Development Checks

```sh
./tests/run.sh
busybox ash ./tests/run.sh
shellcheck tgbot/files/etc/init.d/tgbot \
  tgbot/files/usr/libexec/tgbot/apply \
  tgbot/files/usr/libexec/tgbot/test-api \
  tgbot/files/usr/libexec/tgbot/tgbotd \
  tgbot/files/usr/libexec/tgbot/validate \
  tgbot/files/usr/libexec/tgbot/lib/*.sh tests/*.sh tests/mocks/*
node --check luci-app-tgbot/htdocs/luci-static/resources/view/tgbot/config.js
jq empty luci-app-tgbot/root/usr/share/luci/menu.d/luci-app-tgbot.json \
  luci-app-tgbot/root/usr/share/rpcd/acl.d/luci-app-tgbot.json
```

Real WOL validation must be performed on an authorized LAN device after mock and
authorization tests pass.
