# AGENTS.md — session learnings for repkger

Terse, hard-won facts that aren't recoverable from the code or README/NOTES.
Read these before touching the matching areas.

## Testing (test/roundtrip.sh)

- `check "desc" <cmd>` redirects `<cmd>`'s stdout to /dev/null — a pipe placed
  *outside* the call (`check … lsbom | grep`) feeds grep empty input and dies
  under `set -euo pipefail` with a misleading "ok printed then exit 1". Capture
  output into a variable first (e.g. `BOM5="$(lsbom …)"; check … grep -q <<<"$BOM5"`).
- "No raw ref" assertions must not use `grep -F '/Applications/…'`: the mapped
  path `$H5/Applications/…` contains that substring. Match path-root positions
  only: `grep -E '(^|[[:space:]])/Applications/MiniApp.app'`.
- Fixture `postinstall` carries stale `/Applications`, `/Library`, `/usr/local`
  refs deliberately — phase 5 verifies the redone pkg's embedded script is
  home-mapped. Don't "simplify" them away.

## pkg internals / tools

- `xar -xf <pkgbuild-made.pkg> Scripts` extracts the Scripts member as a
  **gzip-compressed cpio file**, not a dir: inspect with
  `gunzip -dc Scripts | cpio -id`. (Same for any pkgbuild output.)
- A redone pkg's install-location is only in `PackageInfo`
  (`install-location="…"`); `lsbom` shows BOM paths **relative** to that root
  (`./Applications/…`), so destination assertions must grep PackageInfo.
- `pkgbuild --scripts` refuses unknown script names and arch-suffixed variants
  (`postinstall-e`) — the fallback in `cmd_bom_redo` retries without `--scripts`.

## Architecture decisions (deliberate, not bugs)

- Payload rewrite and embedded-script rewrite use **different pairs sets**:
  `script_rewrite_pairs` drops `/usr`, `/bin`, `/sbin` (and keeps all user
  `--map`s) so `#!/bin/sh` and `/usr/bin/env` in redone-pkg scripts still
  resolve to real system tools. Don't "unify" them.
- `--only` pruning: unmatched dirs that merely *contain* a requested prefix
  must still be descended into — recursion condition is
  `has_boundary || only_below(vc)`, and only the emit/merge branch requires
  `only_match(vc)`. A naive top-level prune drops the whole subtree.
- `bom_redo_leaves` emits `src<TAB>mapped<TAB>virtual-path` — the third field
  is what callers should display (basename alone shows `Shared` for
  `/Users/Shared`).
