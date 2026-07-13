'use strict';
'require view';
'require form';
'require poll';
'require rpc';
'require uci';
'require ui';
'require tools.widgets as widgets';

return view.extend({
	callStatus: rpc.declare({
		object: 'luci.tgbot',
		method: 'status',
		expect: { running: false }
	}),

	callTest: rpc.declare({
		object: 'luci.tgbot',
		method: 'test',
		expect: { code: 1, output: '' }
	}),

	callApply: rpc.declare({
		object: 'luci.tgbot',
		method: 'apply',
		expect: { code: 1, output: '' }
	}),

	load() {
		return Promise.all([
			uci.load('tgbot'),
			L.resolveDefault(this.callStatus(), { running: false })
		]);
	},

	validateToken(sectionId, value) {
		const enabled = uci.get('tgbot', 'main', 'enabled') == '1';
		if (!value)
			return enabled ? _('A bot token is required while the service is enabled.') : true;
		return value.length <= 256 && /^[0-9]+:[A-Za-z0-9_-]+$/.test(value)
			? true : _('Enter a valid Telegram bot token.');
	},

	validateApiUrl(sectionId, value) {
		if (!value || value.length > 512 || !value.startsWith('https://'))
			return _('Enter an HTTPS Telegram Bot API base URL.');
		if (/[\s\x00-\x1f\x7f?#"\\]/.test(value))
			return _('The API URL must not contain whitespace, query, fragment, quote, or backslash characters.');
		const authority = value.substring(8).split('/')[0];
		const match = authority.match(/^([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]+))?$/);
		const host = match ? match[1] : '';
		const port = match && match[2] ? Number(match[2]) : 0;
		if (!match || host.length > 253 || host.includes('..') || host.includes('.-') || host.includes('-.') ||
			(match[2] && (port < 1 || port > 65535)))
			return _('The API URL authority is invalid.');
		return true;
	},

	validateAdminId(sectionId, value) {
		return /^[1-9][0-9]{0,19}$/.test(value)
			? true : _('Enter a positive numeric Telegram user ID.');
	},

	validateDeviceName(sectionId, value) {
		if (!value || /[\x00-\x1f\x7f]/.test(value) || new TextEncoder().encode(value).length > 48)
			return _('Enter a device name up to 48 bytes without control characters.');
		const duplicate = uci.sections('tgbot', 'device').some((section) =>
			section['.name'] != sectionId && section.name == value);
		return duplicate ? _('Device names must be unique.') : true;
	},

	handleTest() {
		return this.map.save().then(() => this.callTest()).then((result) => {
			ui.addNotification(null, E('p', {}, result.output || _('No response.')),
				result.code == 0 ? 'info' : 'error');
		});
	},

	handleApply() {
		return this.map.save().then(() => this.callApply()).then((result) => {
			ui.addNotification(null, E('p', {}, result.output || _('No response.')),
				result.code == 0 ? 'info' : 'error');
			return this.refreshStatus();
		});
	},

	refreshStatus() {
		return L.resolveDefault(this.callStatus(), { running: false }).then((status) => {
			this.running = status.running === true;
			const node = document.getElementById('tgbot-service-state');
			if (node) {
				node.textContent = this.running ? _('Running') : _('Stopped');
				node.className = this.running ? 'label notice success' : 'label notice warning';
			}
		});
	},

	render([config, status]) {
		let m, s, o;
		this.running = status.running === true;

		m = new form.Map('tgbot', _('Telegram Bot'),
			_('Configure private Telegram access to router status and Wake-on-LAN.'));
		this.map = m;

		s = m.section(form.NamedSection, 'main', 'bot', _('Service'));
		s.anonymous = true;

		o = s.option(form.DummyValue, '_service_state', _('Service status'));
		o.rawhtml = true;
		o.cfgvalue = () => E('span', {
			'id': 'tgbot-service-state',
			'class': this.running ? 'label notice success' : 'label notice warning'
		}, this.running ? _('Running') : _('Stopped'));

		o = s.option(form.Button, '_test_api', _('API connection'));
		o.inputtitle = _('Test connection');
		o.inputstyle = 'action';
		o.onclick = ui.createHandlerFn(this, 'handleTest');

		o = s.option(form.Button, '_apply_service', _('Apply service state'));
		o.inputtitle = _('Save and apply');
		o.inputstyle = 'apply';
		o.onclick = ui.createHandlerFn(this, 'handleApply');

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = o.disabled;

		o = s.option(form.Value, 'token', _('Bot token'));
		o.password = true;
		o.rmempty = true;
		o.validate = L.bind(this.validateToken, this);

		o = s.option(form.Value, 'api_base_url', _('Telegram API base URL'),
			_('The endpoint must preserve the standard /bot&lt;TOKEN&gt;/&lt;METHOD&gt; path layout.'));
		o.default = 'https://api.telegram.org';
		o.rmempty = false;
		o.validate = L.bind(this.validateApiUrl, this);

		o = s.option(form.DynamicList, 'admin_id', _('Administrator user IDs'),
			_('Only private chats from these exact numeric Telegram user IDs are accepted.'));
		o.rmempty = true;
		o.validate = L.bind(this.validateAdminId, this);

		o = s.option(form.Value, 'poll_timeout', _('Long polling timeout'));
		o.datatype = 'range(1,50)';
		o.default = '50';
		o.rmempty = false;

		s = m.section(form.NamedSection, 'main', 'bot', _('Status and reachability'));
		s.anonymous = true;

		o = s.option(form.DynamicList, 'status_interface', _('Status network interfaces'),
			_('UCI network names queried by the /status command.'));
		o.datatype = 'uciname';
		o.default = [ 'wan', 'wan6' ];
		o.rmempty = false;

		o = s.option(form.Value, 'wake_check_delay', _('Initial reachability delay'));
		o.datatype = 'range(0,120)';
		o.default = '5';
		o.rmempty = false;

		o = s.option(form.Value, 'wake_check_attempts', _('Reachability attempts'));
		o.datatype = 'range(1,20)';
		o.default = '6';
		o.rmempty = false;

		o = s.option(form.Value, 'wake_check_interval', _('Reachability interval'));
		o.datatype = 'range(1,60)';
		o.default = '5';
		o.rmempty = false;

		s = m.section(form.GridSection, 'device', _('Wake-on-LAN devices'),
			_('Every wake request requires a fresh Telegram confirmation.'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;
		s.nodescriptions = true;
		s.modaltitle = (sectionId) => {
			const name = uci.get('tgbot', sectionId, 'name');
			return name ? _('Edit device: %s').format(name) : _('Add device');
		};

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = o.enabled;
		o.editable = true;

		o = s.option(form.Value, 'name', _('Name'));
		o.rmempty = false;
		o.validate = L.bind(this.validateDeviceName, this);

		o = s.option(form.Value, 'mac', _('MAC address'));
		o.datatype = 'macaddr';
		o.rmempty = false;

		o = s.option(widgets.DeviceSelect, 'interface', _('Interface'));
		o.noaliases = true;
		o.noinactive = true;
		o.rmempty = false;

		o = s.option(form.Value, 'check_ip', _('Reachability IPv4 address'),
			_('Optional address checked after the magic packet is sent.'));
		o.datatype = 'ip4addr("nomask")';
		o.rmempty = true;

		poll.add(L.bind(this.refreshStatus, this), 5);
		return m.render();
	}
});
