# Backend Quality Guidelines

## Scenario: Architecture-Independent OpenWrt Packages

### 1. Scope / Trigger

- Trigger: adding or changing an OpenWrt package that contains only portable
  shell, JavaScript, configuration, or data files.
- This contract prevents a portable package from silently inheriting the SDK's
  target CPU architecture.

### 2. Signatures

- Core package declaration: `define Package/<name>` with `PKGARCH:=all` inside
  that block.
- LuCI package declaration: top-level `LUCI_PKGARCH:=all` before including
  `luci.mk`.
- Verification commands:

```sh
make package/tgbot/compile V=s
make package/luci-app-tgbot/compile V=s
```

### 3. Contracts

- `tgbot/Makefile` must place `PKGARCH:=all` inside `define Package/tgbot`.
  A top-level assignment is not the package metadata contract used here.
- `luci-app-tgbot/Makefile` uses LuCI's `LUCI_PKGARCH:=all` convention.
- One source tree builds both generations. OpenWrt's build system maps the
  architecture-independent declaration differently by package format:
  - APK metadata: `arch: noarch`; filenames do not carry an `_all` suffix.
  - IPK metadata: `Architecture: all`; filenames end in `_all.ipk`.
- Output-directory names such as `bin/packages/x86_64/...` identify the SDK
  repository bucket and do not override package metadata.

### 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| `PKGARCH:=all` is outside `Package/tgbot` | Reject in review; move it into the package block |
| Core package APK reports a CPU architecture | Build verification fails |
| Core package IPK is not `Architecture: all` | Build verification fails |
| APK filename lacks `_all` but metadata is `noarch` | Valid |
| APK and IPK source files differ | Release verification fails |
| Exact target SDK is unavailable | Record format/source compatibility only; require a target-router smoke test |

### 5. Good / Base / Bad Cases

- Good: both SDK builds succeed, APK metadata is `noarch`, IPK metadata is
  `all`, and installed file manifests match.
- Base: only one package generation is requested; its native metadata is still
  inspected rather than inferred from the Makefile.
- Bad: treating an APK filename or its `bin/packages/<arch>` directory as proof
  that the package is CPU-specific.

### 6. Tests Required

- Build the core and LuCI packages in one APK SDK and one IPK SDK.
- Assert the native metadata architecture, dependencies, conffiles, ownership,
  and file modes.
- Assert `/etc/config/tgbot` is mode `0600` and remains a conffile.
- Compare installed file lists across both formats.
- Keep real-router installation as a separate gate when the matching firmware
  SDK cannot be reproduced.

### 7. Wrong vs Correct

#### Wrong

```make
PKGARCH:=all

define Package/tgbot
  TITLE:=Telegram bot
endef
```

#### Correct

```make
define Package/tgbot
  TITLE:=Telegram bot
  PKGARCH:=all
endef
```

For a LuCI package, keep the framework-specific declaration:

```make
LUCI_PKGARCH:=all
include $(TOPDIR)/feeds/luci/luci.mk
```
