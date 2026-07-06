# LuCI app anatomy (OpenWrt 25.12)

LuCI is client-side JavaScript (since 19.07): no server-side templates, no Lua.
A LuCI app = JS view(s) + menu JSON + ACL JSON + (for custom backend calls) an rpcd plugin.

## Files
| Path | Purpose |
|---|---|
| /usr/share/luci/menu.d/luci-app-\<x\>.json | menu node, e.g. path `admin/services/torwrt` → view |
| /usr/share/rpcd/acl.d/luci-app-\<x\>.json | which ubus objects/methods a UI session may call |
| /www/luci-static/resources/view/\<x\>/*.js | the page(s), served as-is (no build step) |
| /usr/libexec/rpcd/\<name\> | backend script; ubus object name = file name (ours: `luci.torwrt`) |

## rpcd plugin protocol (shell)
- Executable script; rpcd invokes it two ways:
  - `script list` → print JSON describing methods + arg types: `{"status":{},"check":{}}`
  - `script call <method>` → JSON args on stdin, JSON result on stdout.
- JSON in shell via jshn: `. /usr/share/libubox/jshn.sh`
  (`json_init`, `json_add_string`, `json_dump`; `json_load`, `json_get_var`).
- After adding/changing a plugin or ACL: `/etc/init.d/rpcd restart`.
- Smoke test as root: `ubus call luci.torwrt status '{}'`.

## JS view essentials
- Header lines: `'use strict'; 'require view'; 'require rpc'; 'require poll'; 'require ui';`
- Backend call: `var callStatus = rpc.declare({ object: 'luci.torwrt', method: 'status' });`
- Page: `return view.extend({ load() {...}, render(data) {...} });` DOM via global `E(tag, attrs, children)`.
- Auto-refresh: `poll.add(fn, seconds)`. Notifications: `ui.addNotification(null, E('p', msg))`.
- Future config pages: `form.Map('torwrt')` edits UCI over ubus — needs a uci grant in the ACL.

## Gotchas
- Menu/ACL are cached: `rm -f /tmp/luci-indexcache*; rm -rf /tmp/luci-modulecache/`,
  restart rpcd, then hard-reload the browser (Ctrl+F5).
- The plugin file must be executable, otherwise the ubus object silently never
  appears — debug with `ubus list | grep torwrt`.
- ACL is enforced per session: a method absent from acl.d fails in the UI with
  permission denied even though `ubus call` works fine as root.
- Views run in the browser: keep them dumb; anything needing root goes through the rpcd plugin.
- Keep rpcd methods fast; slow operations (tor connectivity check) must enforce their own
  timeout well under the rpc timeout, and report partial results instead of hanging.

## Dev loop against a real router
scp changed files to their router paths → clear caches (above) → hard-reload the page.
