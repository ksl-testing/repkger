# HANDOFF — repkger + ksl-testing/tap (written 2026-08-11)

A cacheless agent can pick up from this file. Read `README.md`, `llms.md`,
`llms/STATUS.md`, `llms/ROADMAP.md`, and `NOTES.md` for depth; this is the
state + next steps.

## Session update (2026-08-20) — v0.5.0: container input support + script sanitization

**The tool now opens .dmg, .zip, .bundle, and directories containing .pkg files**
in addition to raw .pkg/.mpkg. This is the "unpkg on steroids" upgrade — it
not only extracts like unpkg, but rewrites paths to ~/ locations, sanitizes
scripts for rootless execution, and inspects packages like Suspicious Package.

Three features shipped in `bin/repkger` (v0.5.0, version bumped):

- **Container resolution** (`resolve_pkg_input`): `inspect`, `install`, and
  `bom-redo` now accept `.dmg` (auto-mounts via hdiutil, finds inner .pkg,
  auto-detaches), `.zip`/`.tar*` (extracts, finds inner .pkg), `.bundle`
  (flat XAR, works as-is), or a directory containing a .pkg. DMG mounts and
  temp dirs cleaned up via EXIT trap.
- **Script sanitization** (`--run-scripts` now works!): pre/post-install scripts
  are sanitized for rootless execution — `sudo` prefixes stripped, `launchctl`/
  `installer`/`chown root`/`/System/` writes commented out, path references
  rewritten to home-mapped locations, scripts run in home-rooted environment.
- **Enhanced inspect output** (Suspicious Package parity): script content shown
  by default with Name, Kind, Size, As User, When, line-numbered content,
  and privilege warnings. New `--no-scripts` flag to suppress.

`test/roundtrip.sh` now **104/104** (was 82): phase 6 covers .dmg/.bundle/
.zip/directory input; phase 7 covers script sanitization and enhanced inspect.
Docs updated: README (quick start + design), NOTES (items 18-22).

**Committed and pushed.**

## Previous: Session update (2026-08-19) — v0.4.0: two-tier production build + launch bug fixes

**Production architecture is live.** Two apps built and verified:

| App | Path | Bundle ID | Role |
|-----|------|-----------|------|
| tpl-unwrapper | `~/applications/tpl-unwrapper.app` | `com.tpl-unwrapper.app` | Primary bootkit-branded product |
| Noren Hodoki | `~/applications/noren/Noren Hodoki.app` | `com.noren-hodoki.app` | Plugin widget for tpl-bootkit |

Both embed `repkger` CLI v0.4.0, ad-hoc signed, launch from Finder.

**Three launch bugs fixed:**
1. **codesign ordering** — `codesign` ran BEFORE plist edits and the
   INSTALL_DIR copy, so the installed `.app` was unsigned (Gatekeeper
   blocked Finder double-click). Fixed: codesign runs last, plus re-signs
   the installed copy at its target path.
2. **Gatekeeper cache** — ad-hoc signed apps get rejected by `spctl` and
   macOS caches the rejection per (bundle-ID, path). Rebuilding with the
   same bundle ID at the same path still fails until the cache is cleared.
   Fix: `lsregister -f <app>` after install (added to make-app.sh). Also,
   `$HOME` expansion in `open` mangles spaces — use `~/` form in scripts.
3. **Stale copies** — old `Noren CLI.app` / `Noren Desktop.app` from
   OpenCode's brand work cluttered `~/applications/noren/`. Cleaned.

**Build commands** (env-var-driven, no script edits needed):
```bash
# Primary (bootkit-branded)
APP_NAME=tpl-unwrapper DISPLAY_NAME="TPL Unwrapper" \
  BUNDLE_ID=com.tpl-unwrapper.app \
  INSTALL_DIR="$HOME/applications" bash scripts/make-app.sh

# Plugin (noren hodoki)
APP_NAME="Noren Hodoki" DISPLAY_NAME="Noren Hodoki" \
  BUNDLE_ID=com.noren-hodoki.app \
  INSTALL_DIR="$HOME/applications/noren" bash scripts/make-app.sh
```

