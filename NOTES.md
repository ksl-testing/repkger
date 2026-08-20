# NOTES — dev notes for repkger

## Architecture (single-file bash CLI + AppleScript GUI)

1. **Expand**: `pkgutil --expand-full <pkg> <dir>` extracts payloads into
   directories (`<comp>.pkg/Payload/` as a dir), leaves `Bom`, `Scripts/`,
   `PackageInfo`. Fallback: `xar -xf` + manual `gunzip|cpio` (or `pbzx`).
   A single-component pkg expands with `PackageInfo` at the ROOT (no
   `Contents/Packages/`).
2. **Map** (`map_path`): user `--map` (longest prefix) → keep-if-writable
   (top-level dir `-w` check) → always-keep (`/Users/Shared`, `/tmp`) →
   home-rooted defaults (`/Applications`→`$ROOT/Applications`,
   `/Library`→`$ROOT/Library`, `/usr/local`→`$ROOT/.local`, `/usr`→`$ROOT/.usr`,
   `/etc`,`/var`,`/opt`,`/bin`,`/sbin`→under `$ROOT`, `/private*`→stripped).
3. **Merge** (`merge_tree`): walks the payload tree with virtual absolute
   paths (normalized so install-location `/` never yields `//`); remaps only
   where a mapping boundary lies *below* the current node; dittos whole
   subtrees otherwise. `MERGED_DIRS` + `MAPPED_LOCS` collected here.
4. **Installed-file list** (`build_installed_files`): BOM-driven
   `INSTALLED_FILES` (`dst<TAB>typ<TAB>mode<TAB>uidgid<TAB>size`, existing
   entries only). This list scopes EVERYTHING below — rewrite, resign, and the
   record — so the tool never touches pre-existing content in mapped dirs.
5. **Dequarantine** (`dequarantine`/`strip_quarantine`): `xattr -dr
   com.apple.quarantine` on merged dirs + mapped install-location dirs
   (recursive), plus a non-recursive strip of each one's parent dir (a
   quarantined parent re-infects copies — Gatekeeper inheritance). If `-d`
   fails while the attr is present, clear all xattrs (`-c`/`-cr`). Never walks
   `/` or `$HOME_ROOT` recursively.
6. **Rewrite** (`rewrite_installed`/`rewrite_one`): ONE perl pass;
   longest-prefix alternation, path-root boundary, whole reference token
   consumed as a verbatim tail → no nested/overlapping re-matches
   (`/usr/local/bin` → `~/.local/bin`, `/private/var` → `~/var`),
   idempotent. Binary plists via `plutil -convert xml1` → rewrite → back.
7. **Sign** (`resign_installed`): verify/re-sign only `.app` dirs from the
   package's own list (fallback: `find` over merged dirs if no BOM dirs);
   `_CodeSignature` artifacts are swept into the record afterwards.
8. **Record**: `~/.repkger/records/<name>-<ver>-<sha8>/record.tsv` — header
   (pkg, sha, name, ver, installed_at, home_root, user_maps),
   `component<TAB>id<TAB>ver<TAB>loc`, `script<TAB>id<TAB>name<TAB>md5`,
   `file<TAB>dst<TAB>typ<TAB>mode<TAB>uidgid<TAB>size`. `uninstall` deletes
   files deepest-first, rmdir recorded dirs, then the mapped install-location
   dirs (only if empty).
9. **brew wrapper**: parses `brew info --cask X --json=v2`; if url is a
   `.pkg`/`.mpkg`, downloads to `~/.repkger/downloads`, verifies sha256,
   calls `install`; else execs real brew. **`--rpkg`** (v0.3.0) FORCES the
   rootless strategy for a pkg cask and never falls through: an unsupported
   artifact dies with an error instead of silently running brew's `installer`
   (which needs sudo). `--rpkg` also handles **`.dmg`/`.zip` containers with a
   `.pkg`/`.mpkg` inside**: download + sha256 verify, then mount
   (`hdiutil attach -nobrowse -readonly -mountpoint` to a temp dir) or unzip
   (`unzip`, `ditto -x -k` fallback), `find -maxdepth 4` for the inner pkg,
   rootless-install it, then `cask_cleanup` (EXIT trap) detaches the volume /
   drops the extract dir. Extension detection strips `?#` from the URL (also
   used for the download filename). The `brew()` shim installed by
   `repkger self-install` lets you type `brew install --cask --rpkg gamemaker`
   — it strips `--rpkg`, routes to `repkger brew`, and passes every other brew
   call straight through (bash + zsh compatible; guarded when repkger is
   missing). Cask detection handles `--cask` before or after the name.
   Roundtrip phase 4 covers: direct pkg, zip-with-pkg, dmg-with-pkg (incl.
   "volume detached" check), unsupported artifact dies, and brew never sees a
   non-`info` call in any case.
