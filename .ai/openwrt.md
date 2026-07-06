# OpenWrt >= 25.12 platform notes

Baseline: OpenWrt 25.12 (kernel 6.12). Everything below assumes this baseline.

## Package manager: apk, NOT opkg
- 25.12 replaced opkg with apk (Alpine Package Keeper). `opkg` does not exist on target.
- Commands: `apk update`, `apk add <pkg>`, `apk del <pkg>`, `apk info -e <pkg>` (is installed?).
- Package names mostly match old opkg names.

## Shell: busybox ash
- POSIX sh only. Forbidden: arrays, `[[ ]]`, `function` keyword, `$'...'`,
  process substitution `<(...)`, `${var/pat/rep}` replacement.
- Allowed: `local`, `$(...)`, `${var#...}`/`${var%...}`, arithmetic `$(( ))`.
- Do not rely on `set -o pipefail` (availability varies by busybox build).

## Init: procd
- File `/etc/init.d/<name>`, shebang `#!/bin/sh /etc/rc.common`, `USE_PROCD=1`.
- Implement `start_service()` using `procd_open_instance` .. `procd_close_instance`.
- Manage: `/etc/init.d/<name> start|stop|restart|enable|disable`; enable = symlink in `/etc/rc.d/`.

## Config: UCI
- Files in `/etc/config/<name>`, no shebang, `config <type> '<section>'` + `option k 'v'`.
- Access: `uci get torwrt.main.enabled`, `uci set ...`, `uci commit torwrt`.

## Firewall
- firewall4 / nftables (`fw4`). No iptables. Custom rules via uci firewall sections
  or includes; direct nft only if uci can't express it.

## Gotchas
- Download: `wget` on default images is uclient-fetch; HTTPS works out of the box.
  It supports `-4`/`-6`; the busybox wget applet does NOT support `-4` — torwrt
  relies on uclient-fetch (present in default images). Project rule: always `-4`.
- No RTC: clock is wrong early at boot until NTP syncs -> TLS downloads can fail.
  Installer/updater must not assume correct time right after boot.
- Logs: write `logger -t torwrt "msg"`, read `logread -e torwrt`. No persistent logs by default.
- Survive sysupgrade: add paths to `/etc/sysupgrade.conf` (installer should do this).
- Flash is small and RAM-limited: avoid temp files, big deps; `/tmp` is tmpfs (RAM).
