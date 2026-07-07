# Status
Updated: 2026-07-07

## State
Installer + Status tab confirmed working on a live router (rockchip/aarch64, 25.12.4).
**New, NOT yet hardware-tested:** SOCKS5 proxy install (`--proxy`), the Bridges tab
(list/apply, in-app fetch, info), tor bridge integration via `tail_include`, and
`obfs4proxy` as a base dep. Nothing committed/pushed yet — owner triggers commits.

## Done
- 2026-07-06 — structure, `.ai/` docs, stubs, git init.
- 2026-07-07 — MVP: install.sh, backend lib, rpcd plugin, CLI, Status page. Live-install
  fixes: IPv4 (+fallback), feed preflight, apk retries, green summary, `uninstall`.
  English-only user text. Pushed through VERSION 0.3.0.
- 2026-07-07 — VERSION 0.4.0: (1) `--proxy`/`TORWRT_PROXY` — whole install through a
  SOCKS5 proxy (curl shim for apk; verified before any change; needs curl present).
  (2) Bridges tab + backend: get_config/set_config/get_bridges, bridges stored b64 in
  UCI, applied to tor via `/etc/tor/torwrt.conf` + `tor.conf.tail_include`.
  (3) In-app bridge fetch from moat `circumvention/builtin` (obfs4/snowflake/meek-azure),
  optional SOCKS5. (4) Info block: website CAPTCHA, email, telegram. obfs4proxy is a dep.

## Recent fixes
- 0.4.1 — bridges.js had a stray `)` → view failed to parse (blank tab). Added
  scripts/jsbal.py to catch that class before commit.
- 0.4.2 — "Get bridges" failed with "unreachable" on the live router: the bridge-fetch
  curl lacked `-4` (this router's IPv6 is broken; check() had `-4`, get_bridges didn't).
  Added `-4`, real curl-exit-code error messages, and `ca-bundle` as a conditional dep.

## Verify on the router (this release)
1. `torwrt uninstall` then reinstall to get obfs4proxy + new files (or just re-run installer).
2. Proxy install: `sh install.sh --proxy socks5://HOST:PORT` on a box without tor/curl —
   proxy verified first; apk pulls through it; clean abort if the proxy is dead.
3. Bridges tab: paste an obfs4 bridge, enable, Save & apply → `logread -e Tor` shows it
   using the bridge; Status tab shows Bridges = enabled. Confirm `/tmp/torrc` has the
   `%include /etc/tor/torwrt.conf` line and `uci show tor.conf` has the tail_include.
4. "Get bridges" (obfs4) with and without a SOCKS5 proxy → lines appear, "Add" fills the
   textarea. (Endpoint shape verified from a dev box; the jshn parse is untested on ash.)
5. Uninstall removes the tail_include + /etc/tor/torwrt.conf and restarts tor cleanly.

## Next steps
1. Commit + push (owner's call); fix hardware-test findings.
2. Traffic proxying design (transparent proxy via fw4/nftables).
3. More bridge options: snowflake/webtunnel transports, moat settings (per-country),
   optional CAPTCHA flow for unique bridges.
4. Release flow: tags, pin installer to a release instead of main.

## Open questions
- License.