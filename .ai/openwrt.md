# OpenWrt >= 25.12 platform notes

Baseline: OpenWrt 25.12 (kernel 6.12). Everything below assumes this baseline.

## Package manager: apk, NOT opkg
- 25.12 replaced opkg with apk (Alpine Package Keeper). `opkg` does not exist on target.
- Commands: `apk update`, `apk add <pkg>`, `apk del <pkg>`, `apk info -e <pkg>` (is installed?).
- Package names mostly match old opkg names.
- apk downloads by spawning `wget` (its errors reference wget) and has **no IPv4-only
  and no SOCKS switch**. install.sh interposes a PATH wget wrapper: direct mode adds
  the net flags; proxy mode replaces wget with a curl+socks shim (uclient-fetch cannot
  do SOCKS5 — verified; redsocks/curl are the only options). Feed connectivity can be
  flaky (a live test failed once with the wrapper then passed) → preflight the feed URL
  and retry apk; do not assume the wrapper alone fixes feed errors.

## tor package (net/tor)
- `apk add tor` installs the **full** variant (bridges/relay). `tor-basic` has **no
  bridge support** — do not depend on it. Binary: `/usr/sbin/tor`; runs as user `tor`.
- Init `/etc/init.d/tor` generates `/tmp/torrc` from UCI `/etc/config/tor` (section
  `tor.conf`) and starts `tor -f /tmp/torrc`. Default torrc = `/etc/tor/torrc`; it sets
  `Log notice syslog` (so our syslog-based status/logs/bootstrap parsing works).
- **Add config the blessed way**: `uci add_list tor.conf.tail_include='/path.conf'`,
  `uci commit tor`, restart tor → init appends `%include /path.conf`. Never edit the
  stock torrc. torwrt uses this with `/etc/tor/torwrt.conf`.
- obfs4: OpenWrt package `obfs4proxy` → `/usr/bin/obfs4proxy` (provides obfs4).
  snowflake/meek/webtunnel need other binaries (not packaged the same way).
- Bridge config: `UseBridges 1` + `ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy`
  + `Bridge <line>` per bridge.

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
- `curl` (used for the connectivity check + bridge fetch) needs two things this router
  can't be assumed to have: **`-4`** (IPv6 is broken here — always pass it on direct
  fetches, like wget) and **`ca-bundle`** for TLS verification (installer adds it when
  /etc/ssl/certs/ca-certificates.crt is missing). A curl fetch that returns nothing is
  almost always one of these — surface `curl`'s exit code, don't just say "unreachable".
- No RTC: clock is wrong early at boot until NTP syncs -> TLS downloads can fail.
  Installer/updater must not assume correct time right after boot.
- Logs: write `logger -t torwrt "msg"`, read `logread -e torwrt`. No persistent logs by default.
- Survive sysupgrade: add paths to `/etc/sysupgrade.conf` (installer should do this).
- Flash is small and RAM-limited: avoid temp files, big deps; `/tmp` is tmpfs (RAM).
