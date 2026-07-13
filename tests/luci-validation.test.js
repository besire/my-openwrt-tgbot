'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'luci-app-tgbot',
	'htdocs', 'luci-static', 'resources', 'view', 'tgbot', 'config.js'), 'utf8');
const rpcDeclarations = [];
const model = new Function('view', 'rpc', '_', source)(
	{ extend: (definition) => definition },
	{ declare: (options) => {
		rpcDeclarations.push(options);
		return () => {};
	} },
	(message) => message
);

const rpcByMethod = Object.fromEntries(rpcDeclarations.map((options) =>
	[ options.method, options ]));

assert.deepEqual(rpcByMethod.status.expect, { '': { running: false } },
	'status RPC must preserve its complete result object');
assert.deepEqual(rpcByMethod.test.expect, { '': { code: 1, output: '' } },
	'test RPC must preserve code and output in one result object');
assert.deepEqual(rpcByMethod.apply.expect, { '': { code: 1, output: '' } },
	'apply RPC must preserve code and output in one result object');

assert.equal(model.validateAdminId('main', ''), true,
	'DynamicList container validation must accept its empty sentinel');
assert.equal(model.validateAdminId('main', '1083075748'), true,
	'a positive Telegram user ID must be accepted');
assert.equal(model.validateAdminId('main', '99999999999999999999'), true,
	'a 20-digit Telegram user ID must be accepted');
assert.notEqual(model.validateAdminId('main', '0'), true,
	'zero must be rejected');
assert.notEqual(model.validateAdminId('main', '01083075748'), true,
	'a leading-zero Telegram user ID must be rejected');
assert.notEqual(model.validateAdminId('main', '1083x75748'), true,
	'a nonnumeric Telegram user ID must be rejected');
assert.notEqual(model.validateAdminId('main', '999999999999999999999'), true,
	'a 21-digit Telegram user ID must be rejected');

console.log('LuCI view tests passed.');
