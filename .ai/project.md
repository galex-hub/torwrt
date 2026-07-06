# Project

**torwrt** — OpenWrt service that manages the stock `tor` package: installs it,
supervises the daemon, configures the connection to it and (later) traffic through it.
Ships with a LuCI web UI under **Services → Torwrt**.

## Scope
MVP (current target):
- Self-install via one command (`install.sh`): installs tor, torwrt itself, the LuCI app.
- LuCI page **Services → Torwrt**: connection status, log block,
  start / stop / restart buttons, "check connection" (web request through tor).
- No traffic proxying yet — this is the base.

Future (the skeleton must take these without rewriting the base — see
[architecture.md](architecture.md) design principles):
- Transparent proxying of selected traffic through tor.
- Configuring the tor connection from the UI (ports, bridges / pluggable transports).

## Targets
- OpenWrt **>= 25.12.4** only. No older releases (installer must check and refuse).
- Any router architecture: pure POSIX shell + LuCI JS, no compiled code.

## Delivery model
- Repo: `git@github.com:galex-hub/torwrt.git` (https://github.com/galex-hub/torwrt).
- Not shipped as an apk/ipk package. User runs on the router:
  `wget -4 -O /tmp/torwrt-install.sh https://raw.githubusercontent.com/galex-hub/torwrt/main/install.sh && sh /tmp/torwrt-install.sh`
- `install.sh` bootstraps everything and installs all missing deps (tor, curl, ...);
  exact flow: [architecture.md](architecture.md) → Components.
- Update = re-run installer (idempotent; user config preserved).

## Key decisions
| Date | Decision | Why |
|---|---|---|
| 2026-07-06 | Pure POSIX sh (busybox ash), no compiled code | works on any arch, no build infra |
| 2026-07-06 | Repo mirrors router FS under `files/` | install = copy tree; mapping is obvious |
| 2026-07-06 | Single-command install from GitHub raw | simplest UX on a router |
| 2026-07-06 | Docs in English | token economy for agents |
| 2026-07-06 | Manage the stock `tor` package, never bundle/fork it | upstream security updates keep coming via apk |
| 2026-07-06 | All logic behind ubus object `luci.torwrt`; UI/CLI are thin clients | one backend, N frontends; features add methods, base never rewritten |
| 2026-07-07 | Install source = branch tarball (codeload), extracted in /tmp (tmpfs) | one HTTP request; docs/tests never touch flash — only `files/` + VERSION are copied to `/` |
| 2026-07-07 | Existing `/etc/config/torwrt` is never overwritten on update | user settings survive updates |
| 2026-07-07 | tor lifecycle via stock `/etc/init.d/tor`, no own supervisor | package init already handles procd/user/torrc; no conflicts, no duplication |
| 2026-07-07 | Classic shell rpcd plugin (not ucode) | plugin sources the shared shell lib directly — single source of logic |
| 2026-07-07 | User README in Russian | primary audience; commands are copy-paste anyway |
| 2026-07-07 | **All downloads are IPv4-only** (`wget -4`, `curl -4`) — hard rule for any future network call | half-configured IPv6 on routers stalls/breaks fetches; IPv4 is the dependable path |
