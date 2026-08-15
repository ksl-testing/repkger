# HANDOFF — repkger + ksl-testing/tap (written 2026-08-11)

A cacheless agent can pick up from this file. Read `README.md`, `llms.md`,
`llms/STATUS.md`, `llms/ROADMAP.md`, and `NOTES.md` for depth; this is the
state + next steps.

## Session update (2026-08-15) — CI runs BLOCKED by GitHub billing; no release yet

Checked live 2026-08-15 (`gh run list` / `gh run view`): the fixed pipeline
has NOT produced a release. Two runs exist on `main`:

- Run **31548908050** (push of `ff70de3`) — FAILED in `test`: the real
  admin-runner `/Applications` issue (fixed below).
- Run **31757347428** (push of `20ca6d7`, which carries the `test/roundtrip.sh`
  fix) — **job not started**: GitHub's annotation says *"recent account
  payments have failed or your spending limit needs to be increased"* — the
  Actions jobs never ran. This is an ACCOUNT/BILLING block, not a code or
  workflow issue.
- `gh release view v0.2.0` → **release not found**. `TAP_TOKEN` still not set.

So the pipeline is code-ready (28/28 locally) but GitHub Actions is currently
unusable for this account. Until billing is resolved, publish manually from
this Mac (no Actions minutes):

```bash
# build assets the way the workflow would (make-app.sh + CLI zip + SHA256SUMS)
# then, from inside the repo:
gh release create v0.2.0 <Repkger-0.2.0.app.zip> <repkger-0.2.0.zip> <repkger> <SHA256SUMS.txt>
# or refresh an existing release with gh release upload
# then push the formula:
#   add a PAT as the TAP_TOKEN secret on ksl-testing/repkger, then
scripts/update-tap.sh   # renders tap/repkgr.rb + repkger.rb alias → ksl-testing/homebrew-tap
```

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
  needs to be increased") — jobs never started. `v0.2.0` does NOT exist yet.
  See the 2026-08-15 section at the top of this file for the manual
  publish path and the billing re-check.
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

1. **Unity Editor rootless install test** (user request; pkg is ready at
   `~/Downloads/Unity-6000.3.22f1.pkg`). Verify sha256 first, then:
   `bin/repkger inspect <pkg> --files 15`, then
   `bin/repkger install <pkg> --home $HOME --yes` (this lands
   `~/Applications/Unity/Hub/Editor/6000.3.22f1/Unity.app` or similar —
   confirm the actual payload layout with `inspect --files` first), launch
   the editor once (`open ~/Applications/…/Unity.app`), then `repkger list` +
   `repkger uninstall` to verify reversal. The pkg is ~5 GB so give the
   CLI 10+ min; the GUI's `doInstall` timeout is 3600 s.
2. **Release**: this session's push auto-triggers the fixed pipeline. Verify
   `gh run list`, then `gh release view v0.2.0 --repo ksl-testing/repkger`
   (assets: `Repkger-0.2.0.app.zip`, `repkger-0.2.0.zip`, raw script,
   `SHA256SUMS.txt`). Add the `TAP_TOKEN` PAT (repo scope) secret so
   `scripts/update-tap.sh` can push the formula, then
   `brew install ksl-testing/tap/repkgr` on a clean machine.
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
