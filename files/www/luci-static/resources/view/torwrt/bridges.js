'use strict';
'require view';
'require rpc';
'require ui';
'require dom';

// Services -> Torwrt -> Bridges. Thin client of ubus object "luci.torwrt".
// Contract: .ai/architecture.md. Three parts: your own bridge list, in-app
// retrieval of bridges from Tor (optionally via a SOCKS5 proxy), and pointers
// to the other official ways to obtain bridges.

var callGetConfig = rpc.declare({
	object: 'luci.torwrt',
	method: 'get_config'
});

var callSetConfig = rpc.declare({
	object: 'luci.torwrt',
	method: 'set_config',
	params: [ 'enabled', 'bridges' ]
});

var callGetBridges = rpc.declare({
	object: 'luci.torwrt',
	method: 'get_bridges',
	params: [ 'proxy', 'transport' ]
});

function byId(id) { return document.getElementById(id); }

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		return L.resolveDefault(callGetConfig(), {});
	},

	// --- part 2: save & apply the user's own bridge list ---
	handleApply: function() {
		var enabled = byId('twrt-br-enabled').checked;
		var text = byId('twrt-bridges').value;
		ui.showModal(_('Applying bridges'), [
			E('p', { 'class': 'spinning' }, _('Writing config and restarting Tor...'))
		]);
		return callSetConfig(enabled, text).then(function(cfg) {
			ui.hideModal();
			if (cfg && cfg.bridges_enabled && !cfg.obfs4_available)
				ui.addNotification(null, E('p', _('Bridges saved, but obfs4proxy is not installed — obfs4 bridges will not work. Re-run the installer to add it.')));
			else
				ui.addNotification(null, E('p', _('Bridges saved and applied. Tor is restarting; check the Status tab.')), 'info');
		}).catch(function(e) {
			ui.hideModal();
			ui.addNotification(null, E('p', _('Failed to apply bridges: ') + e));
		});
	},

	// --- part 3: fetch bridges from Tor, optionally through a SOCKS5 proxy ---
	handleFetch: function() {
		var proxy = byId('twrt-br-proxy').value.trim();
		var transport = byId('twrt-br-transport').value;
		var out = byId('twrt-br-fetched');
		dom.content(out, E('em', {}, _('Requesting bridges from bridges.torproject.org...')));
		return callGetBridges(proxy, transport).then(function(res) {
			res = res || {};
			if (res.ok && res.bridges) {
				dom.content(out, [
					E('textarea', {
						'id': 'twrt-br-result',
						'rows': 5,
						'style': 'width:100%; font-family:monospace',
						'readonly': true
					}, res.bridges),
					E('div', { 'style': 'margin-top:.4em' }, [
						E('button', {
							'class': 'btn cbi-button cbi-button-apply',
							'click': ui.createHandlerFn(this, 'handleAppend')
						}, _('Add these to my bridges'))
					])
				]);
			} else {
				dom.content(out, E('div', { 'style': 'color:#c33' },
					_('Could not get bridges: ') + (res.error || _('unknown error'))));
			}
		}.bind(this)).catch(function(e) {
			dom.content(out, E('div', { 'style': 'color:#c33' }, _('Request failed: ') + e));
		});
	},

	handleAppend: function() {
		var res = byId('twrt-br-result');
		if (!res) return;
		var ta = byId('twrt-bridges');
		var cur = ta.value.replace(/\s*$/, '');
		ta.value = (cur ? cur + '\n' : '') + res.value.replace(/\s*$/, '') + '\n';
		byId('twrt-br-enabled').checked = true;
		ta.scrollIntoView();
		ui.addNotification(null, E('p', _('Bridges added to the list above. Review, then press "Save & apply".')), 'info');
	},

	render: function(cfg) {
		cfg = cfg || {};

		var warnObfs4 = cfg.obfs4_available ? [] : [
			E('div', { 'class': 'cbi-value-description', 'style': 'color:#a80' },
				_('Note: obfs4proxy is not installed, so obfs4 bridges will not work. Re-run the installer to add it.'))
		];

		var yourBridges = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Your bridges')),
			E('div', { 'class': 'cbi-section-descr' },
				_('Paste one bridge line per row (as provided by Tor), then enable and apply. Leave empty and disabled for a direct connection to the Tor network.')),
			E('label', { 'class': 'cbi-value-title', 'style': 'display:block; margin:.3em 0' }, [
				E('input', {
					'id': 'twrt-br-enabled',
					'type': 'checkbox',
					'checked': cfg.bridges_enabled ? 'checked' : null
				}),
				' ', _('Use bridges')
			]),
			E('textarea', {
				'id': 'twrt-bridges',
				'rows': 6,
				'style': 'width:100%; font-family:monospace',
				'placeholder': 'obfs4 192.0.2.1:443 FINGERPRINT cert=... iat-mode=0'
			}, cfg.bridges || '')
		].concat(warnObfs4).concat([
			E('div', { 'style': 'margin-top:.6em' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-save important',
					'click': ui.createHandlerFn(this, 'handleApply')
				}, _('Save & apply'))
			])
		]));

		var getBridges = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Get bridges from Tor')),
			E('div', { 'class': 'cbi-section-descr' },
				_('Fetch built-in bridges directly from bridges.torproject.org. If that site is blocked on your network, route the request through a SOCKS5 proxy. Only obfs4 works out of the box; snowflake and meek-azure need extra transport packages.')),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Transport')),
				E('div', { 'class': 'cbi-value-field' }, [
					E('select', { 'id': 'twrt-br-transport', 'class': 'cbi-input-select' }, [
						E('option', { 'value': 'obfs4' }, 'obfs4 (' + _('recommended') + ')'),
						E('option', { 'value': 'snowflake' }, 'snowflake'),
						E('option', { 'value': 'meek-azure' }, 'meek-azure')
					])
				])
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('SOCKS5 proxy (optional)')),
				E('div', { 'class': 'cbi-value-field' }, [
					E('input', {
						'id': 'twrt-br-proxy',
						'type': 'text',
						'class': 'cbi-input-text',
						'style': 'width:100%',
						'placeholder': 'socks5://[user:pass@]host:port'
					}),
					E('div', { 'class': 'cbi-value-description' },
						_('Only used for this request to bridges.torproject.org.'))
				])
			]),
			E('div', {}, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, 'handleFetch')
				}, _('Get bridges'))
			]),
			E('div', { 'id': 'twrt-br-fetched', 'style': 'margin-top:.8em' })
		]);

		var info = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Other ways to get bridges')),
			E('div', { 'class': 'cbi-section-descr' },
				_('If the button above cannot reach Tor, request bridges through one of these channels and paste the result into "Your bridges".')),
			E('ul', {}, [
				E('li', {}, [
					E('strong', {}, _('Website: ')),
					E('a', { 'href': 'https://bridges.torproject.org/', 'target': '_blank', 'rel': 'noreferrer' },
						'https://bridges.torproject.org/'),
					' ', _('(solve the CAPTCHA to get unique bridges).')
				]),
				E('li', {}, [
					E('strong', {}, _('Email: ')),
					_('send a message to '),
					E('a', { 'href': 'mailto:bridges@torproject.org?body=get%20transport%20obfs4' },
						'bridges@torproject.org'),
					' ', _('with the text '),
					E('code', {}, 'get transport obfs4'),
					' ', _('in the body. Must be sent from a Gmail or Riseup address.')
				]),
				E('li', {}, [
					E('strong', {}, _('Telegram: ')),
					_('message '),
					E('a', { 'href': 'https://t.me/GetBridgesBot', 'target': '_blank', 'rel': 'noreferrer' },
						'@GetBridgesBot'),
					' ', _('and send '),
					E('code', {}, '/bridges'),
					' ', _('(or '), E('code', {}, '/obfs4'), _(' / '), E('code', {}, '/webtunnel'), ').')
				])
			])
		]);

		return E('div', {}, [
			E('h2', {}, _('Bridges')),
			E('div', { 'class': 'cbi-section-descr' },
				_('Bridges are unlisted Tor entry points that help connect where Tor is blocked. Configure them below.')),
			yourBridges,
			getBridges,
			info
		]);
	}
});
