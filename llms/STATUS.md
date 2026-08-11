# STATUS — 2026-08-10

## Done & validated
- CLI commands: `inspect`, `install`, `uninstall`, `list`, `brew`, `gui` (stub),
  `self-install`, `version` — single file `bin/repkger` (bash 3.2-compatible).
- Full round-trip validated on **GameMaker 2024.14.4.222.pkg**:
  - `inspect`: title/component/identifier/version/install-location/BOM(17,480)/scripts shown.
  - `install --home /tmp/repkger-home-test`: `~/Applications`-equivalent merge,
    33 stale refs rewritten, 1 bundle ad-hoc re-signed, 9,327 files recorded.
  - `install` (default `$HOME`): `~/Applications/GameMaker.app` created.
  - `uninstall`: 8,235 files + 1,093 dirs removed; tree back to 1 entry.
- Paths with spaces parse correctly (awk `-F'\t'` fix).
- pkg sha256 verified `8cbd33a9…cc7f` (matches upstream homebrew cask).

## Broken / needs attention (CRITICAL)
- **Scope bug in rewrite + codesign passes**: they operate on
  `INSTALLED_TARGETS` (the whole mapped install-location dir), so a real
  install into `$HOME` rewrote `/Applications`/`/Library`/`/bin`/`/usr/local`
  references inside OTHER apps in `~/Applications` and ad-hoc re-signed 10
  bundles (original vendor signatures lost for Suspicious Package, Platypus,
  Autodesk Fusion, FamiStudio).
- Damage reversal is NOT yet done (survey was interrupted mid-run). See
  `llms.md` → "TODO first" for the exact reverse-rewrite commands and the
  re-sign / reinstall guidance.
- The fix is to run rewrite+resign only on the package's own files:
  rewrite over the **record file list**, resign over `MERGED_DIRS` only.

## Housekeeping notes
- `~/Downloads/repkger-test/` holds the downloaded pkg + an expanded copy
  (`expanded/`) — free to delete; re-downloadable.
- `~/.repkger/records/` holds the real-install record for GameMaker.
- The `Repkger.app` GUI does NOT exist yet — only the `gui` CLI stub.
- No git repo existed for this project before this commit; this push is the first.
