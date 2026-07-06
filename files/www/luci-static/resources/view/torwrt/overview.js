'use strict';
'require view';
'require rpc';
'require poll';
'require ui';
'require dom';

// Services -> Torwrt. Thin client of ubus object "luci.torwrt"
// (backend: /usr/libexec/rpcd/luci.torwrt); contract: .ai/architecture.md.

var callStatus = rpc.declare({
	object: 'luci.torwrt',
	method: 'status'
});

var callLogs = rpc.declare({
	object: 'luci.torwrt',
	method: 'logs',
	expect: { log: '' }
});

var callStart   = rpc.declare({ object: 'luci.torwrt', method: 'start' });
var callStop    = rpc.declare({ object: 'luci.torwrt', method: 'stop' });
var callRestart = rpc.declare({ object: 'luci.torwrt', method: 'restart' });
var callCheck   = rpc.declare({ object: 'luci.torwrt', method: 'check' });

function statusRow(label, value) {
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'width': '33%' }, label),
		E('td', { 'class': 'td left' }, value)
	]);
}

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		return Promise.all([
			L.resolveDefault(callStatus(), {}),
			L.resolveDefault(callLogs(), '')
		]);
	},

	renderStatusTable: function(st) {
		var stateCell;
		if (!st.tor_installed)
			stateCell = E('span', { 'style': 'color:#c33; font-weight:bold' },
				_('tor is not installed — re-run the installer'));
		else if (st.running)
			stateCell = E('span', { 'style': 'color:#2a2; font-weight:bold' },
				_('running') + (st.pid ? ' (PID ' + st.pid + ')' : ''));
		else
			stateCell = E('span', { 'style': 'color:#c33; font-weight:bold' }, _('stopped'));

		var bootstrap;
		if (!st.running)
			bootstrap = '—';
		else if (st.bootstrap >= 0)
			bootstrap = st.bootstrap + '%' + (st.bootstrap_msg ? ' — ' + st.bootstrap_msg : '');
		else
			bootstrap = _('unknown (no bootstrap lines in the log buffer)');

		return E('table', { 'class': 'table' }, [
			statusRow(_('Tor daemon'), stateCell),
			statusRow(_('Bootstrap'), bootstrap),
			statusRow(_('Autostart'), st.enabled ? _('enabled') : _('disabled')),
			statusRow(_('Tor version'), st.tor_version || '—'),
			statusRow(_('Torwrt version'), st.torwrt_version || '—')
		]);
	},

	updateStatus: function(st) {
		var box = document.getElementById('twrt-status');
		if (box) dom.content(box, this.renderStatusTable(st));
	},

	updateLogs: function(text) {
		var pre = document.getElementById('twrt-log');
		if (!pre) return;
		pre.textContent = text || _('(empty — no tor lines in the system log yet)');
		pre.scrollTop = pre.scrollHeight;
	},

	refresh: function() {
		var self = this;
		return Promise.all([
			L.resolveDefault(callStatus(), null),
			L.resolveDefault(callLogs(), null)
		]).then(function(data) {
			if (data[0]) self.updateStatus(data[0]);
			if (data[1] != null) self.updateLogs(data[1]);
		});
	},

	// start/stop/restart return fresh status JSON right away
	handleAction: function(fn, ev) {
		var self = this;
		return fn().then(function(st) {
			self.updateStatus(st);
			return L.resolveDefault(callLogs(), null).then(function(text) {
				if (text != null) self.updateLogs(text);
			});
		}).catch(function(e) {
			ui.addNotification(null, E('p', _('Command failed: ') + e));
		});
	},

	renderCheckResult: function(res) {
		var box = document.getElementById('twrt-check-result');
		if (!box) return;
		var el;
		var took = (res.elapsed_s != null) ? ' (' + res.elapsed_s + 's)' : '';
		if (res.ok && res.is_tor)
			el = E('div', { 'style': 'color:#2a2; font-weight:bold' },
				'✔ ' + _('Connected through Tor.') + ' ' + _('Exit IP') + ': ' + (res.ip || '?') + took);
		else if (res.ok)
			el = E('div', { 'style': 'color:#a80; font-weight:bold' },
				'⚠ ' + _('Request succeeded, but the exit is not recognized as Tor.') +
				' IP: ' + (res.ip || '?') + took);
		else
			el = E('div', { 'style': 'color:#c33; font-weight:bold' },
				'✘ ' + _('Check failed') + ': ' + (res.error || '?') + took);
		dom.content(box, el);
	},

	handleCheck: function(ev) {
		var self = this;
		var box = document.getElementById('twrt-check-result');
		if (box) dom.content(box, E('em', {}, _('Checking — a request through Tor can take ~15 seconds...')));
		return callCheck().then(function(res) {
			self.renderCheckResult(res || { ok: false, error: _('empty response') });
		}).catch(function(e) {
			self.renderCheckResult({ ok: false, error: String(e) });
		});
	},

	render: function(data) {
		var st = data[0] || {};
		var log = data[1] || '';
		var self = this;

		poll.add(function() { return self.refresh(); }, 5);

		return E('div', {}, [
			E('h2', {}, _('Torwrt')),
			E('div', { 'class': 'cbi-section-descr' },
				_('Tor management for OpenWrt. This base version controls and monitors the tor daemon; traffic routing comes in a later release.')),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Status')),
				E('div', { 'id': 'twrt-status' }, this.renderStatusTable(st)),
				E('div', { 'style': 'margin-top:1em' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': ui.createHandlerFn(this, 'handleAction', callStart)
					}, _('Start')), ' ',
					E('button', {
						'class': 'btn cbi-button cbi-button-remove',
						'click': ui.createHandlerFn(this, 'handleAction', callStop)
					}, _('Stop')), ' ',
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, 'handleAction', callRestart)
					}, _('Restart')), ' ',
					E('button', {
						'class': 'btn cbi-button cbi-button-action important',
						'click': ui.createHandlerFn(this, 'handleCheck')
					}, _('Check connection'))
				]),
				E('div', { 'id': 'twrt-check-result', 'style': 'margin-top:0.8em' })
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Log')),
				E('pre', {
					'id': 'twrt-log',
					'style': 'max-height:24em; overflow:auto; font-size:12px; white-space:pre-wrap'
				}, log || _('(empty — no tor lines in the system log yet)'))
			])
		]);
	}
});
