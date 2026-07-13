# Frontend Quality Guidelines

## Scenario: Save And Apply A LuCI-Owned Service

### 1. Scope / Trigger

- Trigger: a LuCI action saves UCI-backed form values and then changes a
  service's `procd` state.
- This contract keeps the action limited to the `tgbot` configuration and makes
  service failures visible to the user.

### 2. Signatures

- LuCI sequence: `form.Map.save() -> luci.tgbot.apply()`.
- RPC result: `{ code: integer, output: string }`.
- Fixed helper: `/usr/libexec/tgbot/apply` with no user-supplied arguments.
- Persistent write: `uci commit tgbot` only.

### 3. Contracts

- The button handler must wait for `this.map.save()` before invoking the fixed
  `luci.tgbot.apply` RPC method.
- The RPC method may execute only `/usr/libexec/tgbot/apply`; the ACL must not
  expose a generic shell or arbitrary command arguments.
- When enabled, the helper loads and strictly validates UCI, commits only
  `tgbot`, enables the init script, and restarts it in that order.
- When disabled, invalid device data must not prevent shutdown. The helper
  stops the service, commits only `tgbot`, and disables the init script.
- Commit, enable, restart, and disable failures return a nonzero `code` and a
  bounded `output` message. A failed prerequisite prevents later state changes.
- The LuCI notification uses `code == 0` for success and refreshes service state
  after an apply attempt.

### 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Form validation fails | Do not call the apply RPC |
| Enabled config fails strict validation | Do not commit, enable, or restart |
| `uci commit tgbot` fails | Return failure; do not enable or restart |
| Init enable fails | Return failure; do not restart |
| Init restart fails | Return failure after the attempted enable |
| Disabled config contains an invalid WOL device | Still stop, commit `tgbot`, and disable |
| Init disable fails | Return failure and report it |

### 5. Good / Base / Bad Cases

- Good: valid enabled settings are saved, only `tgbot` is committed, the
  service is enabled/restarted, and the displayed state refreshes.
- Base: disabled settings contain an incomplete device; the bot still stops and
  is disabled safely.
- Bad: calling a global configuration apply operation that commits unrelated
  UCI packages before restarting `tgbot`.

### 6. Tests Required

- Assert disabled apply logs exactly `stop` then `disable` and commits exactly
  `commit tgbot`.
- Assert commit failure prevents enable/restart.
- Assert enable failure prevents restart.
- Assert restart and disable failures propagate as nonzero results.
- Syntax-check the LuCI view and validate the RPC menu/ACL JSON.
- On a router, save a value through LuCI, reload the page, and verify the service
  state and persisted `/etc/config/tgbot` value.

### 7. Wrong vs Correct

#### Wrong

```javascript
handleApply() {
	return this.callApply();
}
```

This races the service action against unsaved form data and leaves commit scope
undefined.

#### Correct

```javascript
handleApply() {
	return this.map.save()
		.then(() => this.callApply())
		.then((result) => this.refreshStatus().then(() => result));
}
```

The fixed helper then owns the authoritative `uci commit tgbot` and ordered
service transition.
