# Build OpenWrt Telegram Bot

## Goal

Build a Telegram bot that runs on an OpenWrt router and lets its owner or
administrators wake configured LAN devices through `etherwake`, inspect the
router's current status, check configured-device reachability, and view local
network diagnostics.

## User Value

- Wake a LAN device remotely through Telegram without exposing another public
  management endpoint.
- Check essential router health and connectivity from a concise Telegram reply.
- Avoid exposing an additional router management service to the public Internet.

## Confirmed Facts

- The deployment target is OpenWrt.
- Telegram is the user-facing interaction channel.
- Wake-on-LAN through OpenWrt's `etherwake` utility is the primary MVP feature.
- Router status reporting is the second confirmed MVP feature.
- This is a greenfield repository: there is no application code, dependency
  manifest, test suite, README, or established implementation language yet.
- The repository currently contains only Trellis and agent configuration.
- The deployment environment may be unable to reach `api.telegram.org`
  directly.
- The user already operates a VPS reverse proxy. Deploying or managing that
  proxy is outside this project's scope; the bot only needs a configurable
  Telegram Bot API base URL.
- A LuCI application is part of the requested product scope.
- The initial device runs OpenWrt `SNAPSHOT` revision `r1804-2a845ee80c` for
  target `airoha/an7581`, package architecture `aarch64_cortex-a53`, and kernel
  architecture `aarch64`.
- The target uses `apk-tools 3.0.5`; the native deliverables are OpenWrt `.apk`
  packages. The reported firmware taints are `no-all busybox`.
- On 2026-07-13, the official `airoha/an7581` Snapshot download directory
  exposes SDK revision `r35330-e8c74e8f1e`, which does not match the device's
  `r1804-2a845ee80c`. Official rolling Snapshot artifacts therefore cannot be
  assumed to reproduce this firmware.
- The target firmware was obtained from the releases of
  `https://github.com/YYH2913/openwrt`; its build configuration and source
  lineage must be treated as the compatibility reference for the initial
  device.
- Device revision hash `2a845ee80c` exactly matches branch
  `xr1710g-6.18-integration` in that repository. Inspection confirms this tree
  packages `apk-tools 3.0.5`, matching the router.
- One feed-compatible source tree will target both modern OpenWrt package
  generations: `.apk` is the primary artifact for the user's router, and
  `.ipk` compatibility is retained for OpenWrt 24.10.
- Telegram replies default to Simplified Chinese. LuCI uses translatable English
  source strings and ships a Simplified Chinese catalog.
- The bot is private-chat only and authorizes one or more administrators by
  exact Telegram numeric user ID.
- WOL targets are managed through LuCI and selected in Telegram through inline
  buttons followed by an explicit confirmation. Each target has a display name,
  MAC address, send interface, and optional reachability-check IP address.
- `/status` reports hostname, device model, OpenWrt version, uptime, system load,
  memory usage, overlay storage usage, temperature when available, WAN/WAN6
  state and assigned interface addresses, and bot service state.
- The bot runtime is BusyBox `ash`; Python is not part of the first release.
- The core runtime dependencies are `curl`, `jsonfilter`, `ca-bundle`,
  `libubox`/`jshn`, `ubus`, `uci`, `etherwake`, and `coreutils-od`. The target's
  custom BusyBox configuration does not provide `od`; the LuCI frontend uses
  modern LuCI JavaScript.
- The next command increment is `/menu`, `/devices`, and `/network`. It reuses
  the existing WOL target allowlist and configured status interfaces; it does
  not scan arbitrary LAN clients or call external diagnostic services.

## Requirements

- The bot must be able to run within OpenWrt's constrained environment.
- Runtime code must remain compatible with BusyBox `ash` and must not rely on
  Bash-only syntax or GNU-only command behavior.
- Telegram credentials and administrator identities must be configurable and
  must not be hard-coded in source control.
