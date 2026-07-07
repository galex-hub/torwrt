# Architecture

## Design principles (the skeleton for the future)
- **Single source of logic**: everything real lives in `/usr/lib/torwrt/common.sh`
  (`twrt_*` functions). rpcd plugin and CLI are thin dispatchers over it.
- **UI never runs commands**: LuCI JS talks only to ubus object `luci.torwrt`.
  New feature = lib function + ubus method (+ ACL entry) + UI element;
  existing pieces are extended, not rewritten.
- **tor lifecycle via the stock `/etc/init.d/tor`**: the tor package already handles
  procd, user separation and torrc; torwrt drives it, never replaces or forks it.
- **tor CONFIG via the package's own include mechanism**: torwrt writes one managed
  fragment `/etc/tor/torwrt.conf` and registers it once as `tor.conf.tail_include`
  in `/etc/config/tor`; the tor init regenerates `/tmp/torrc` with our `%include`.
  We never edit the stock torrc. (openwrt.md → tor package.)
- **One status shape** (JSON below) consumed by UI and CLI alike; extend by adding keys.

## Repo layout
```
AGENTS.md      entry pointer -> .ai/
.ai/           agent docs (this folder)
install.sh     bootstrap installer — the only file the user downloads manually
files/         mirrors the router filesystem 1:1 (files/etc/... -> /etc/...)
scripts/       dev-only helpers (lint, release); never shipped to the router
tests/         tests; never shipped
VERSION        current version, single line
```

## files/ -> router map
| Repo path (under files/) | Router path | Role |
|---|---|---|
| etc/init.d/torwrt | /etc/init.d/torwrt | no-op placeholder by design (future: fw wiring); tor runs under stock init |
| etc/config/torwrt | /etc/config/torwrt | UCI config (options below) |
| usr/bin/torwrt | /usr/bin/torwrt | CLI: status/logs/start/stop/restart/check/version/uninstall |
| usr/lib/torwrt/common.sh | /usr/lib/torwrt/common.sh | shared lib — all logic |
| usr/libexec/rpcd/luci.torwrt | /usr/libexec/rpcd/luci.torwrt | rpcd plugin = ubus object `luci.torwrt` |
| usr/share/luci/menu.d/luci-app-torwrt.json | same | LuCI menu: Services → Torwrt, tabs Status + Bridges |
| usr/share/rpcd/acl.d/luci-app-torwrt.json | same | ACL for the ubus methods |
| www/luci-static/resources/view/torwrt/overview.js | same | Status tab (status/logs/buttons/check) |
| www/luci-static/resources/view/torwrt/bridges.js | same | Bridges tab (list/apply, in-app fetch, info) |

Menu: parent `admin/services/torwrt` is `firstchild`; two leaf views (`overview`
order 10, `bridges` order 20) render as tabs. Installer also writes
/usr/lib/torwrt/VERSION (from repo VERSION), and /etc/tor/torwrt.conf at runtime.

## UCI config (`torwrt.main`)
| Option | Default | Used for |
|---|---|---|
| socks_addr | 127.0.0.1 | tor SOCKS host for the connectivity check |
| socks_port | 9050 | tor SOCKS port |
| check_url | https://check.torproject.org/api/ip | connectivity check endpoint (returns `{"IsTor":bool,"IP":"..."}`) |
| log_lines | 50 | lines returned by the `logs` method |
| bridges_enabled | 0 | whether bridges are applied to tor |
| bridges_b64 | (empty) | user's bridge lines, base64 (avoids UCI whitespace/newline issues) |

## ubus API contract (`luci.torwrt`)
Mirrored in the ACL file — change both together.

| Method | Access | Args | Returns |
|---|---|---|---|
| status | read | — | `{torwrt_version, tor_version, tor_installed, running, pid?, enabled, bootstrap(-1=unknown), bootstrap_msg, bridges_enabled}` |
| logs | read | — | `{log: string}` (last `log_lines` tor/torwrt syslog lines) |
| get_config | read | — | `{bridges_enabled:bool, bridges:string, obfs4_available:bool}` |
| start / stop / restart | write | — | fresh `status` JSON |
| check | write | — | ok `{ok:true,is_tor,ip,elapsed_s}` / fail `{ok:false,error,elapsed_s}` |
| set_config | write | `enabled:bool, bridges:string` | fresh `get_config` JSON (stores, writes torrc fragment, restarts tor) |
| get_bridges | write | `proxy:string, transport:string` | ok `{ok:true,transport,bridges:string}` / fail `{ok:false,error}` |

Implementation notes:
- running = `pidof tor`; enabled = `/etc/init.d/tor enabled`; bootstrap = last
  "Bootstrapped N%" line in `logread` (approximation: -1 when rotated out of the buffer).
- check = `curl -4 --socks5-hostname` (DNS resolves through tor too; IPv4-only per
  project rule), 12 s cap — safely under rpcd/LuCI rpc timeouts; curl exit codes mapped.
- get_bridges = POST to `bridges.torproject.org/moat/circumvention/builtin`
  (flat `{obfs4:[...],snowflake:[...],meek-azure:[...],...}`), optional SOCKS5 via
  `curl -x socks5h://…`. Returns built-in bridges for the chosen transport; no CAPTCHA.
- set_config → `twrt_bridges_apply`: writes /etc/tor/torwrt.conf (UseBridges 1,
  ClientTransportPlugin obfs4 when obfs4 lines + /usr/bin/obfs4proxy present, Bridge
  lines), ensures the tail_include, restarts tor. Disabled/empty → neutral fragment.
- tor version cached in /tmp/torwrt.torver (status is polled every 5 s by the UI).

## Components
- **install.sh** — self-contained (runs before anything is installed). Flow:
  parse args (`--proxy`) → root/OpenWrt/version/clock checks → `setup_download`
  (proxy mode: require curl, normalize to `socks5h://…`, verify proxy reaches the
  feed before touching anything; else direct) → tarball into /tmp (tmpfs): via
  curl+proxy, or wget `-4` with fallback to system default (`NET_FLAGS`) → if deps
  (tor, curl, obfs4proxy; checked by binary) missing, probe downloads.openwrt.org
  and **abort cleanly before any system change** when unreachable → `apk` with
  retries under a PATH-interposed `wget` wrapper (proxy mode: a curl+socks shim that
  translates apk's wget calls; else wget+`NET_FLAGS`) → copy `files/` tree to `/`
  (existing /etc/config/torwrt preserved; previous version read first) → chmod →
  ensure tor enabled+running → enable torwrt, restart rpcd, clear LuCI caches →
  green SUCCESS summary ("installed" vs "updated OLD -> NEW").
  Env: `TORWRT_BRANCH`, `TORWRT_FORCE=1`, `TORWRT_PROXY`.
  Sysupgrade: only /etc/config/* survives; after firmware upgrade re-run the installer.
- **LuCI views** — `overview.js` (Status tab): status table + action buttons +
  check-result + log `<pre>`, polls every 5 s. `bridges.js` (Bridges tab): "Your
  bridges" (enable + textarea + Save & apply via set_config), "Get bridges from Tor"
  (transport + optional SOCKS5 proxy → get_bridges → append to list), and an info
  block (website/email/telegram channels).
- **Uninstall** (`torwrt uninstall`) also removes the tail_include and
  /etc/tor/torwrt.conf and restarts tor; tor/curl/obfs4proxy packages stay installed.

All components implemented; the bridges feature is not yet hardware-tested — see [status.md](status.md).
