# STATUS — 2026-08-19 (v0.4.0)

## Done & validated
- CLI commands: `inspect` (+ `--json`, `--show-scripts`, `--files [N]`),
  `install`, `uninstall`, `list`, `brew`, `gui`, `self-install`, `version`,
  `bom-redo` (+ `--preview`/`--list-only`, `--only`) — single file
  `bin/repkger` (bash 3.2-compatible).
- **Scope bug fixed**: rewrite + resign operate only on the package's own
  landed files (BOM-driven `INSTALLED_FILES`); validated with a decoy app
  pre-placed in a scratch home — untouched.
- **Rewrite rewrite**: single-pass longest-prefix token rewrite; verified
  byte-correct on nested refs (`/usr/local/bin`, `/usr/bin:/bin`,
  `/private/var`, `/Library/Application Support`, `--prefix=`), idempotent.
- **Quarantine**: merged targets + mapped install-location dirs stripped
  recursively; each one's parent dir stripped non-recursively
  (`xattr -dr com.apple.quarantine`, fallback `-c`/`-cr` clear-all). Verified
  against a quarantined scratch `~/Applications`.
- **GUI `Repkger.app`** built (`build/Repkger.app`): droplet with Inspect /
  Install / Uninstall flows, embedded CLI, doc types, ad-hoc signed;
  headless `--install/--inspect` verified end-to-end via osascript.
- **GUI multi-select (2026-08-13)**: open dialog picks one or many .pkg files
  (`choosePkgs`); mode chooser + drag-drop process each independently with
  per-file `(i of n)` progress notifications; verified via osascript: two
  sequential fixture installs → 2 records → both uninstalled. `make-app.sh`
  reads the version from `bin/repkger` (single source of truth).
- **CI round-trip fix (2026-08-13)**: `test/roundtrip.sh` phase 1 pins
  `--map` `/Applications` `/Library` `/usr/local` to the scratch home —
  deterministic on admin machines (GitHub runners) where keep-if-writable
  would keep the fixture in the real `/Applications`. 82/82 locally.
- **Synthetic fixture** (`test/make-fixture.sh`, 3.7 KB pkg): full
  install → uninstall round-trip (25 files recorded incl. `_CodeSignature`,
  all reversed; `/Users/Shared` + `/tmp` kept in place and cleaned; a
  top-level symlink is preserved through merge + uninstall; postinstall
  carries stale `/Applications`/`/Library`/`/usr/local` refs for phase 5
  script-adjustment testing).
- pkg sha256 GameMaker `8cbd33a9…cc7f` (matches upstream homebrew cask) was
  verified at v0.1.0; fixture re-testing covers the loop since.

## Fixed incidental bugs (v0.2.0)
- Single-component pkgs expanding with `PackageInfo` at the root were
  "unsupported layout" (component_dirs now checks the root).
- install-location `/` produced `//Applications` paths, which silently broke
  keep-in-place for `/Users/Shared` + `/tmp` and made the TCC guard walk `/`.
- `comp_scripts | grep -q` SIGPIPE under `pipefail` hid scripts in inspect;
  `inspect` also exited 1 spuriously.
- `_CodeSignature` dirs created by ad-hoc signing weren't recorded →
  uninstall left them behind.

## Outstanding
- Historical v0.1.0 `~/Applications` damage on this machine not yet reversed
  (tool can no longer cause it). See `llms.md` → "Old v0.1.0 damage reversal".
- **Release pipeline — published manually, CI still blocked (2026-08-15)**:
  first run (`31548908050`) failed its test job on the admin-runner
  `/Applications` issue — FIXED in `test/roundtrip.sh` (28/28 locally). The
  re-trigger run (`31757347428`) was **blocked by GitHub account billing**
  (jobs never started). **v0.2.0 is now live** — published manually via
  `gh release create` (28/28 roundtrip → make-app.sh → dist assets → gh),
  zero Actions quota. Automation prepped but deferred:
  `.github/workflows/release.yml` (WHEN-THIS-RUNS comment) +
  `scripts/release-gh.sh` (non-working placeholder). Tap formula still needs
  a `TAP_TOKEN` PAT. See `HANDOFF.md` → 2026-08-15 section. FamiStudio cask
  DONE and live at 4.5.3. Fresh-agent pickup: `HANDOFF.md` at the repo root.
