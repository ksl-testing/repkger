# repkger — LLM handoff doc (read this first)

> Written 2026-08-10. Purpose: let a **cacheless LLM** (or a human) pick up this
> project in ≤5 minutes. Everything below is the current truth; re-read files
> before editing (they may have changed).

## What this project is

A macOS tool that installs Apple installer `.pkg` files **without admin / sudo /
`installer` / the pkg GUI**. It re-targets every install path to somewhere the
current user can write (`~/Applications`, `~/Library`, `~/.local`, ...), keeps
world-writable locations (`/Users/Shared`) in place, rewrites stale absolute
path references inside installed files, records exactly what landed, and can
reverse it. It also inspects `.pkg` files the way *Suspicious Package* does
(components, BOM file lists, scripts, versions). A `brew` wrapper intercepts
`brew install --cask <name>` for casks that ship a `.pkg` (e.g. `gamemaker`)
and installs them rootlessly.

Origin: generalization of the CSP_Mac project's `install_portable.sh`
(`~/Documents/GitHub/CSP_Mac`), which did the same thing for one specific pkg.

## Repo layout

```
bin/repkger        # the whole CLI — single bash script (macOS bash 3.2 compatible)
README.md          # overview + quick start
llms.md            # THIS FILE — handoff
llms/STATUS.md     # detailed status + the open damage-reversal task
llms/ROADMAP.md    # GUI .app, brew integration, tap integration
NOTES.md           # dev notes: architecture, validated behavior, gotchas
```

## Status (2026-08-10)

### DONE + validated
- `bin/repkger` CLI: `inspect`, `install`, `uninstall`, `list`, `brew`, `gui`
  (stub), `self-install`, `version`.
- Validated end-to-end against **GameMaker-2024.14.4.222.pkg**
  (`~/Downloads/repkger-test/`): inspect shows correct components/BOM/scripts;
  install → `~/Applications/GameMaker.app` (9,327 files recorded, 33 files
  rewritten, 1 bundle ad-hoc re-signed); uninstall → fully reversed (8,235
  files + 1,093 dirs). pkg sha256 `8cbd33a9...` matches upstream cask.
- `--list-only` dry run works. Record/uninstall round-trip works
  (incl. paths with spaces after the `awk -F'\t'` fix).
- Known-good fixtures to re-test against (fast):
  - `~/Downloads/repkger-test/GameMaker-2024.14.4.222.pkg` (430 MB)
  - scratch home: `--home /tmp/repkger-home-test --yes` + `REPKGER_DATA=/tmp/repkger-data`

### CRITICAL UNRESOLVED — collateral damage in ~/Applications
The first real install (into `$HOME`) ran the **path-rewrite and codesign
passes over the ENTIRE `~/Applications` directory** instead of only the
package's own files, because `record_installed_targets()` adds the mapped
install-location dir (`$HOME_ROOT/Applications`) to `INSTALLED_TARGETS`, and
`cmd_install` passes `INSTALLED_TARGETS` to `rewrite_tree` / `resign_apps`.

Consequences on this machine (user `tpldih`):
- Files inside other apps in `~/Applications` had these strings rewritten:
  `/Applications` → `/Users/tpldih/Applications`, `/Library` → `/Users/tpldih/Library`,
  `/bin` → `/Users/tpldih/bin`, `/usr/local` → `/Users/tpldih/.local`, etc.
  Known-hit files (survey was INTERRUPTED — list incomplete):
  - `~/Applications/FamiStudio.app/Contents/MacOS/main.command`
  - `~/Applications/MacNdCheese Launcher.app/Contents/Resources/installer.sh`
  - `~/Applications/MacNdCheese Launcher.app/Contents/Resources/backend_server.py`
  - `~/Applications/MacNdCheese Launcher.app/Contents/Resources/oxrsys-runtime/oxrsys-runtime.toml`
  - `~/Applications/Remove Autodesk Fusion.app/Contents/MacOS/Remove Autodesk Fusion`
  - `~/Applications/Platypus.app/Contents/Resources/Documentation.html`
  - Freebuff.app (1 file), Suspicious Package.app (3 files),
    TPLDIH BootKit.app (18 files)
- 10 bundles were ad-hoc re-signed (original signatures lost for vendor-signed
  apps: Suspicious Package, Platypus, Autodesk Fusion, FamiStudio): the
  re-signed list was Remove Autodesk Fusion, FamiStudio, MacNdCheese Launcher,
  Platypus, Suspicious Package, Autodesk Fusion Service Utility, TPLDIH
  BootKit, Freebuff, **GameMaker (ours — keep)**, Autodesk Fusion.

#### TODO first (≤10 min): reverse the rewrite + re-sign
1. Re-run the full damage survey (interrupted before): grep all of
   `~/Applications` (excluding GameMaker.app) for the new-form prefixes:
   `/Users/tpldih/Applications`, `/Users/tpldih/Library`, `/Users/tpldih/bin`,
   `/Users/tpldih/.local`, `/Users/tpldih/.usr`, `/Users/tpldih/etc`,
   `/Users/tpldih/var`, `/Users/tpldih/opt`, `/Users/tpldih/sbin`.
