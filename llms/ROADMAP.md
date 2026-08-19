# ROADMAP

Ordered by dependency; each step is self-contained for a fresh agent.

## 1. ~~FIX the rewrite/codesign scope bug~~ — DONE (v0.2.0, 2026-08-11)
- Rewrite + resign now iterate the BOM-driven `INSTALLED_FILES` list (the
  package's own landed files) instead of scanning mapped top-level dirs.
- Dequarantine covers merged dirs + mapped install-location dirs and strips
  each one's parent dir (non-recursive).
- Validated with the synthetic fixture + a decoy app in the scratch home.

## 2. REVERSE ~/Applications collateral damage (still pending)
From the v0.1.0 broad-scan install. Survey, reverse-rewrite, verify shebangs,
re-sign affected bundles, optionally
`brew reinstall --cask suspicious-package platypus` +
`brew install --cask ksl-testing/tap/famistudio` to restore vendor sigs.
Full procedure in `llms.md` → "Old v0.1.0 damage reversal". Also consider a
`repkger undo-rewrite <dir>` command that automates the reverse mapping
(using the same longest-prefix token logic as `rewrite_one`, inverted).

## 3. ~~GUI `Repkger.app`~~ — DONE (v0.2.0, 2026-08-11; multi-select 2026-08-13)
- `gui/Repkger.applescript` droplet: `on open droppedItems` → Inspect /
  Install per drop (multiple drops looped independently); `on run` mode
  chooser (Inspect / Install / Uninstall) with a **multi-select** open dialog
  (`choosePkgs`, `multiple selections allowed true`) that processes each
  chosen .pkg independently with per-file `(i of n)` progress notifications;
  Suspicious-Package-style inspect dialog (components, scripts, `--files 20`
  BOM listing with home-mapped destinations), Full Report → TextEdit,
  Install → `repkger install --home $HOME --yes`; headless
  `--install <pkg> [--home dir] [--data dir]` + `--inspect <pkg>` (drive via
  `osascript`, NOT the raw binary — droplets ignore argv).
- `scripts/make-app.sh`: osacompile → `build/Repkger.app`, embeds
  `bin/repkger` into `Contents/Resources/`, sets
  `com.ksl-testing.repkger` + version (now read from `bin/repkger`'s
  `REPKGER_VERSION`), registers `.pkg`/`.mpkg` doc types via PlistBuddy,
  ad-hoc signs. `repkger gui` finds it in build/ / repo root /
  `~/Applications` / `/Applications`.
- **Remaining polish**: custom icon (`gui/Repkger.iconset` + iconutil +
  `CFBundleIconFile` — make-app.sh already supports `gui/Repkger.icns`);
  real progress UI (install is notifications-only; the CLI run blocks the
  droplet); notarization (needs a paid dev account).

## 4. ~~Brew formula pipeline~~ — DONE (2026-08-11, pre-v0.2.0-publish)
- `tap/repkgr.rb` + `tap/repkger.rb` templates → `scripts/update-tap.sh`
  publishes `Formula/repkgr.rb` (+ `repkger.rb` alias) to
  `ksl-testing/homebrew-tap`, creating the repo on first run. URL points at
  `releases/download/v<VERSION>/repkger-<VERSION>.zip` with the real sha256;
  generated formulas pass `brew style`, `brew install`, and `brew test`
  (validated locally via a throwaway tap).
- Automation: `.github/workflows/release.yml` — on `main` push (source paths)
  or `workflow_dispatch`: test → build assets → publish/refresh `vX.Y.Z`
  release → `scripts/update-tap.sh`. Needs the `TAP_TOKEN` secret to push the
  tap (skips gracefully without it).
- ~~FamiStudio cask~~ — DONE (2026-08-11): rootless .NET cask with a
  self-healing launcher (dotnet discovery + repair prompt), de-quarantine
  self-heal (bundle + parent on every launch), a bundled .NET apphost so the
  macOS menu says "FamiStudio" not "dotnet", settings/autosave symlinks into
  ~/Documents/FamiStudio, and a weekly Monday livecheck updater — live at
  4.5.3.
- Still open: `Casks/repkger.rb` (GUI app to /Applications, depends_on
  formula: "repkger") and the rootless `Casks/gamemaker.rb` example:
  `preflight do` writes `repkger-install.sh` into `staged_path`, then
  `installer script: { executable: "repkger-install.sh" }` (runs as the
  current user). sha256
  `8cbd33a9a92ed60ebd53734413b33afdeb8c677326ada0c80971e9f91555cc7f`,
  livecheck `https://gms.yoyogames.com/update-mac.rss` (sparkle).
- `repkger brew --cask <name>` wrapper already implemented in the CLI.

## 5. First publish — ✅ DONE manually via gh CLI (2026-08-15)
- ~~Commit everything~~ — DONE. The CI pipeline is **blocked by GitHub account
  billing** (runs never start), so v0.2.0 was published manually with the gh
  CLI (zero Actions quota): 28/28 roundtrip → `make-app.sh` → dist assets →
  `gh release create v0.2.0` (assets `repkger`, `repkger-0.2.0.zip`,
  `Repkger-0.2.0.app.zip`, `SHA256SUMS.txt`).
- ~~Automation~~ DEFERRED, prepped: `.github/workflows/release.yml` carries a
  WHEN-THIS-RUNS comment; `scripts/release-gh.sh` is a **non-working
  placeholder** documenting the manual gh steps to convert into a script
  later (or re-enable the workflow once billing is fixed).
- STILL OPEN: add a `TAP_TOKEN` PAT secret (repo scope) to ksl-testing/repkger
  so `scripts/update-tap.sh` pushes the formula; then
  `brew install ksl-testing/tap/repkgr` on a clean machine.

## 6. ~~Unity Editor rootless install test~~ — ✅ DONE (2026-08-18, v0.3.0)
User wanted: download + extract the editor the way Unity Hub would with
`~/Applications` selected, by redoing the BOM to accessible no-sudo locations.
Delivered via the new **`bom-redo`** command (BOM + payload repacked per
mapping boundary): ARM64 pkg → rootless pkg rooted at
`$HOME/Applications/Unity/Hub/Editor/6000.3.22f1` (byte-for-byte the Hub
layout) → plain install → launch → uninstall. Full details: README
"Validated", HANDOFF 2026-08-18, NOTES.md. On the way, fixed: `*.pkg.tmp`
component discovery, Distribution-version fallback (Unity's PackageInfo
version is `0`), under-home map_path rule, dir-pkg sha256, bundle .mpkg
expansion, and the ditto top-level-symlink dereference bug.

Natural follow-ups: make the Unity flow a one-liner
(`repkger bom-redo … --map …` could ship a `--hub-parity` preset for
`/Applications/Unity/Unity`), add the rootless pkg to the GUI's install flow,
and consider auto-deleting the downloaded pkg after a successful bom-redo.

## Ideas parked
- `--run-scripts` hardening: run pre/postinstall with a sandboxed home-rooted
  env (DSTROOT=$HOME, INSTALL_PREFIX mapped); currently recorded-not-run.
- Verify installed tree against the record (like CSP's COMBINED_BOM check).
- `repkger undo-rewrite <dir>`: reverse the path rewrite with the inverted
  mapping (needed for the ~/Applications damage, item 2).
- Refactor CSP_Mac's `install_portable.sh` + `Casks/clip-studio-paint.rb` to
  use repkger (drop the CSP-specific code).
- Handle `/Library/LaunchDaemons` payloads with a loud warning (won't autostart).
- Icon + proper notarization for the GUI app (needs a paid dev account).
- GUI progress: run install in the background and poll the record file for a
  progress bar instead of beachballing.