- Router-management actions must be restricted to explicitly authorized users.
- Commands and callback queries from groups, supergroups, channels, or users not
  present in the administrator allowlist must never invoke bot operations.
- Wake targets must be configured as an alias-to-MAC-address allowlist; Telegram
  input must never be evaluated as a shell command or interpolated unchecked
  into an `etherwake` invocation.
- The network interface used by `etherwake` must be configurable.
- `/wol` must render only configured, enabled targets as Telegram inline buttons.
  A target-selection callback must not send a magic packet until the authorized
  user accepts a second confirmation action.
- When a target has a check IP configured, the bot must perform a bounded,
  delayed reachability check after sending the magic packet. It must distinguish
  "packet sent" from "target observed online" in its response.
- Router status commands must be read-only and must report unavailable metrics
  gracefully across supported OpenWrt devices.
- Router status must use local OpenWrt interfaces and data sources only; it must
  not call an external public-IP or device-information service.
- The implementation must provide a repeatable installation and service startup
  path suitable for OpenWrt.
- Packages must contain no architecture-specific compiled artifacts and should
  be installable on any supported OpenWrt CPU architecture where their declared
  dependencies are available.
- Both packages should declare architecture `all`. Runtime portability does not
  imply that one binary package format can be installed by both `apk` and
  `opkg`, or that every historical LuCI API is supported.
- The Telegram Bot API base URL must be configurable and default to
  `https://api.telegram.org`; requests must preserve the standard Telegram Bot
  API method-path contract under the configured base URL.
- The Telegram command set is `/start`, `/help`, `/menu`, `/status`, `/devices`,
  `/network`, and `/wol`, plus fixed inline callbacks for the menu and for WOL
  selection, confirmation, and cancel.
- `/menu` must present fixed buttons for status, configured-device reachability,
  local network diagnostics, and WOL. Menu callbacks must pass through the same
  private-chat and administrator authorization as text commands and dispatch
  through the same action handlers.
- `/devices` must list only valid enabled WOL targets. A target with a configured
  check IP receives one bounded ping probe and is reported as online or not
  responding; a target without a check IP is reported as not configured for
  reachability. The command must not enumerate DHCP leases or scan the LAN.
- `/network` must report each configured status interface's local `ubus` state,
  protocol, L3 device, addresses, default gateways, and DNS servers when
  available. It may perform one bounded IPv4 default-gateway ping but must not
  call an external public-IP, DNS, or connectivity service.
- Secrets must not appear in process logs or command output.
- The solution must not require exposing a new inbound router port.
- The core bot must remain installable and operable without LuCI.
- A separate `luci-app-tgbot` package must provide a modern OpenWrt web UI for
  editing supported UCI settings, managing configured WOL targets, viewing bot
  service state, and invoking only explicitly supported service/test actions.
- Legacy Lua-based LuCI pages are not required; the target uses a modern LuCI
  JavaScript view.
- LuCI RPC/ACL permissions must expose only the operations required by the app.
- Package metadata must use the normal OpenWrt build system and produce the
  native package format of the confirmed target SDK. It must not use Alpine
  `APKBUILD` files or Android APK tooling.
- The same package source must build as `.apk` on the matching APK-based tree and
  as `.ipk` on OpenWrt 24.10 without maintaining separate runtime copies.
- Builds intended for the initial device must use its matching firmware
  buildroot/SDK revision rather than an arbitrary newer rolling Snapshot SDK.
- The repository must keep package sources buildroot/feed-compatible so a
  matching vendor or custom firmware tree can build them even when its SDK is
  not retained by the official rolling Snapshot archive.

Distribution is confirmed as feed-compatible package source producing native
`.apk` and `.ipk` artifacts in their respective OpenWrt build environments.

## Acceptance Criteria

- [ ] The bot can be installed and started on an agreed OpenWrt target.
- [ ] An authorized Telegram user can invoke every agreed MVP command and
      receive a clear response.
