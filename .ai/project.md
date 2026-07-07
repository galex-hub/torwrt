# Project

**torwrt** — OpenWrt service that manages the stock `tor` package: installs it,
supervises the daemon, configures the connection to it and (later) traffic through it.
Ships with a LuCI web UI under **Services → Torwrt**.

## Scope
Done:
- Self-install via one command (`install.sh`): installs tor, curl, obfs4proxy, torwrt,
  the LuCI app. Optional `--proxy` routes the whole install through a SOCKS5 proxy.
- LuCI **Services → Torwrt**, tab **Status**: daemon status, logs, start/stop/restart,
  "check connection" (web request through tor).
- LuCI tab **Bridges**: paste/enable a bridge list (applied to tor), fetch built-in
  bridges in-app from bridges.torproject.org (optional SOCKS5 proxy), and info on the
  website/email/telegram bridge channels.

Future (the skeleton must take these without rewriting the base — see
[architecture.md](architecture.md) design principles):
- Transparent proxying of selected traffic through tor.
- More tor connection settings from the UI (ports, snowflake/webtunnel transports,
  per-country bridge recommendations via the moat settings API, CAPTCHA bridge flow).

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
| 2026-07-07 | **All user-facing text is English** (README, UI, installer/CLI output) | owner's call after live test: no RU/EN mixing |
| 2026-07-07 | Downloads prefer IPv4 (`-4`) with automatic fallback to system default | broken IPv6 stalls fetches, but IPv4-only must not brick installs where it is unavailable; installer probes and picks |
| 2026-07-07 | Installer changes nothing until connectivity to every required resource is confirmed | no half-installed state, ever |
| 2026-07-07 | `--proxy` install routes everything through curl+SOCKS5 (uclient-fetch can't do SOCKS); requires curl present | reach GitHub/feeds from censored networks; verified before any change |
| 2026-07-07 | Bundle `obfs4proxy` as a base dep | bridges are a core feature; obfs4 must work out of the box |
| 2026-07-07 | tor config via package `tail_include`, managed file `/etc/tor/torwrt.conf` | package-blessed, isolated, uninstall-clean; never touch stock torrc |
| 2026-07-07 | Bridges stored base64 in `torwrt.main.bridges_b64` | multi-line/whitespace-safe in UCI; survives updates; removed on uninstall |
| 2026-07-07 | In-app "get bridges" = moat `circumvention/builtin` (no CAPTCHA), not the /bridges/ CAPTCHA page | reliable in an embedded UI; CAPTCHA/email/telegram offered as info links for unique bridges |