**Real-world verification:** 561MB BrickLink Studio 2.0.pkg
(`https://studio.download.bricklink.info/Studio2.0/Archive/2.26.7_1/Studio+2.0.pkg`).
Inspect: 72,871 BOM entries, postinstall script parsed. Preview: 7 leaves
mapping `/Applications/Studio 2.0/*` → `~/Applications/Studio 2.0/*`.
Targeted `--only "/Applications/Studio 2.0/Sample"` produced an 11-file
rootless `.pkg`. Roundtrip suite: **82/82**. Build script now runs
`lsregister -f` after install to clear cached Gatekeeper rejections.

## Previous: v0.4.0 feature work — predictive BOM + targeted extraction + script adjustment

The user's ask: make the `.pkg`/`.bundle` → no-sudo extractor a working
product — Suspicious-Package-style **predictive BOM** for the `~/`-rooted
repack, **targeted multi-level extractions**, and pre/post-install scripts
**adjusted to match the new BOM**. All three shipped in `bin/repkger`
(v0.4.0, version bumped; NOT committed):

- **`bom-redo --preview` / `--list-only`**: predictive BOM — expands the
  pkg, prints every mapping-boundary leaf → mapped root, predicted entry
  counts, a sample of the predicted BOM (path → `~/` dest), and the script
  estimates; returns before pkgbuild/mkbom, writes nothing.
- **`--only PREFIX`** (bom-redo AND install): targeted extraction.
  `only_match`/`only_below` prune the payload walk at every level (descend
  into unmatched dirs that CONTAIN a prefix; merge/emit only subtrees at/under
  a prefix; relative prefixes normalized against the component
  install-location). `bom-redo … --only /Applications` → single flat
  rootless `.pkg` whose BOM is just that subtree.
- **Script adjustment**: embedded pre/post-install scripts are rewritten so
  their absolute refs match the new BOM (`script_rewrite_pairs` = payload
  pairs minus `/usr` `/bin` `/sbin` + all user `--map`s, so `#!/bin/sh` and
  `/usr/bin/env` still work). `--preview` shows the estimate including lines
  that can't be mapped (sudo/chown-root/launchctl/installer/System).

`test/roundtrip.sh` gained **phase 5 (22 checks)** → **82/82** locally
(preview builds nothing; `--only` BOM/install-location verified via xar +
lsbom; embedded postinstall home-mapped with shebang intact; mpkg path;
`install --only`). Fixture postinstall now carries stale refs to exercise the
adjustment. Docs updated: README (quick start + design), NOTES item 13,
ROADMAP (item 7), this file. Nothing committed/pushed; no release.

## Session update (2026-08-18) — Unity Editor test COMPLETE + `bom-redo` (v0.3.0)

The user-requested **Unity Editor rootless install test is DONE** — see
README "Validated". The pkg had been deleted from `~/Downloads` to save space,
so it was re-downloaded (ARM64 build, the one Unity Hub itself would fetch on
this Apple-silicon Mac):
`https://download.unity3d.com/download_unity/1c726e1fb402/MacEditorInstallerArm64/Unity-6000.3.22f1.pkg`
(5,107,849,173 bytes; md5 `revO9paHvxhkIn7BzWb6BA==` matches Unity's published
hash; sha256 `a60e4a44c2463edd63a6d172361c873e7e57d4c6e7eb443da2a95602cc598d6a`).
Still in `~/Downloads/Unity-6000.3.22f1-arm64.pkg`.

