# STATUS — 2026-08-11 (v0.2.0)

## Done & validated
- CLI commands: `inspect` (+ `--json`, `--show-scripts`, `--files [N]`),
  `install`, `uninstall`, `list`, `brew`, `gui`, `self-install`, `version` —
  single file `bin/repkger` (bash 3.2-compatible).
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
- **Synthetic fixture** (`test/make-fixture.sh`, 3.7 KB pkg): full
  install → uninstall round-trip (25 files recorded incl. `_CodeSignature`,
  all reversed; `/Users/Shared` + `/tmp` kept in place and cleaned).
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
- **Release pipeline live**: v0.2.0 pushed (`ff70de3`); the workflow
  publishes release `v0.2.0` + assets (verify run, then add the `TAP_TOKEN`
  secret so the tap formulae publish too). FamiStudio cask DONE and live at
  4.5.3. Fresh-agent pickup: `HANDOFF.md` at the repo root.
- Repkger.app has no custom icon / notarization / progress UI.
- Tap casks: the `famistudio` cask is DONE and live at **4.5.3** (rootless
  .NET cask with apphost menu-name fix, de-quarantine self-heal,
  settings/autosave symlinks, daily livecheck — upgrade verified: settings
  ini byte-identical after `brew upgrade --cask famistudio`). Still open:
  `Casks/repkger.rb` (GUI) + rootless `Casks/gamemaker.rb`.

## Release pipeline (new in this session, validated locally)
- `.github/workflows/release.yml`: push to `main` (paths: bin/gui/scripts/
  tap/test/workflow) or `workflow_dispatch` → test (fixture round-trip 28
  checks + GUI smoke) → build (`make-app.sh`, CLI zip, app zip, SHA256SUMS)
  → publish/refresh release `v<REPKGER_VERSION>` with assets →
  `scripts/update-tap.sh` updates `ksl-testing/homebrew-tap`. Manual
  re-trigger: `gh workflow run build-release.yml` (works from mobile).
- `scripts/update-tap.sh` renders `tap/repkgr.rb` (+ `repkger.rb` alias) with
  the release URL + sha256, clones or creates the tap repo, commits, pushes.
- Validated: workflow YAML parses; `bash -n` all scripts; `test/roundtrip.sh`
  28/28; generated formulas pass `brew style` (0 offenses), `brew install`
  and `brew test` via a throwaway local tap (then untapped, no residue).
- To activate: commit + push, add `TAP_TOKEN` secret, then
  `brew install ksl-testing/tap/repkgr`.

## Housekeeping notes
- `test/make-fixture.sh` builds the fast fixture (`/tmp/repkger-fixture/mini.pkg`);
  `build/Repkger.app` is gitignored-worthy (generated).
- `~/Downloads/repkger-test/` (GameMaker fixture) was deleted to save space;
  re-downloadable.
- `~/.repkger/records/` holds the real-install GameMaker record from v0.1.0.
