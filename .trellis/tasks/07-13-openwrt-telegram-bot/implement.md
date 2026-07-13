# OpenWrt Telegram Bot Implementation Plan

## Delivery Order

- [x] 1. Scaffold the feed packages and project documentation.
  - Add root `tgbot/` and `luci-app-tgbot/` package definitions with
    `PKGARCH:=all`, dependencies, conffiles, and install manifests.
  - Add README coverage for feed/SDK builds, `.apk`/`.ipk` installation,
    reverse-proxy URL expectations, configuration, upgrade, and rollback.
  - Keep both package formats generated from the same source files.

- [x] 2. Implement the authoritative UCI contract and shared shell validation.
  - Add disabled-by-default `/etc/config/tgbot` example configuration.
  - Implement config loading, normalization, and validation for API URL, token,
    administrator IDs, numeric limits, WOL names/MAC/interfaces/check IPs, and
    status interfaces.
  - Expose validation through a safe helper for LuCI while keeping runtime
    validation authoritative.

- [x] 3. Implement the Telegram transport and daemon lifecycle.
  - Add the token-safe curl wrapper, structured JSON request builder, normalized
    response/error contract, custom base URL joining, TLS enforcement, and
    bounded retry/backoff.
  - Add `getUpdates` with `limit=1`, backlog discard, atomic at-most-once offset,
    allowed update types, and clean signal handling.
  - Add `procd` init, validation gate, reload trigger, and bounded respawn.

- [x] 4. Implement centralized Telegram decoding, authorization, and dispatch.
  - Normalize message/callback fields once with `jsonfilter`.
  - Enforce private-chat and administrator-ID authorization before all paths.
  - Implement `/start`, `/help`, unknown-command behavior, callback answers, and
    plain-text Chinese responses without parse-mode injection.

- [x] 5. Implement router status collectors and `/status` formatting.
  - Normalize board, uptime, load, memory, overlay, thermal, WAN/WAN6, and
    service-state values independently.
  - Keep unavailable metrics nonfatal and output one bounded readable message.

- [x] 6. Implement WOL target selection and single-use confirmation.
  - Render enabled UCI targets as inline buttons with safe JSON encoding.
  - Implement expiring nonce state bound to user/chat/target, Confirm/Cancel,
    atomic consume, repeat validation, and the sole `etherwake` execution path.
  - Add optional delayed/bounded IPv4 ping checking with distinct sent/online
    outcomes.

- [x] 7. Implement fixed LuCI service helpers and the LuCI application.
  - Add exact-purpose Test API, validate/apply, and service-state helpers that
    do not accept arbitrary commands.
  - Add menu and least-privilege RPC ACL manifests.
  - Add native general/status forms, editable WOL grid, stable runtime state,
    field-level validation, and Simplified Chinese translations.

- [x] 8. Build the automated regression suite.
  - Add a minimal shell test harness, PATH-based command mocks, shared fixture
    tables, Telegram JSON fixtures, and temporary isolated state/config roots.
  - Cover valid workflows, all trust boundaries, missing metrics, command
    failures, callbacks, backoff, and secret/shell-injection regressions.
  - Add LuCI JS/JSON/catalog syntax checks and package file-layout assertions.

- [ ] 9. Verify both OpenWrt package generations. (Partially complete.)
  - Build `.apk` with the matching `2a845ee80c` APK-based source/SDK.
  - Build `.ipk` with an OpenWrt 24.10 SDK from the same package sources.
  - Inspect package metadata, architecture `all`, dependencies, permissions,
    conffiles, init registration, RPC ACL, and installed file ownership.
  - [x] Build and inspect `noarch` APK packages with OpenWrt 25.12.5 and
    `apk-tools 3.0.5` as a package-format compatibility check.
  - [x] Build and inspect `all` IPK packages with OpenWrt 24.10.7.
  - [ ] Reproduce the APK build with a matching `2a845ee80c` SDK/buildroot. The
    vendor releases publish firmware images but do not publish that SDK.

- [ ] 10. Run integration and release review.
  - Install locally built packages on the target router, configure while
    disabled, test the custom API base, then enable and verify `/status`.
  - Test authorized/unauthorized private and group updates, WOL cancel,
    confirmation expiry/reuse, actual magic-packet delivery, and optional ping.
  - Reboot/restart the router to verify `procd`, backlog handling, conffile
    preservation, logs, and rollback/uninstall behavior.

## Current Verification Status

- 71 regression tests pass with the host `sh` and with BusyBox `ash` plus
  BusyBox applets.
- ShellCheck, LuCI JavaScript syntax, JSON manifests, translation/catalog
  checks, and package layout checks pass.
- Telegram request JSON was exercised with OpenWrt's real `jshn.sh`.
- The LuCI RPC ucode compiles with OpenWrt 25.12.5 and 24.10.7 runtimes.
- Final APK and IPK packages are staged under ignored `dist/` directories with
  `dist/SHA256SUMS` for target-router transfer.
- Exact-source inspection at vendor commit `2a845ee80c` confirms matching
  `apk-tools 3.0.5` and the same architecture-independent packaging semantics,
  but does not replace installation and WOL testing on the target router.

## Validation Commands

Commands may be refined to the final test harness and SDK paths during
implementation.

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
jq empty luci-app-tgbot/root/usr/share/luci/menu.d/luci-app-tgbot.json
jq empty luci-app-tgbot/root/usr/share/rpcd/acl.d/luci-app-tgbot.json
```

Matching APK buildroot:

```sh
./scripts/feeds update -a
./scripts/feeds install -a
make defconfig
make package/tgbot/compile V=s
make package/luci-app-tgbot/compile V=s
```

OpenWrt 24.10 IPK SDK uses the same package compile targets after linking or
adding this repository as a feed.

## Review Gates

- [x] PRD and design are approved before `task.py start`.
- [x] No network or WOL action occurs before authoritative config and auth checks.
- [x] No code path besides the WOL executor invokes `etherwake`.
- [x] No generic shell execution is exposed through Telegram or LuCI RPC ACL.
- [x] Token is absent from argv, environment, logs, fixtures, and committed config.
- [x] Both package formats come from the same runtime source tree.
- [x] Automated checks pass before real-router installation.
- [ ] Real-router validation passes before reporting the task complete.

## Risk And Rollback Points

- Transport/offset changes can replay or lose updates: keep offset behavior
  covered by fixtures before adding commands.
- UCI schema changes affect runtime and LuCI together: change the contract and
  both consumers in one commit-sized step, then test round-trip behavior.
- RPC ACL changes can broaden router control: inspect the final allowlist and
  reject generic executables/methods.
- Package build failures are isolated from runtime code; keep the last building
  package definitions while adjusting SDK-specific metadata.
- Real WOL tests affect a configured LAN device only. Cancel/expiry/mock tests
  run first, and no reboot/network/firewall operations are in scope.