- **Unity Editor rootless install test — DONE (2026-08-18, v0.3.0)**: full
  Unity-Hub-parity flow via the new **`repkger bom-redo`** command (BOM redone
  to the mapped no-sudo locations and repacked with pkgbuild). ARM64 pkg
  (5,107,849,173 bytes, md5 matches Unity's published hash) → rootless pkg
  rooted at `$HOME/Applications/Unity/Hub/Editor/6000.3.22f1` → plain install
  (no --map) → 55,077 files, 201 stale refs rewritten → launched headless
  once → uninstall reversed everything. See README "Validated" + HANDOFF
  2026-08-18. `test/roundtrip.sh` 45/45.
- **New in v0.3.0**: `bom-redo`; bundle-.mpkg expansion;
  `*.pkg.tmp` component discovery; Distribution-version fallback
  (Unity stamps PackageInfo version `0`); map_path never re-maps
  under-home paths; sha256 for dir pkgs; top-level symlink
  preservation in merge (ditto dereferences them); `--rpkg` brew
  force flag + `brew()` shim (no silent installer); `--rpkg` handles
  dmg/zip casks with an inner pkg (mount/unzip → rootless install →
  cleanup); GUI `choose from list` chooser (fixed 4-button -50 bug) +
  cask install mode + headless `--cask`.
- **New in v0.5.1+**: `brew install --cask <name>` always routes
  through repkger rootlessly (the `brew()` shim intercepts
  `install --cask` by default; `--rootless` alias for `--rpkg`
  additionally dies on non-pkg artifacts). `--rootless` works as an
  alias for `--rpkg` everywhere. Roundtrip **112/112**.
- **New in v0.4.0**: Predictive BOM (`--preview`/`--list-only` on
  `bom-redo`); targeted multi-level extraction (`--only PREFIX` on `bom-redo`
  + `install`); embedded pre/post-install script adjustment to match the
  redone BOM (`script_rewrite_pairs` = payload pairs minus `/usr` `/bin`
  `/sbin` + user `--map`s); two-tier production build (`tpl-unwrapper`
  primary + `Noren Hodoki` plugin, env-var-driven `make-app.sh`);
  Gatekeeper cache fix (`lsregister -f` after install). Real-world verified:
  BrickLink Studio 2.0.pkg (561 MB, 72K BOM entries), Unity 6000.3.22f1
  (5 GB, 55K entries). Roundtrip **82/82**.
- **Production apps** at `~/applications/`: `tpl-unwrapper.app` (primary)
  and `noren/Noren Hodoki.app` (plugin), both v0.4.0, signed, Finder-launched.
- Repkger.app has no custom icon / notarization; progress UI is
  notifications-only (no progress bar yet).
- Tap casks: the `famistudio` cask is DONE and live at **4.5.3** (rootless
  .NET cask with apphost menu-name fix, de-quarantine self-heal,
  settings/autosave symlinks, weekly Monday livecheck — upgrade verified:
  settings ini byte-identical after `brew upgrade --cask famistudio`). Still open:
  `Casks/repkger.rb` (GUI) + rootless `Casks/gamemaker.rb`.

## Release pipeline
- `.github/workflows/release.yml`: push to `main` (paths: bin/gui/scripts/
  tap/test/workflow) or `workflow_dispatch` → test (fixture round-trip 82
  checks + GUI smoke) → build (`make-app.sh`, CLI zip, app zip, SHA256SUMS)
  → publish/refresh release `v<REPKGER_VERSION>` with assets →
  `scripts/update-tap.sh` updates `ksl-testing/homebrew-tap`. Manual
  re-trigger: `gh workflow run build-release.yml` (works from mobile).
- `scripts/update-tap.sh` renders `tap/repkgr.rb` (+ `repkger.rb` alias) with
  the release URL + sha256, clones or creates the tap repo, commits, pushes.
- **Env-var build** (`scripts/make-app.sh`): APP_NAME, DISPLAY_NAME,
  BUNDLE_ID, INSTALL_DIR — no script edits needed. Primary build:
  `APP_NAME=tpl-unwrapper` at `~/applications/`. Plugin build:
  `APP_NAME="Noren Hodoki"` at `~/applications/noren/`. After install,
  `lsregister -f` clears cached Gatekeeper rejections.
- ⚠️ CI blocked by GitHub account billing (runs don't start) — v0.2.0 and
  v0.3.0 published manually via `gh release create`. v0.4.0 pending commit.
  `scripts/release-gh.sh` is a non-working placeholder for future automation.
  Tap formula still needs a `TAP_TOKEN` PAT.

## Housekeeping notes
- `test/make-fixture.sh` builds the fast fixture (`/tmp/repkger-fixture/mini.pkg`);
  `build/Repkger.app` is gitignored-worthy (generated).
- `~/Downloads/repkger-test/` (GameMaker fixture) was deleted to save space;
  re-downloadable.
- `~/.repkger/records/` holds the real-install GameMaker record from v0.1.0.
- `gui/NorenHodoki.icns` (kuchinashi gradient icon) — sourced from
  tpl-bootkit branding. `make-app.sh` picks it up automatically.
- Real-world test pkgs on disk: BrickLink Studio 2.0.pkg (561 MB) in
  `~/Downloads/`, Unity 6000.3.22f1-arm64.pkg (5 GB) in `~/Downloads/`.
