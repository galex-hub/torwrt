# Status
Updated: 2026-07-07

## State
**MVP installed successfully on a live router** (rockchip/aarch64, 25.12.4) after the
network fixes below. UI functionality feedback pending from the owner.

## Done
- 2026-07-06 — project structure, `.ai/` docs, stub files, git init.
- 2026-07-07 — scope confirmed; LuCI skeleton; ubus contract; doc rules relaxed.
- 2026-07-07 — install.sh implemented (version gate, tmpfs tarball, apk deps,
  config-preserving update, LuCI cache handling); remote galex-hub/torwrt added.
- 2026-07-07 — working MVP: lib `common.sh` (status/logs/ctl/check via stock
  /etc/init.d/tor), rpcd plugin, CLI, LuCI overview page (poll 5s, action buttons,
  connectivity check), RU user README. VERSION 0.2.0. First commit pushed.
- 2026-07-07 — all downloads forced to IPv4 (`wget -4` / `curl -4`, incl. README
  command); recorded as a hard project rule. VERSION 0.2.1.
- 2026-07-07 — first live test (rockchip/aarch64): tarball fetch OK, but `apk update`
  failed — apk spawns its own wget without `-4`. Fix: deps skipped when binaries
  already present + apk runs under a PATH-interposed `wget -4` wrapper. VERSION 0.2.2.
- 2026-07-07 — second live test: apk failed once more even with the wrapper (manual
  `wget -4` to the feed worked), then **install succeeded** — feed connectivity is
  flaky. Installer hardened: connectivity preflight for every required resource
  before touching the system (clean abort otherwise), IPv4 preferred with automatic
  fallback to system default, apk retries, green SUCCESS summary with
  installed-vs-updated versions. Added `torwrt uninstall` (clean removal, tor/curl
  left untouched). All user-facing text switched to English (README rewritten).
  VERSION 0.3.0.

## Verify on the router (remaining)
1. LuCI page under Services: status/bootstrap correct, logs shown, buttons + check work
   (tor must log to syslog as ` Tor[pid]:` for bootstrap parsing — if the tag differs,
   fix the grep in `twrt_logs_text`/`twrt_bootstrap_read`).
2. Re-run installer: reports "updated OLD -> NEW", config preserved, green summary.
3. `torwrt uninstall`: menu entry gone, files gone, tor still running; reinstall works.

## Next steps
1. Commit + push (owner's call), owner tests on router, fix findings.
2. Traffic proxying design (transparent proxy via fw4/nftables, per-device/all-LAN policy).
3. Tor connection config from UI (ports; bridges/pluggable transports).
4. Release flow: tags, pin installer to a release instead of main.

## Open questions
- License.
