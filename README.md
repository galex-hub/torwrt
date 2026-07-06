# torwrt

Tor management for OpenWrt routers: one-command install and a LuCI web page
(**Services → Torwrt**) with daemon status, logs, Start/Stop/Restart buttons and a
live connectivity check through the Tor network.

The current version is the base: it controls and monitors the tor daemon.
Routing traffic through Tor is planned for future releases.

## Requirements

- OpenWrt **25.12.4 or newer** (the installer checks and refuses older releases);
- internet access from the router;
- a few MB of free flash (the `tor` and `curl` packages are installed automatically).

## Install / update

SSH into the router and run:

```sh
wget -4 -O /tmp/torwrt-install.sh https://raw.githubusercontent.com/galex-hub/torwrt/main/install.sh
sh /tmp/torwrt-install.sh
```

The installer verifies the system, confirms that every required server is reachable
(and aborts cleanly, changing nothing, if one is not), installs missing packages,
copies only the runtime files to flash and wires up the LuCI page.

Re-running the same command updates torwrt; your `/etc/config/torwrt` settings
are preserved.

## Usage

- **LuCI → Services → Torwrt** — daemon status and bootstrap progress, log viewer,
  control buttons and "Check connection" (a live request through Tor showing the
  exit IP; takes up to ~15 seconds).
- CLI: `torwrt status | logs | start | stop | restart | check | version`.
- Settings: `/etc/config/torwrt` (SOCKS address/port, check URL, log lines).

## Uninstall

```sh
torwrt uninstall
```

Removes torwrt completely (service, web page, config). The tor daemon and the
installed packages are left untouched; to remove tor as well:
`/etc/init.d/tor stop && apk del tor`.

## Notes

- If the menu item does not show up right away, hard-refresh the LuCI page (Ctrl+F5).
- After a firmware upgrade (sysupgrade), run the installer again.

---
For developers and AI agents: [AGENTS.md](AGENTS.md) → [.ai/](.ai/)