2. For each hit file, reverse the transformation (order: longest/least-common
   prefixes first; all are distinct children of `/Users/tpldih/` so plain
   order works; handle binary plists via `plutil -convert xml1` before / back):
   ```
   perl -pi -e '
     s{/Users/tpldih/bin/}{/bin/}g;
     s{/Users/tpldih/sbin/}{/sbin/}g;
     s{/Users/tpldih/\.local/}{/usr/local/}g;
     s{/Users/tpldih/\.usr/}{/usr/}g;
     s{/Users/tpldih/etc/}{/etc/}g;
     s{/Users/tpldih/var/}{/var/}g;
     s{/Users/tpldih/opt/}{/opt/}g;
     s{/Users/tpldih/Applications/}{/Applications/}g;
     s{/Users/tpldih/Library/}{/Library/}g' FILE
   ```
   CAUTION: only reverse files that were actually rewritten (contain new-form
   strings). Verify shebangs are back to `#!/bin/...`.
3. Re-sign affected bundles (they are ad-hoc now anyway):
   `codesign --force --deep --sign - "PATH.app"` for each affected .app
   (NOT GameMaker.app — it is intentionally rewritten).
4. Consider `brew reinstall --cask suspicious-package platypus` (and famistudio
   from ksl-testing/tap) to restore genuine vendor signatures.

#### TODO second: fix the scope bug in bin/repkger (do before ANY real install)
- `record_installed_targets()` → should add the **merged** dirs (already tracked
  in `MERGED_DIRS`), not the whole mapped install-location dir.
- `cmd_install` post-merge passes must operate ONLY on the package's own files:
  - rewrite: iterate the **record file list** (paths that exist), not
    `grep -r` over the mapped dir.
  - resign: `resign_apps "${MERGED_DIRS[@]}"` (already merged-scope for
    dequarantine — mirror that for rewrite + resign).
- Re-validate with the scratch flow, then with a real `~/` install and confirm
  no other apps' files change (`git diff`-style check of mtimes / grep before).

## How to test (fast loop)

```bash
R=~/Documents/GitHub/repkger/bin/repkger
$R inspect  ~/Downloads/repkger-test/GameMaker-2024.14.4.222.pkg
$R install  ~/Downloads/repkger-test/GameMaker-2024.14.4.222.pkg --list-only
rm -rf /tmp/repkger-home-test /tmp/repkger-data
REPKGER_DATA=/tmp/repkger-data $R install ~/Downloads/repkger-test/GameMaker-2024.14.4.222.pkg --home /tmp/repkger-home-test --yes
REPKGER_DATA=/tmp/repkger-data $R list
REPKGER_DATA=/tmp/repkger-data $R uninstall com.yoyogames.gms2 --yes
find /tmp/repkger-home-test | wc -l     # expect 1 (only the root)
```

## Key implementation facts (gotchas learned)

- `pkgutil --expand-full` **refuses a pre-existing destination dir** ("File
  exists") — the script must `rm -rf` the target first.
- macOS BSD `sed` has **no `\b`** — attribute regexes must not use it.
- `lsbom` output is **tab-separated with spaces allowed inside the path** —
  parse with `awk -F'\t'`, never default whitespace splitting.
- BOM entries include `._*` AppleDouble files that `pkgutil --expand-full`
  folds into xattrs — they never exist on disk; the record skips non-existent
  entries (and uninstall works off the record).
- bash 3.2 (macOS system bash): `set -u` + empty array expansion errors —
  use `${arr[@]+"${arr[@]}"}` everywhere.
- EXIT traps must reference **global** vars, not function-locals (locals are
  out of scope when the trap fires).
- Don't combine `xattr ... && say` under `set -e` (silent exit on failure);
  use `if ... then ... else warn`.
- `installer manual:` in brew cask DSL does NOT run anything (just prints);
  `installer script:` runs as the current user with `reset_uid` — that's the
  rootless cask hook. `depends_on formula:` is valid in casks.
- GameMaker pkg facts: single component `com.yoyogames.gms2` v2024.14.4.222,
  install-location `/Applications`, preinstall is entirely commented out,
  postinstall only chmods `/Users/Shared/GameMakerStudio2` dirs + relaunches.
  Upstream cask sha256 `8cbd33a9a92ed60ebd53734413b33afdeb8c677326ada0c80971e9f91555cc7f`.

## Next milestones (details in llms/ROADMAP.md)

1. Fix scope bug + reverse ~/Applications damage (above).
2. GUI `Repkger.app` — AppleScript droplet (`on open droppedItems`), osacompile
   build script, embedded CLI in Resources, document types for .pkg.
3. Brew integration: `repkger brew` already coded; add `Formula/repkger.rb` +
   `Casks/repkger.rb` + rootless `Casks/gamemaker.rb` to
   `ksl-testing/homebrew-tap` (workspace:
   `~/homebrew/Library/Taps/ksl-testing/homebrew-tap`).
4. `gh repo create ksl-testing/repkger --private --source=. --push` (this
   repo is local-only as of writing; push when ready).
