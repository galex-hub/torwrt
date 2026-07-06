# Architecture

## Design principles (the skeleton for the future)
- **Single source of logic**: everything real lives in `/usr/lib/torwrt/common.sh`
  (`twrt_*` functions). rpcd plugin and CLI are thin dispatchers over it.
- **UI never runs commands**: LuCI JS talks only to ubus object `luci.torwrt`.
  New feature = lib function + ubus method (+ ACL entry) + UI element;
  existing pieces are extended, not rewritten.
- **tor lifecycle via the stock `/etc/init.d/tor`**: the tor package already handles
  procd, user separation and torrc; torwrt drives it, never replaces or forks it.
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
| usr/bin/torwrt | /usr/bin/torwrt | CLI: status/logs/start/stop/restart/check/version |
| usr/lib/torwrt/common.sh | /usr/lib/torwrt/common.sh | shared lib — all logic |
| usr/libexec/rpcd/luci.torwrt | /usr/libexec/rpcd/luci.torwrt | rpcd plugin = ubus object `luci.torwrt` |
| usr/share/luci/menu.d/luci-app-torwrt.json | same | LuCI menu: Services → Torwrt |
| usr/share/rpcd/acl.d/luci-app-torwrt.json | same | ACL for the ubus methods |
| www/luci-static/resources/view/torwrt/overview.js | same | UI page (status/logs/buttons/check) |

Installer also writes /usr/lib/torwrt/VERSION (from repo VERSION).

## UCI config (`torwrt.main`)
| Option | Default | Used for |
|---|---|---|
| socks_addr | 127.0.0.1 | tor SOCKS host for the connectivity check |
| socks_port | 9050 | tor SOCKS port |
| check_url | https://check.torproject.org/api/ip | connectivity check endpoint (returns `{"IsTor":bool,"IP":"..."}`) |
| log_lines | 50 | lines returned by the `logs` method |

## ubus API contract (`luci.torwrt`)
Mirrored in the ACL file — change both together. All methods take no args.

| Method | Access | Returns |
|---|---|---|
| status | read | `{torwrt_version, tor_version, tor_installed:bool, running:bool, pid?:int, enabled:bool, bootstrap:int(-1=unknown), bootstrap_msg}` |
| logs | read | `{log: string}` (last `log_lines` tor/torwrt syslog lines) |
| start / stop / restart | write | fresh `status` JSON (UI updates from the response) |
| check | write | ok: `{ok:true, is_tor:bool, ip, elapsed_s}`; fail: `{ok:false, error, elapsed_s}` |

Implementation notes:
- running = `pidof tor`; enabled = `/etc/init.d/tor enabled`; bootstrap = last
  "Bootstrapped N%" line in `logread` (approximation: -1 when rotated out of the buffer).
- check = `curl -4 --socks5-hostname` (DNS resolves through tor too; IPv4-only per
  project rule), 12 s cap — safely under rpcd/LuCI rpc timeouts; curl exit codes
  mapped to human messages.
- tor version cached in /tmp/torwrt.torver (status is polled every 5 s by the UI).

## Components
- **install.sh** — self-contained (runs before anything is installed). Flow:
  root/OpenWrt/version/clock checks → branch tarball into /tmp (tmpfs) →
  deps (tor, curl): skipped entirely when binaries already present, otherwise
  `apk update && apk add` under a PATH-interposed `wget -4` wrapper → copy `files/` tree to `/`
  (existing /etc/config/torwrt preserved) → chmod executables → ensure tor
  enabled+running → enable torwrt, restart rpcd, clear LuCI caches.
  Env overrides: `TORWRT_BRANCH`, `TORWRT_FORCE=1` (skip version gate).
  Sysupgrade: only /etc/config/* survives by default; after a firmware upgrade the
  user re-runs the installer (code paths are deliberately not in sysupgrade.conf).
- **LuCI view** (overview.js) — status table + action buttons (ui.createHandlerFn
  spinners) + check-result line + log `<pre>`; polls status+logs every 5 s.

All MVP components are implemented; nothing is tested on hardware yet — see [status.md](status.md).