- [ ] An authorized user can select a configured device and cause the bot to
      invoke `etherwake` with exactly that device's validated MAC address and
      the configured network interface.
- [ ] Unknown targets, malformed configuration, and invalid MAC addresses never
      invoke `etherwake` and return a clear error.
- [ ] `/wol` offers enabled targets through an inline keyboard, supports cancel,
      and invokes `etherwake` only after a fresh authorized confirmation.
- [ ] A configured check IP triggers a bounded post-wake reachability check;
      absent or unsuccessful checks never misreport the target as online.
- [ ] An authorized user can request router status and receive the agreed health
      and connectivity fields without changing router state.
- [ ] `/status` fits the agreed fields into one readable Telegram message and
      labels unsupported or unavailable metrics without failing the command.
- [ ] `/menu` exposes only fixed known actions, and its authorized callbacks
      produce the same results as their corresponding text commands.
- [ ] `/devices` reports enabled configured targets without LAN scanning and
      distinguishes online, no response, and missing check-IP states.
- [ ] `/network` reports configured-interface details from local OpenWrt data,
      bounds its gateway probe, and degrades missing fields without failing.
- [ ] An unauthorized user cannot read router data or execute router actions.
- [ ] Authorization uses `from.id` rather than usernames, and every command and
      callback path independently enforces both private-chat and administrator
      allowlist checks.
- [ ] Secrets are supplied through deployment configuration rather than source.
- [ ] The service restarts according to the agreed OpenWrt service policy and
      records actionable failures without leaking secrets.
- [ ] Changing the Telegram API base URL causes both update polling and outgoing
      messages to use that URL without source-code changes.
- [ ] The bot works with the user's existing reverse proxy when it implements
      the standard Telegram Bot API URL layout.
- [ ] Installing `luci-app-tgbot` adds a LuCI configuration page that can save
      valid bot, authorization, status, and WOL settings through UCI.
- [ ] Both packages build with the confirmed target's OpenWrt SDK and install
      through its native `apk` package manager.
- [ ] The initial package build targets `airoha/an7581` and installs on
      `aarch64_cortex-a53` OpenWrt Snapshot `r1804-2a845ee80c`.
- [ ] The same source passes package builds for the matching APK-based tree and
      an OpenWrt 24.10 IPK SDK.
- [ ] LuCI shows the current service state and can apply configuration by safely
      restarting the `procd` service.
- [ ] Invalid URLs, Telegram IDs, interfaces, aliases, MAC addresses, and other
      supported fields are rejected with field-specific validation feedback.
- [ ] Telegram outages or proxy failures use bounded retry/backoff and do not
      create a tight request loop.
- [ ] Automated tests cover command authorization and the agreed core behavior.
- [ ] Shell syntax/tests pass under BusyBox-compatible `ash` semantics, and the
      installed bot has no Python runtime dependency.
- [ ] Telegram replies are available in Simplified Chinese, and the LuCI page
      renders correctly in both its English source locale and Simplified Chinese.

## Likely Out Of Scope For The First Release

- A standalone web administration UI outside LuCI.
- Multi-router fleet management or a hosted control plane.
- An untrusted third-party Telegram API relay.
- VPS reverse-proxy installation, configuration, monitoring, or credentials.
- Arbitrary shell execution through Telegram.
- Router reboot, service restart through Telegram, firewall changes, firmware
  upgrades, traffic accounting, DHCP-client browsing, and proactive alerts.
- Compatibility with legacy Lua-based LuCI or every historical OpenWrt release.

## Open Questions

None blocking implementation. The final artifact review may revise the accepted
defaults before the task is activated.

## Notes

- This is a complex task with reviewed `design.md` and `implement.md` artifacts
  required before activation.
- Source/runtime portability, package-manager format compatibility, and LuCI API
  compatibility are separate concerns and will be validated separately.
