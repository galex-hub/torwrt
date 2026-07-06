# torwrt — docs index

Read only what your task needs. `project.md` + `status.md` are mandatory and short.

| Doc | Contents | Read when |
|---|---|---|
| project.md | Goal, scope (MVP/future), targets, delivery model, key decisions | always |
| status.md | Current state, next steps, open questions | always |
| architecture.md | Repo layout, repo→router file map, components, ubus API contract | touching code or file layout |
| openwrt.md | Platform facts: apk, procd, UCI, busybox ash, gotchas | writing code that runs on the router |
| luci.md | LuCI app anatomy: menu/ACL/rpcd plugin/JS views, dev workflow | touching the web UI or the rpcd backend |
| conventions.md | Shell/JS/JSON style, line endings, naming, workflow rules | writing code or docs |

## Doc rules
- English, terse. Tables/lists over prose. Length: whatever the content needs — zero fluff or filler.
- One fact lives in exactly one doc — link, never duplicate.
- Hard facts only (paths, commands, versions). No marketing.
- After meaningful work: update `status.md`. Touch other docs only when facts change.
