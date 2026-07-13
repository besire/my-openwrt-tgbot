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

## Scenario: Deterministic BusyBox Shell Function Status

### 1. Scope / Trigger

- Trigger: adding or changing a BusyBox `ash` function whose purpose is an
  action such as initialization, cleanup, or iteration and for which doing no
  work is a valid success case.
- This contract prevents a loop's final test or an unmatched glob from leaking
  status `1` into a caller such as the daemon startup path.

### 2. Signatures

- Action functions return `0` after all required work completes, including a
  valid no-op, and return nonzero only for a documented failure.
- `wol_reset_confirmation_state()` returns `0` when the confirmation directory
  is ready and contains no stale regular files, including when it was already
  empty; it returns nonzero when the directory cannot be prepared.

### 3. Contracts

- End action functions with an explicit `return 0` when their final compound
  command does not itself define the function's public result.
- Treat an unmatched quoted-prefix glob such as `"$dir"/*` as a normal loop
  input: POSIX shells retain the literal pattern when no file matches.
- Predicate and lookup functions may intentionally return nonzero for
  "not found"; their names, callers, and tests must make that contract clear.
- Callers that gate service startup must assert the action function's status
  rather than assume its side effects imply success.

### 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Cleanup directory is empty | Return `0`; daemon startup continues |
| Cleanup directory contains stale regular files | Remove them and return `0` |
| Required runtime directory cannot be created | Return nonzero; startup fails |
| Glob has no matches and the loop test returns `1` | Do not expose that status |
| Predicate does not find a requested value | Return nonzero by documented design |

### 5. Good / Base / Bad Cases

- Good: startup clears existing confirmation files and continues.
- Base: a fresh boot has an empty confirmation directory and startup still
  returns success.
- Bad: a cleanup function ends immediately after `[ -f "$file" ] && rm ...`
  inside a glob loop, so a fresh installation enters a `procd` crash loop.

### 6. Tests Required

- Invoke every startup action through an asserted status path.
- Exercise cleanup with an empty directory and assert status `0`.
- Exercise cleanup with at least one matching file and assert the intended side
  effect and status.
- Run the regression suite with both the host shell and BusyBox `ash`.

### 7. Wrong vs Correct

#### Wrong

```sh
reset_state() {
    for file in "$state_dir"/*; do
        [ -f "$file" ] && rm -f "$file"
    done
}
```

#### Correct

```sh
reset_state() {
    for file in "$state_dir"/*; do
        [ -f "$file" ] && rm -f "$file"
    done
    return 0
}
```