10. **GUI** (`gui/Repkger.applescript` + `scripts/make-app.sh`):
    osacompile droplet; embedded CLI in `Contents/Resources/repkger`
    (`cliPath()` finds it via `path to me`); `on open` drop handler →
    Inspect dialog (`inspect --files 20` + Full Report via TextEdit) or
    Install (`install --home $HOME --yes`); `on run` mode chooser is a
    **`choose from list`** (NOT buttons — `display dialog` allows at most 3
    buttons, the old 4-button chooser died with -50 at runtime) with a
    **multi-select** open dialog (`choosePkgs`) — each chosen/dropped .pkg is
    processed independently in a loop with per-file `(i of n)` progress
    notifications (AppleScript has no optional params — `doInstall` takes
    `(p, homeRoot, dataDir, progressLabel)`; every call site passes all 4);
    **`--rpkg` passthrough (v0.3.0)**: mode chooser gains "Install a brew cask
    (--rpkg, rootless)" (`doCaskPrompt` → `doCaskInstall(caskName, dataDir)`,
    runs `repkger brew install --cask --rpkg <name>`) + headless
    `--cask <name> [--data dir]`;
    headless `--install <pkg> [--home dir] [--data dir]` and
    `--inspect <pkg>` — drive via `osascript`, the droplet binary ignores
    argv;    `com.ksl-testing.repkger` (default), `.pkg`/`.mpkg` doc types, ad-hoc
    signed; version stamped from `bin/repkger`'s `REPKGER_VERSION` by
    make-app.sh. **Name-configurable via env vars** (v0.4.0): APP_NAME,
    DISPLAY_NAME, BUNDLE_ID, INSTALL_DIR — no script edits needed.
    Primary build: `APP_NAME=tpl-unwrapper` at `~/applications/`.
    Plugin build: `APP_NAME="Noren Hodoki"` at `~/applications/noren/`.
    After install: `lsregister -f` clears cached Gatekeeper rejections.
11. **Release pipeline + brew tap** (`.github/workflows/release.yml`,
    `scripts/update-tap.sh`, `tap/*.rb` templates): push to `main` (source
    paths) or `workflow_dispatch` → test (fixture round-trip + GUI smoke) →
    build assets (`repkger`, `repkger-<v>.zip`, `Repkger-<v>.app.zip`,
    `SHA256SUMS.txt`) → publish/refresh release `v<REPKGER_VERSION>` (delete +
    recreate keeps one canonical release + stable `releases/download/...`
    URLs) → update `Formula/repkgr.rb` (+ `repkger.rb` alias) in
    `ksl-testing/homebrew-tap` (create-on-first-run via `gh repo create`,
    needs `TAP_TOKEN` PAT; skips gracefully without it).
13. **BOM redo** (`repkger bom-redo <pkg> [--home] [--out] [--map]`,
    v0.3.0): redoes the package BOM to the mapped no-sudo locations and
    repacks. `bom_redo_leaves` walks the payload with the SAME boundary logic
    as `merge_tree` (a leaf = a subtree under one mapped root); each leaf is
    rebuilt with `pkgbuild --root <leaf> --install-location <mapped> --ownership
    preserve` (same component id so records merge; scripts embedded but skipped
    on failure). One leaf → flat `<name>-rootless.pkg`; several → an `.mpkg`
    bundle with a generated minimal Distribution. Because every destination is
    already under `$HOME` (or an already-writable location), `repkger install`
    of the rootless pkg re-maps NOTHING — the `map_path` "already under home
    root" rule (1b) makes that exact, and it also protects `--home` under
    `/var/folders` from the `/var` default rule. `bom-redo` needs the payload
    as a dir (pkgutil --expand-full).
    **v0.4.0 additions** (all `--only`-aware):
    - **Predictive BOM** (`--preview` / `--list-only`): Suspicious
      Package-style preview that expands the pkg, walks the leaves, prints
      every leaf → mapped root with predicted entry counts + a sample of the
      predicted BOM, plus `script_estimate` output, and returns BEFORE the
      pkgbuild/mkbom requirement and the `$out` mkdir — nothing is written.
    - **Targeted multi-level extraction** (`--only PREFIX`, also on
      `install`): `only_match`/`only_below` prune the payload walk at every
      level — descend when a prefix lies deeper (even with no mapping boundary
      there), merge/emit only subtrees at/under a prefix. Relative prefixes
      are normalized against the component install-location
      (`set_only_matches`). `--only /Applications` on the fixture → a single
      flat rootless `.pkg` (1 leaf) whose BOM/install-location are the mapped
      dir and nothing else.
    - **Script adjustment**: `script_rewrite_pairs` = payload `rewrite_pairs`
      MINUS the pure system-tool dirs (`/usr`, `/bin`, `/sbin`) plus all user
      `--map` pairs — a postinstall still needs `#!/bin/sh` and
      `/usr/bin/env` to resolve to real system tools. `redo_scripts` copies
      each script into a stage dir, rewrites it with the same idempotent
      `rewrite_one` pass, and `pkgbuild --scripts <stage>` embeds the
      adjusted copies (binary scripts untouched; the pkgbuild-without-scripts
      fallback stays). `script_estimate` (preview) counts refs that will be
      home-mapped and flags lines that still need privileges
      (sudo/chown-root/launchctl/installer/System — cannot be mapped).
