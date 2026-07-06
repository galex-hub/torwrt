# Conventions

## Shell code
- Shebang `#!/bin/sh`; busybox-ash-compatible POSIX only (forbidden constructs: [openwrt.md](openwrt.md)).
- Lint: `shellcheck -s dash <file>` must be clean (dash = closest dialect to ash).
- `install.sh` uses `set -eu`. The lib, CLI and rpcd plugin run with at most `set -u`:
  lib functions use return codes as data, `-e` would abort mid-JSON.
- Naming: functions `snake_case`; shared lib functions prefixed `twrt_`; globals `TORWRT_*`.
- Errors: fail loud and early — `die() { echo "torwrt: $*" >&2; exit 1; }`.
- Installer and CLI actions must be idempotent (re-run = repair/update, never breaks).
- Comments in code: English, only for non-obvious constraints.
- **All user-facing text is English only** — LuCI UI strings, installer/CLI output,
  README. Never mix languages.

## LuCI JS / JSON
- JS: LuCI idioms only (see [luci.md](luci.md)); `'use strict';` first line; tabs.
- menu.d / acl.d: strict JSON (no comments, no trailing commas), tabs.

## Files
- **LF line endings only** (enforced via .gitattributes). CRLF silently breaks ash
  scripts. Dev machine is Windows — never bypass this.
- UTF-8 without BOM.
- Executable bit can't be set on Windows: run `git update-index --chmod=+x <file>`
  for every new script under `files/` and for `install.sh`.

## Workflow
- Work proceeds in small agreed steps; design is discussed before implementation.
  Do not implement ahead of the current step.
- Git: commit/push only when the owner explicitly asks. Commit messages: plain and
  descriptive, **no AI/agent attribution** (no Co-Authored-By trailers etc.).
- After each step: update [status.md](status.md) (state / done / next / questions).
- Versioning: bump `VERSION` (semver) when behavior changes; `0.x` until first release.