The user asked for the extraction to be done "the way Unity Hub would had I
selected ~/Applications, by redoing the bom to match accessible no sudo
locations" → new **`repkger bom-redo`** command (v0.3.0): redoes the BOM to the
mapped no-sudo locations and repacks (pkgbuild per mapping boundary; flat
`-rootless.pkg` for one leaf, `.mpkg` bundle otherwise). Unity run:
`bin/repkger bom-redo <pkg> --map "/Applications/Unity/Unity=$HOME/Applications/Unity/Hub/Editor/6000.3.22f1"`
→ `~/.repkger/rootless/Unity-6000.3.22f1-arm64-rootless.pkg` (install-location
`$HOME/Applications/Unity/Hub/Editor/6000.3.22f1` — byte-for-byte the Unity Hub
layout) → plain `repkger install` (no --map) → 55,077 files, 201 stale refs
rewritten, launched headless once (`-batchmode -quit`, clean exit), uninstall
reversed everything. `test/roundtrip.sh` now 45/45 (phase 3 = bom-redo
round-trip; fixture gained a top-level symlink regression check).

Bugs found + fixed along the way:
- `component_dirs` missed `*.pkg.tmp` (Unity's inner component name).
- Unity stamps `PackageInfo version="0"`; install/bom-redo now prefer the
  Distribution version (record reads `6000.3.22f1`).
- `map_path` could re-map paths already under `$HOME` (e.g. homes under
  `/var/folders` hit the `/var` rule) — new rule 1b keeps under-home paths.
- `sha256_of` failed on directory pkgs (bundle `.mpkg`); now hashes contents.
- `expand_pkg` now expands the inner packages of bundle `.mpkg` dirs (pkgutil
  refuses them directly).
- **`ditto` dereferences a top-level symlink source** (copies the target as a
  real dir) — Unity's top-level `Unity Bug Reporter.app` symlink was
  materialized; merge_tree now creates top-level symlinks directly. The one
  leftover from the real install (a dir copy + launch-created `UnityLockfile`/
  `UserSettings`/`Logs`) was cleaned by hand.
- `show_redone_bom | head` SIGPIPE'd under pipefail (exit 141) — guarded.

Version bumped to **0.3.0** (feature). NOT committed; nothing pushed.
`~/Applications/Unity` is gone; record purged. Artifacts kept: the original
pkg + the rootless pkg in `~/.repkger/rootless/`.

Same session, second request: **`brew … --rpkg` alias** (user wants
`brew install --cask --rpkg unity-editor|gamemaker` to force the rootless
strategy for pkg casks and never silently run brew's `installer`/sudo).
Implemented: `--rpkg` force flag in the `repkger brew` wrapper (non-pkg
artifact → loud die, never fall through; `--cask` before or after the name),
plus a `brew()` shim appended by `repkger self-install` that strips `--rpkg`
and routes to `repkger brew`, passing every other brew call through (bash +
zsh verified). `test/roundtrip.sh` phase 4 (fake `brew` that only answers
`info`) proves: pkg cask installs rootlessly into `$HOME`, brew only ever saw
`info` (no installer path), non-pkg + `--rpkg` dies. **51/51.** Docs updated
(README, NOTES). GUI rebuilt.

Note for later: there is no official `unity-editor` brew cask — `--rpkg` works
with any cask whose artifact is a `.pkg` (e.g. `gamemaker`, `xquartz`); for
Unity, a cask would need to be added to the tap (or use the direct
`bom-redo` flow).

Fourth request, same session: **`--rpkg` now handles dmg/zip casks containing a
`.pkg`**. `cmd_brew` detects `.dmg`/`.zip` (query-stripped URL), downloads +
sha-verifies, then mounts (`hdiutil attach -readonly -mountpoint` to a temp
dir) or unzips (`unzip`, `ditto -x -k` fallback), finds the inner `.pkg`/
`.mpkg` (maxdepth 4), installs it rootlessly, and `cask_cleanup` (EXIT trap)
detaches/drops the temp dir. Containers with no pkg inside die loudly; other
extensions die loudly too (never fall through to brew's installer). Roundtrip
phase 4 now 13 checks: direct pkg, zip-with-pkg, dmg-with-pkg (incl. "volume
detached"), unsupported-artifact die, and fake-brew sees only `info`
throughout. **58/58.**

Third request, same session: **`--rpkg` passthrough in the Repkger.app GUI**.
The mode chooser now has a "Install a brew cask (--rpkg, rootless)" list item
(`doCaskPrompt` → `doCaskInstall`) plus a headless `--cask <name> [--data
<dir>]` mode, both running `repkger brew install --cask --rpkg <name>`. Along
the way FIXED a real GUI bug: the old mode chooser used a 4-button
`display dialog`, but AppleScript allows at most 3 buttons (-50 at runtime) —
replaced with `choose from list`. Verified headless: `osascript build/
Repkger.app --cask rpkgtest` against the fake brew installs rootlessly (brew
sees only `info`); `--install` regression passed; droplet stays alive showing
the list chooser (no -50). GUI rebuilt. Docs: README + NOTES item 10.

## Session update (2026-08-18) — v0.3.0 shipped manually; production app + tpl-bootkit

**Unity Editor test completed + cask pipeline live.** v0.3.0 adds `bom-redo`
(rewrite a pkg's BOM to home-mapped no-sudo locations, so extraction matches
Unity Hub's `~/Applications/Unity/Hub/Editor/<ver>` layout) and the `--rpkg`
brew flow (`brew install --cask --rpkg <cask>`; dmg/zip-with-inner-pkg now
supported). Bugs fixed en route: `ditto` dereferencing top-level symlink
sources, `component_dirs` missing Unity's `Unity.pkg.tmp`, `PackageInfo
version="0"` fallback, `/var` re-map of home paths. Roundtrip suite 58/58;
GUI gained a Cask-install mode + headless `--cask` (4-button dialog was broken
— AppleScript max is 3 — replaced with `choose from list`).

- **Cask**: `ksl-testing/homebrew-tap` now ships `Casks/unity-editor.rb`
  (arm64 MacEditorInstaller pkg, sha-verified, LTS-stream livecheck via
  `services.api.unity.com`, weekly `update-unity-editor.yml` updater) + `--map`
  passthrough in the brew wrapper. `brew install --cask --rpkg unity-editor`
  works end-to-end (verified: install, headless launch, uninstall).
- **Production app**: `~/Applications/noren/repkgr/Repkger.app` (0.3.0),
  synced by `bin/repkger.sh` in tpl-bootkit (CLI-only with `--cli`).
- **v0.3.0 published MANUALLY via gh CLI** (no Actions): `scripts/make-app.sh`
  → zip `build/Repkger.app` → `gh release create v0.3.0 --title ... --notes ...`
  with the zip attached. Re-run those same commands for the next bump.
- **Artifacts on disk**: `~/Downloads/Unity-6000.3.22f1-arm64.pkg` and
  `~/.repkger/rootless/Unity-6000.3.22f1-arm64-rootless.pkg` (~10 GB total).

## Session update (2026-08-15) — CI BLOCKED by billing; v0.2.0 published manually via gh

Checked live 2026-08-15 (`gh run list` / `gh run view`): GitHub Actions runs
never start for this account. Two runs exist on `main`:

- Run **31548908050** (push of `ff70de3`) — FAILED in `test`: the real
  admin-runner `/Applications` issue (fixed below).
- Run **31757347428** (push of `20ca6d7`, which carries the `test/roundtrip.sh`
  fix) — **job not started**: GitHub's annotation says *"recent account
  payments have failed or your spending limit needs to be increased"* — the
  Actions jobs never ran. This is an ACCOUNT/BILLING block, not a code or
  workflow issue.

So the pipeline is code-ready (28/28 locally) but Actions is unusable until
billing is fixed. **v0.2.0 was published manually through the gh CLI on
2026-08-15** (zero Actions quota): `test/roundtrip.sh` 28/28 →
`scripts/make-app.sh` → assemble `dist/` → `gh release create v0.2.0`.
Release live at `github.com/ksl-testing/repkger/releases/tag/v0.2.0` with
assets `repkger`, `repkger-0.2.0.zip`, `Repkger-0.2.0.app.zip`,
`SHA256SUMS.txt`. `TAP_TOKEN` still not set (tap formula not yet pushed).

The automation is **prepped but deferred**: `.github/workflows/release.yml`
is committed with a "WHEN THIS RUNS" header comment, and
`scripts/release-gh.sh` is a **non-working PLACEHOLDER** documenting the
manual gh-CLI steps for the future (fill it in when billing is fixed).
Re-check `gh run list --repo ksl-testing/repkger` after billing is fixed.

## Session update (2026-08-13) — committed + pushed

- **GUI upgraded for multi-file use**: `gui/Repkger.applescript` open dialog
  now supports multi-select (`choosePkgs`, `multiple selections allowed`);
  the mode chooser processes **each chosen/dropped .pkg independently**
  (Inspect or Install loop), with per-file `(i of n)` progress notifications;
  drag-drop of several .pkg files was already supported and still works.
  `doInstall` gained a `progressLabel` param (AppleScript has NO optional
  params — every call site must pass 4 args, or you get `-1721`).
- **`scripts/make-app.sh` now derives the version from `bin/repkger`'s
  `REPKGER_VERSION`** (was hardcoded 0.2.0). `build/Repkger.app` rebuilt +
  verified (bundle id, version, ad-hoc signed, embedded CLI).
- **CI round-trip fix**: `test/roundtrip.sh` phase 1 pins `--map` for
  `/Applications`, `/Library`, `/usr/local` to the scratch home — the old
  assertions assumed `/Applications` isn't writable, which is false on admin
  machines (GitHub `macos-26` runners), so the fixture landed in the REAL
  `/Applications` and 4 checks failed (run `31548908050`). Verified 28/28
  locally. **Pushing to `main` now auto-triggers the fixed release pipeline**
  (paths: bin/gui/scripts/tap/test/workflow all matched).
- **Unity Editor test material ready** (user requested a Unity Editor.app
  test): Unity **6000.3.22f1** (latest LTS) pkg fully downloaded at
  `~/Downloads/Unity-6000.3.22f1.pkg` (5,133,313,381 bytes). Source:
  `https://download.unity3d.com/download_unity/1c726e1fb402/MacEditorInstaller/Unity.pkg`
  (hash from `services.api.unity.com/unity/editor/release/v1/releases`).
  The install test itself was NOT run yet — see Pending step 1.
- **Gotcha learned**: osacompile droplets do NOT receive argv when run
  directly (`build/Repkger.app/Contents/MacOS/droplet --install …`) or via
  `open --args` — `on run argv` gets `{"current application"}` / nothing, so
  the app falls into the mode chooser dialog and hangs. The working headless
  path is `osascript build/Repkger.app --install …`. Also: a stale running
  droplet instance intercepts Apple events — `pkill -f MacOS/droplet` before
  re-testing or osascript hangs.

## Auth note (2026-08-13 incident — resolved in the 2026-08-14 sync)

The 2026-08-13 CLI push failure returned **403 "Write access not granted"**;
the user had to push manually through GitHub Desktop. The HTTPS +
`gh auth git-credential` path is now working again for this repo, and the
pending documentation/project commits are being pushed through the CLI. No
release is created by this documentation sync; release creation remains a
separate deliberate action. No SSH keys are required on this machine.

## Repos & remotes

- **repkger** (this repo): `github.com/ksl-testing/repkger`, branch `main`.
  All v0.2.0 work is committed in `ff70de3` (scope-bug fix, dequarantine
  targets+parents, GUI app, release pipeline, brew tap templates, docs).
  `.freebuff/` is tool state — never commit it. `build/` and `dist/` are
  gitignored (generated).
- **tap**: `~/homebrew/Library/Taps/ksl-testing/homebrew-tap` →
  `github.com/ksl-testing/homebrew-tap`, branch `main`. FamiStudio cask fixes
  committed (`be569b4`), updater bumped the cask to **famistudio 4.5.3**
  (`1ab3f5b`). Clean working tree.

## Release pipeline (repkger) — verify it finished

`.github/workflows/release.yml`: on push to `main` (paths: bin/gui/scripts/
tap/test/workflow) or manual `gh workflow run build-release.yml`:
**test** (fixture round-trip, 28 checks, + GUI smoke) → **build**
(`Repkger-<v>.app.zip`, `repkger-<v>.zip`, raw `repkger`, `SHA256SUMS.txt`)
→ **release** (publish/refresh `v0.2.0` + assets) → **tap update**
(`scripts/update-tap.sh`).

- The push of `ff70de3` started run **31548908050** (~00:04 UTC) which
  **FAILED** in the test job: 4 phase-1 round-trip checks, because the
  `macos-26` runner user is an admin and `/Applications` is writable, so the
  default keep-if-writable mapping kept the fixture in the real `/Applications`
  (and dequarantine then walked it — 9.5 min job). **Fixed**:
  `test/roundtrip.sh` phase 1 now pins `--map` for `/Applications`,
  `/Library`, `/usr/local` to the scratch home (deterministic on every
  machine; verified 28/28 locally).
- **Since 2026-08-15 the pipeline cannot run at all**: the re-trigger run
  (31757347428, push of `20ca6d7`) was **blocked by GitHub account
  billing** ("recent account payments have failed or your spending limit
  needs to be increased") — jobs never started. **v0.2.0 was published
  manually via the gh CLI instead** (no Actions quota) — see the 2026-08-15
  section at the top of this file; the workflow stays committed (with a
  WHEN-THIS-RUNS comment) and `scripts/release-gh.sh` is a non-working
  placeholder for the future automation.
- **Needs one secret to go live end-to-end**: add a PAT (repo scope) as the
  `TAP_TOKEN` secret on `ksl-testing/repkger`. Without it the release still
  publishes; the tap step prints a skip notice. With it,
  `brew install ksl-testing/tap/repkgr` (alias `repkger`) installs the CLI.
  The formula is generated from `tap/*.rb` templates by `scripts/update-tap.sh`
  (locally validated: `brew style` clean, `brew install` + `brew test` pass).

## FamiStudio cask — DONE, live at 4.5.3

`Casks/famistudio.rb` (tap) installs the official macOS .NET 8 build and
injects a self-healing launcher (`Contents/MacOS/main.command`):

- dotnet discovery (homebrew opt/bin chain) + graphical repair prompt
  (`install_dotnet@8.sh`) when no runtime exists.
- **Menu name fix**: prefers a bundled .NET **apphost** named `FamiStudio`
  (real Mach-O, generated in postflight via `dotnet publish` of a minimal
  project named FamiStudio) so the macOS menu reads About/Hide/Quit
  **FamiStudio**, not "dotnet". Fallback: `exec -a FamiStudio <muxer>` (fixes
  the menu-bar title only). Root cause: AppKit names those items from the
  **executable file name**; the dotnet muxer refuses to run renamed
  ("cannot execute dotnet when renamed to FamiStudio").
- **De-quarantine self-heal**: strips `com.apple.quarantine`/provenance from
  the bundle (recursive) + parent dir (non-recursive) on every launch.
- **Settings/autosaves survive upgrades**: live data lives in
  `~/Library/Application Support/FamiStudio/` (`FamiStudio.ini`, `AutoSaves/`,
  `WIP.fms`) — outside the bundle. postflight symlinks `FamiStudio.ini` +
  `AutoSaves/` into `~/Documents/FamiStudio/` (next to extracted demo files).
- **4.5.3 upgrade VERIFIED**: after `brew upgrade --cask famistudio` the
  settings ini was byte-identical (sha `4fd9d698…`), `AutoSave00.fms` intact,
  apphost regenerated, symlinks present, launch process = `FamiStudio`,
  bundle quarantine-free. Versioned snapshot at
  `~/Documents/FamiStudio/FamiStudio4.5.2.ini`.
- Also patched for the same menu-name issue: `Casks/famistudio-portable.rb`,
  `patch-famistudio.sh`.

## Livecheck/update workflows — activity-matched cadence

The tap workflows no longer run daily. Current schedules are:

| Tracker | Schedule |
|---|---|
| famistudio | weekly Monday, `17 3 * * 1` |
| freebuff-beta | weekly Tuesday, `29 3 * * 2` |
| reaper | weekly Wednesday, `23 3 * * 3` |
| kirastudio | monthly 2nd, `23 3 2 * *` (currently inert without private-repo auth) |
| tpl-bootkit | monthly 3rd, `17 3 3 * *` (currently inert without private-repo auth) |
| csp | monthly 1st, `17 3 1 * *` in `homebrew-csp` |

Every workflow retains `workflow_dispatch` for an urgent update. These Actions
only update tap metadata; they do not create or upload source-project releases.
Manual run example:
`gh workflow run update-famistudio.yml --repo ksl-testing/homebrew-tap`.

## Pending / next steps

1. ~~**Unity Editor rootless install test**~~ ✅ DONE (2026-08-18, v0.3.0) —
   full detail in the session update above + README "Validated". Both the
   original pkg and the rootless pkg are on disk if you want to re-verify;
   note the install pass takes >10 min on this machine (the 600 s CLI cap
   timed out mid-rewrite on the first attempt — re-running is idempotent).
2. **Release** — ~~publish v0.2.0~~ ✅ DONE manually via gh CLI (2026-08-15;
   no Actions quota): `gh release view v0.2.0 --repo ksl-testing/repkger`
   (assets: `Repkger-0.2.0.app.zip`, `repkger-0.2.0.zip`, raw script,
   `SHA256SUMS.txt`). STILL OPEN: add the `TAP_TOKEN` PAT (repo scope) secret
   so `scripts/update-tap.sh` can push the formula, then
   `brew install ksl-testing/tap/repkgr` on a clean machine. When billing is
   fixed, either re-enable the workflow or finish `scripts/release-gh.sh`
   (placeholder).
3. Optional tap work: `Casks/repkger.rb` (GUI app cask, depends_on formula
   "repkger") and rootless `Casks/gamemaker.rb` (pkg sha
   `8cbd33a9…cc7f`, livecheck gms.yoyogames.com RSS) — ROADMAP item 4.
   Note: the tap repo currently has an untracked `Casks/gamehub.rb` that was
   NOT created in the 2026-08-13 session — do not commit it without asking.
4. Reverse the historical v0.1.0 `~/Applications` damage — procedure in
   `llms.md` → "Old v0.1.0 damage reversal"; `repkger undo-rewrite` idea in
   ROADMAP.
5. FamiStudio user confirmation: relaunch and check the menu says
   "About/Hide/Quit FamiStudio".

## Gotchas (recurring)

- **osacompile droplets ignore argv** when launched directly or via
  `open --args`; headless automation must use `osascript <app-or-src>`.
  Kill stale droplet instances (`pkill -f MacOS/droplet`) before testing or
  Apple events route to a hung instance.
- **AppleScript handlers have no optional params** — changing a handler's
  arity breaks every call site with `-1721`; grep for all `my doInstall(`
  calls after editing.
- **AppKit menu items** follow the executable file name (not argv[0]);
  `exec -a` fixes only the menu-bar title; the dotnet muxer refuses to run
  renamed → use a real apphost.
- `HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications --no-quarantine"` lives in
  `~/.zshrc` — export it before brew cask commands in non-interactive shells.
- Avoid apostrophes in commit messages (the tool shell wrapper breaks on
  single quotes).
- repkger CLI: scratch home via `--home`, records via `REPKGER_DATA`; keeps
  `/Users/Shared` + `/tmp` in place; never walks `/` or `$HOME` recursively.
