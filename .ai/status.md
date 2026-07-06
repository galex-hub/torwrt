# Status
Updated: 2026-07-07

## State
**MVP implemented end-to-end, not yet tested on hardware.** Installer, backend lib,
rpcd plugin, CLI and the LuCI page are all real code now. Owner will test on a live
router (install + UI). Nothing committed/pushed yet — owner triggers commits explicitly.

## Done
- 2026-07-06 — project structure, `.ai/` docs, stub files, git init.
- 2026-07-07 — scope confirmed; LuCI skeleton; ubus contract; doc rules relaxed.
- 2026-07-07 — install.sh implemented (version gate, tmpfs tarball, apk deps,
  config-preserving update, LuCI cache handling); remote galex-hub/torwrt added.
- 2026-07-07 — working MVP: lib `common.sh` (status/logs/ctl/check via stock
  /etc/init.d/tor), rpcd plugin, CLI, LuCI overview page (poll 5s, action buttons,
  connectivity check), RU user README. VERSION 0.2.0.

## Verify on the router (first live test)
1. Install command from README on OpenWrt >= 25.12.4.
2. `ubus list | grep luci.torwrt` — object present; `ubus call luci.torwrt status '{}'`.
3. tor logs actually land in syslog as ` Tor[pid]:` (bootstrap parsing depends on it;
   if the tag differs, fix the grep in `twrt_logs_text`/`twrt_bootstrap_read`).
4. LuCI page appears under Services after hard refresh; buttons + check work.
5. Re-run installer: config preserved, no errors (idempotency).

## Next steps
1. Commit + push (owner's call), owner tests on router, fix findings.
2. Traffic proxying design (transparent proxy via fw4/nftables, per-device/all-LAN policy).
3. Tor connection config from UI (ports; bridges/pluggable transports).
4. Release flow: tags, pin installer to a release instead of main.

## Open questions
- License.
