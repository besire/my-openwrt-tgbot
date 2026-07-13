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

## Scenario: Validate LuCI Dynamic Lists

### 1. Scope / Trigger

- Trigger: assigning a custom `validate(sectionId, value)` function to a
  `form.DynamicList` option.
- LuCI validates both the text input used to add an item and the list's root
  container, so the callback does not always represent a stored list item.

### 2. Signatures

- Option: `form.DynamicList`.
- Callback: `validate(sectionId: string, value: string) -> true | string`.
- Observed LuCI 24.10 and 25.12 calls:
  - Item input validation: `value` is the entered item string.
  - Root-container revalidation: `value` is the empty-string sentinel `''`.

### 3. Contracts

- A custom DynamicList validator must accept `null` and `''` as framework
  sentinels. Required-list checks belong to the form state or authoritative
  backend validation, not the per-item callback.
- Every nonempty value must be validated as one list item. For `admin_id`, the
  accepted shape is `/^[1-9][0-9]{0,19}$/`.
- Accepting the empty sentinel must not weaken backend validation. Strict shell
  validation still requires at least one administrator before enabling or
  testing the bot.

### 4. Validation & Error Matrix

| Value / state | Required result |
| --- | --- |
| `''` or `null` from container revalidation | Return `true` |
| `1083075748` | Return `true` |
| `0` or a leading-zero ID | Return the field-specific error |
| Username, token, whitespace, or nondigit input | Return the field-specific error |
| More than 20 digits | Return the field-specific error |
| Enabled bot with no stored administrator IDs | Backend strict validation fails |

### 5. Good / Base / Bad Cases

- Good: a valid ID is added, the container revalidates with `''`, and the form
  saves the stored list value.
- Base: the optional list is empty while the bot is disabled; the form remains
  editable and the service stays stopped.
- Bad: applying the item regex directly to `''`, which marks the entire list
  invalid after a valid item was added.

### 6. Tests Required

- Load the actual LuCI view model and assert the validator accepts both the
  empty container sentinel and a representative valid ID.
- Assert zero, leading-zero, nondigit, and 21-digit values remain invalid.
- Run `node --check` on the view and `node tests/luci-validation.test.js`.
- On the target router, add a valid ID through the DynamicList control, save,
  reload, and verify the value persists.

### 7. Wrong vs Correct

#### Wrong

```javascript
validateAdminId(sectionId, value) {
	return /^[1-9][0-9]{0,19}$/.test(value) ? true : _('Invalid ID');
}
```

#### Correct

```javascript
validateAdminId(sectionId, value) {
	if (value == null || value === '')
		return true;
	return /^[1-9][0-9]{0,19}$/.test(value) ? true : _('Invalid ID');
}
```
