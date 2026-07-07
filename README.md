# torwrt

Tor management for OpenWrt routers: one-command install and a LuCI web page
(**Services → Torwrt**) with daemon status, logs, Start/Stop/Restart buttons, a live
connectivity check through the Tor network, and bridge configuration.

The current version controls and monitors the tor daemon and configures bridges.
Routing traffic through Tor is planned for future releases.

## Requirements

- OpenWrt **25.12.4 or newer** (the installer checks and refuses older releases);
- internet access from the router;
- a few MB of free flash (the `tor`, `curl` and `obfs4proxy` packages are installed
  automatically).

## Install / update

SSH into the router and run:

```sh
wget -4 -O /tmp/torwrt-install.sh https://raw.githubusercontent.com/galex-hub/torwrt/main/install.sh
sh /tmp/torwrt-install.sh
```

The installer verifies the system, confirms that every required server is reachable
(and aborts cleanly, changing nothing, if one is not), installs missing packages,
copies only the runtime files to flash and wires up the LuCI page. Re-running the same
command updates torwrt; your `/etc/config/torwrt` settings are preserved.

### Installing through a SOCKS5 proxy

If GitHub or the OpenWrt package feeds are blocked on your network, route the whole
install through a SOCKS5 proxy (the proxy is verified before anything is installed):

```sh
sh /tmp/torwrt-install.sh --proxy socks5://127.0.0.1:1080
# with credentials:
sh /tmp/torwrt-install.sh --proxy socks5://user:pass@host:1080
```

This requires `curl` to be present already (OpenWrt's default `wget` cannot use SOCKS5).

## Usage

### Status tab
Daemon status and bootstrap progress, log viewer, control buttons and
"Check connection" (a live request through Tor showing the exit IP; up to ~15 s).

### Bridges tab
- **Your bridges** — paste one bridge line per row, tick "Use bridges" and press
  "Save & apply". torwrt writes the tor config and restarts the daemon.
- **Get bridges from Tor** — fetch built-in bridges straight from
  bridges.torproject.org; if that site is blocked, set a SOCKS5 proxy for the request.
  obfs4 works out of the box; snowflake/meek-azure need extra transport packages.
- **Other ways to get bridges** — the CAPTCHA website, email (`bridges@torproject.org`,
  body `get transport obfs4`, from Gmail/Riseup) and Telegram (`@GetBridgesBot`).

### CLI
`torwrt status | logs | start | stop | restart | check | bridges | version`
Settings live in `/etc/config/torwrt`.

## Uninstall

```sh
torwrt uninstall
```

Removes torwrt completely (service, web page, config, and the tor bridge integration).
The tor daemon and the installed packages are left untouched; to remove tor as well:
`/etc/init.d/tor stop && apk del tor`.

## Notes

- If the menu item does not show up right away, hard-refresh the LuCI page (Ctrl+F5).
- After a firmware upgrade (sysupgrade), run the installer again.

---
For developers and AI agents: [AGENTS.md](AGENTS.md) → [.ai/](.ai/)