14. **FamiStudio cask** (in `ksl-testing/homebrew-tap`): patched
    `main.command` discovers a user-space dotnet (graphical repair prompt if
    missing), strips quarantine/provenance from the bundle + parent on every
    launch, and prefers a bundled .NET **apphost** (generated in postflight
    via `dotnet publish` of a minimal project named FamiStudio) over the
    muxer. macOS names the About/Hide/Quit menu items from the executable
    FILE name — `exec -a` only changes argv[0] (menu-bar title); the muxer
    refuses to run renamed ("cannot execute dotnet when renamed to
    FamiStudio"), so the apphost is the only reliable fix. Settings +
    autosaves live in `~/Library/Application Support/FamiStudio/` (outside
    the bundle — upgrades can't touch them); postflight symlinks
    `FamiStudio.ini` + `AutoSaves/` into `~/Documents/FamiStudio/`.

## Production build (v0.4.0 — two-tier architecture)

15. **Two-tier app build** (`scripts/make-app.sh` env vars):
    - `APP_NAME` — .app folder name + CFBundleName (default: Repkger)
    - `DISPLAY_NAME` — CFBundleDisplayName (default: $APP_NAME)
    - `BUNDLE_ID` — CFBundleIdentifier (default: com.ksl-testing.repkger)
    - `INSTALL_DIR` — if set, copies finished .app here + re-signs at target
    Primary: `APP_NAME=tpl-unwrapper DISPLAY_NAME="TPL Unwrapper"
    BUNDLE_ID=com.tpl-unwrapper.app INSTALL_DIR="$HOME/applications"`
    Plugin: `APP_NAME="Noren Hodoki" DISPLAY_NAME="Noren Hodoki"
    BUNDLE_ID=com.noren-hodoki.app INSTALL_DIR="$HOME/applications/noren"`
16. **codesign MUST run after plist edits AND the install copy**. The old
    order (osacompile → plist → codesign → cp to INSTALL_DIR) left the
    installed copy unsigned → Gatekeeper rejected Finder double-click.
    Current order: osacompile → embed CLI → plist → icon → codesign →
    cp to INSTALL_DIR → re-sign installed copy. Verified with
    `spctl -a -v` and `open -g` (Gatekeeper mode).
17. **Gatekeeper caches rejections per (bundle-ID, path)**. Ad-hoc signed
    apps get rejected by `spctl`, and macOS caches the rejection. Rebuilding
    with the same bundle ID at the same path still fails until the cache is
    cleared. Fix: `/System/Library/Frameworks/CoreServices.framework/
    Frameworks/LaunchServices.framework/Support/lsregister -f <app>` after
    install (added to make-app.sh). Also: `$HOME` expansion + spaces break
    `open` — use `~/` form in shell scripts.

## macOS gotchas learned (expensive lessons)

- `pkgutil --expand-full` errors "File exists" if the destination dir exists →
  `rm -rf` first.
- Single-component pkgs expand with `PackageInfo` at the root.
- BSD sed: no `\b`; attribute regex must be `<tag[^>]* attr=` (with the space).
- `lsbom` = tab-separated, paths may contain spaces → `awk -F'\t'`.
- BOM contains `._*` AppleDouble entries that `--expand-full` folds into
  xattrs → record only paths that exist.
- bash 3.2: `set -u` + empty arrays → use `${arr[@]+"${arr[@]}"}`.
- EXIT traps need globals (locals die with the function).
- `xattr ... && say` under `set -e` → silent abort on failure; use if/else.
- `comp_scripts | grep -q` → SIGPIPE under `pipefail` (bash reports "write
  error: Broken pipe" and the branch flips); capture output first.
- NEVER `xattr -r /` — the TCC guard must skip `/` and `$HOME_ROOT`.
- `codesign --deep --sign` creates `Contents/_CodeSignature` AFTER the BOM —
  sweep it into the record or uninstall leaves it behind.
- Path rewrite must be one longest-prefix pass; naive per-pair
  protect-convert-restore double-rewrites tails (`/usr/local/bin`,
  `/private/var`).
- TCC `com.apple.macl` write-protects launched app bundles — clear once with
  `sudo xattr -rd com.apple.macl "<app dir>"` (repkger detects + prints hint).
- Brew cask DSL: `installer manual:` prints instructions only; `installer
  script:` executes as current user (`reset_uid`); `depends_on formula:` valid.
- AppleScript: `it` is a reserved word — use other loop var names; `open -a
  App file.pkg` hits `on open`, `--args` hits `on run argv`.
- **osacompile droplets ignore argv** when launched directly
  (`Contents/MacOS/droplet --install …` gets `{"current application"}` or
  nothing → falls into the mode-chooser dialog and hangs) and via
  `open --args`; the reliable headless path is
  `osascript <app-or-source> --install …`. A stale running droplet swallows
  Apple events and hangs new osascript calls — `pkill -f MacOS/droplet` first.
- **AppleScript handlers have NO optional/default params** — changing a
  handler's arity breaks every call site (`-1721`); grep all `my doInstall(`
  callers after editing.
- **CI round-trip determinism**: default keep-if-writable keeps `/Applications`
  in place on admin machines (GitHub runners), so `test/roundtrip.sh` phase 1
  pins `--map` for `/Applications`, `/Library`, `/usr/local` to the scratch
  home — 45/45 on both standard and admin users.
- **`ditto` DEREFERENCES a top-level symlink source**: `ditto link.app dst`
  copies the link TARGET as a real dir (nested symlinks are preserved, only
  the top-level argument is dereferenced). Unity's pkg has a top-level
  `Unity Bug Reporter.app` symlink → merge silently materialized it as a dir
  copy, and uninstall (record says symlink) couldn't remove it. Fix: merge_tree
  creates top-level symlinks with `ln -s $(readlink $c) $mc`; fixture now
  carries a top-level symlink regression check.
- **Unity pkg quirks**: inner component is named `Unity.pkg.tmp` (component_dirs
  must glob `*.pkg.tmp`); `PackageInfo version="0"` with the real version
  (`6000.3.22f1`) in the Distribution — both install and bom-redo prefer the
  Distribution version. install-location `/Applications/Unity`, payload
  `Unity/Unity.app` + `Unity Bug Reporter.app` symlink; 55,290 BOM entries,
  ~9.5 GB installed. Unity-Hub layout parity for a chosen folder L is
  `L/Unity/Hub/Editor/<ver>/Unity.app`, so the parity map is
  `--map "/Applications/Unity/Unity=$HOME/Applications/Unity/Hub/Editor/<ver>"`.
- Launch artifacts: Unity writes `UnityLockfile`, `UserSettings/`, `Logs/` into
  its own bundle's `Contents/MacOS/` at first run — not in the BOM, so
  uninstall leaves them (harmless, removable).

## Noren Hodoki branding (v0.4.0 — plugin tier)

**Status: ICON + BUILD PIPELINE DONE · RUNTIME INTEGRATION PENDING**

- **Icon**: `gui/NorenHodoki.icns` (kuchinashi gradient `#E07B4E`→`#B85030`, unwrapping knot glyph) — sourced from tpl-bootkit branding/icons/make-svgs.py
- **Bundle ID**: `com.noren-hodoki.app` (target; default `com.ksl-testing.repkger` for compat)
- **Display name**: "Noren Hodoki" — the Noren Suite module for rootless package extraction
- **Install path**: `~/Applications/Noren Hodoki/` via `INSTALL_DIR`
- **Build command**:
  ```bash
  APP_NAME="Noren Hodoki" DISPLAY_NAME="Noren Hodoki" \
  BUNDLE_ID=com.noren-hodoki.app \
  INSTALL_DIR="$HOME/Applications/Noren Hodoki" \
  ./scripts/make-app.sh
  ```
- **Post-build quarantine strip**: `xattr -dr com.apple.quarantine/provenance` + `lsregister -u -f` after codesign (prevents Defender deletion of fresh builds)
- **CLI embedded**: `bin/repkger` at `Contents/Resources/repkger` — unchanged

**Open / Known issues:**
- Hodoki runtime integration not yet implemented — the app builds and launches, but the Noren Hodoki menu/CLI surface doesn't expose repkger's `bom-redo`/`inspect`/`install` flows yet
- The AppleScript droplet (`gui/Repkger.applescript`) still uses the "Repkger" mode chooser labels; needs relabel to "Noren Hodoki" + Hodoki-specific actions
- Bundle ID migration (`com.ksl-testing.repkger` → `com.noren-hodoki.app`) will need a shim for existing users
- `noren hodoki` CLI alias not yet added to `bin/repkger`

**See also:** tpl-bootkit `branding/HODOKI_BRIEF.md` for full brand identity (kuchinashi gradient, unwrapping metaphor, Noren Suite positioning)

## Test fixtures

- **Fast (default)**: `test/make-fixture.sh` → `/tmp/repkger-fixture/mini.pkg`
  (3.7 KB). Single component `com.test.miniapp` v1.0.0, install-location `/`:
  `Applications/MiniApp.app` (real bundle + stale-refs file + relative
  symlink), `usr/local/bin/mini-tool`, `Library/MiniSupport/README.txt`,
  `Users/Shared/mini-shared.txt`, `tmp/mini-tmp.txt`, preinstall + postinstall.
  Exercises every mapping boundary, keep-in-place, rewrite, resign, and the
  quarantine parent strip.
- **GameMaker 2024.14.4.222** (`~/Downloads/repkger-test/` — deleted to save
  space; re-downloadable). Single component `com.yoyogames.gms2`,
  install-location `/Applications`, 17,480 BOM entries, ~800 MB payload,
  preinstall commented out, postinstall only chmods
  `/Users/Shared/GameMakerStudio2` dirs. Note: `postinstall-e` /
  `preinstall-e` variants exist (arch-specific copies), payload also contains
  `Alice.gmplugin-e`-style `-e` files — those are real files, do not filter.

## Container input support + script sanitization (v0.5.0)

18. **Container resolution** (`resolve_pkg_input`): `inspect`, `install`, and
    `bom-redo` now accept `.pkg`, `.mpkg`, `.bundle` (flat XAR — extension
    agnostic), `.dmg` (mounts read-only via `hdiutil`, finds inner `.pkg`,
    auto-detaches), `.zip` / `.tar*` (extracts to temp dir, finds inner `.pkg`),
    or a directory containing a `.pkg`. DMG mounts and temp dirs are cleaned up
    via EXIT trap. The function sets the global `RESOLVED_PKG` (not echoed —
    avoids subshell propagation issues with `$(...)` callers). Info messages
    go to stderr to avoid polluting return captures.
19. **Script sanitization** (`sanitize_script` + `run_install_scripts`):
    `--run-scripts` now actually executes scripts (was a no-op before). Before
    execution, scripts are sanitized: `sudo` prefixes stripped (handles
    `sudo -u user`, `sudo -u user -s`, etc.), `launchctl`/`installer`/`chown
    root`/`/System/` writes commented out, binary scripts copied untouched.
    Path references are rewritten via `rewrite_one` to match home-mapped
    locations. Scripts run in a home-rooted environment (`DSTROOT`, `HOME`,
    `INSTALLER_TEMP`).
20. **Enhanced inspect output**: script content shown by default (Suspicious
    Package parity). Each script shows Name, Kind, Size, As User (from `auth`
    attribute), When (inferred from script name: preinstall → "Before moving
    files into place", postinstall → "After moving files into place"), and
    line-numbered content with privilege warnings (sudo/chown-root/launchctl/
    /System/ paths flagged). New `--no-scripts` flag to suppress. Previous
    `--show-scripts` still accepted for backward compat.
21. **Container cleanup** (`container_cleanup`): unified cleanup function for
    DMG mounts and temp extract dirs. Replaces old `cask_cleanup` (which now
    delegates to it). Both `CONTAINER_*` and `CASK_*` globals are cleaned.
    EXIT traps in `cmd_inspect`, `cmd_install`, `cmd_bom_redo` chain
    `container_cleanup` with `rm -rf EXPAND_TMP`. Trap uses `${EXPAND_TMP:-}`
    to avoid unbound-variable errors under `set -u`.
22. **Test suite**: 104 checks (was 82). Phase 6 (12 checks): `.dmg`, `.bundle`,
    `.zip`, directory input, `bom-redo` on `.dmg`, unsupported-input error.
    Phase 7 (10 checks): enhanced inspect output (As User, When, Kind, line
    numbers), `--no-scripts`, `--run-scripts` with path rewriting + sudo
    sanitization.
