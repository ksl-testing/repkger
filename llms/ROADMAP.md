# ROADMAP

Ordered by dependency; each step is self-contained for a fresh agent.

## 1. FIX the rewrite/codesign scope bug (do first — prevents further damage)
In `bin/repkger`:
- `cmd_install` post-merge passes must use only the package's own files:
  - rewrite: iterate the recorded file list (paths that exist), not
    `grep -r` over `INSTALLED_TARGETS`.
  - resign: `resign_apps ${MERGED_DIRS[@]+"${MERGED_DIRS[@]}"}` (mirror the
    dequarantine call which already uses MERGED_DIRS).
  - `record_installed_targets()` becomes unnecessary for rewrite; keep
    `INSTALLED_TARGETS` only if something still needs it (else drop).
- Re-validate with the scratch flow in `llms.md`, then a real `~/` install;
  confirm no other apps' files change.

## 2. REVERSE ~/Applications collateral damage (see llms.md "TODO first")
- Survey, reverse-rewrite, verify shebangs, re-sign affected bundles,
  optionally `brew reinstall --cask suspicious-package platypus` +
  `brew install --cask ksl-testing/tap/famistudio` to restore vendor sigs.

## 3. GUI `Repkger.app`
- `gui/Repkger.applescript` — AppleScript droplet:
  - `on open droppedItems` → install each `.pkg` (Terminal window or
    hidden `do shell script` + progress dialog).
  - `on run` → mode chooser (Inspect / Install / Uninstall / Open pkg).
- `scripts/make-app.sh`: `osacompile -o build/Repkger.app gui/Repkger.applescript`,
  embed `bin/repkger` into `Contents/Resources/`, add CFBundleDocumentTypes for
  `pkg`/`mpkg` via PlistBuddy, bundle id `com.ksl-testing.repkger`.
- `repkger gui` should find the app next to the script or in /Applications.

## 4. Brew integration (in `ksl-testing/homebrew-tap` workspace)
- `Formula/repkger.rb` — installs `bin/repkger` (source = this repo tarball;
  needs a tag, e.g. `v0.1.0`, and real sha256).
- `Casks/repkger.rb` — GUI app to /Applications (depends_on formula: "repkger").
- `Casks/gamemaker.rb` — rootless example using the confirmed hook:
  `preflight do` writes `repkger-install.sh` into `staged_path`, then
  `installer script: { executable: "repkger-install.sh" }` (runs as the
  current user; `installer manual:` does NOT run anything — script does).
  sha256 `8cbd33a9a92ed60ebd53734413b33afdeb8c677326ada0c80971e9f91555cc7f`,
  livecheck `https://gms.yoyogames.com/update-mac.rss` (sparkle).
- `repkger brew --cask <name>` wrapper already implemented in the CLI:
  detects pkg-style casks, downloads to `~/.repkger/downloads`, verifies
  sha256, installs rootlessly; `self-install` adds a `brewpkg()` function.
- Docs in the tap pointing back here (each repo documents its own purpose).

## 5. Publishing
- `gh repo create ksl-testing/repkger --private --source=/Users/tpldih/Documents/GitHub/repkger --push`
- Tag `v0.1.0`; update `Formula/repkger.rb` url+sha256; test
  `brew install ksl-testing/tap/repkger` and `brew install --cask ksl-testing/tap/gamemaker`.

## Ideas parked
- `--run-scripts` hardening: run pre/postinstall with a sandboxed home-rooted
  env (DSTROOT=$HOME, INSTALL_PREFIX mapped); currently recorded-not-run.
- Verify installed tree against the record (like CSP's COMBINED_BOM check).
- Refactor CSP_Mac's `install_portable.sh` + `Casks/clip-studio-paint.rb` to
  use repkger (drop the CSP-specific code).
- Handle `/Library/LaunchDaemons` payloads with a loud warning (won't autostart).
- Icon + proper notarization for the GUI app (needs a paid dev account).
