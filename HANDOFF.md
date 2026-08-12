# HANDOFF — repkger + ksl-testing/tap (written 2026-08-11)

A cacheless agent can pick up from this file. Read `README.md`, `llms.md`,
`llms/STATUS.md`, `llms/ROADMAP.md`, and `NOTES.md` for depth; this is the
state + next steps.

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

- The push of `ff70de3` started run **31548908050** (~00:04 UTC); it was
  still in progress at handoff. Check:
  `gh run watch 31548908050 --repo ksl-testing/repkger` then
  `gh release view v0.2.0 --repo ksl-testing/repkger`.
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

## Livecheck/update workflows — now daily

All tap updaters run once daily UTC (down from 2x/week / 2x/day):
famistudio `17 3 * * *`, tpl-bootkit `17 3 * * *`, kirastudio `23 3 * * *`,
reaper `23 3 * * *`, freebuff-beta `29 3 * * *`. Manual run:
`gh workflow run update-famistudio.yml --repo ksl-testing/homebrew-tap`
(updater verifies sha256 against GitHub's asset digest, bumps the cask,
commits, pushes).

## Pending / next steps

1. Confirm release run `31548908050` → `gh release view v0.2.0`; add the
   `TAP_TOKEN` secret; then `brew install ksl-testing/tap/repkgr` on a clean
   machine.
2. Optional tap work: `Casks/repkger.rb` (GUI app cask, depends_on formula
   "repkger") and rootless `Casks/gamemaker.rb` (pkg sha
   `8cbd33a9…cc7f`, livecheck gms.yoyogames.com RSS) — ROADMAP item 4.
3. Reverse the historical v0.1.0 `~/Applications` damage — procedure in
   `llms.md` → "Old v0.1.0 damage reversal"; `repkger undo-rewrite` idea in
   ROADMAP.
4. FamiStudio user confirmation: relaunch and check the menu says
   "About/Hide/Quit FamiStudio".

## Gotchas (recurring)

- **AppKit menu items** follow the executable file name (not argv[0]);
  `exec -a` fixes only the menu-bar title; the dotnet muxer refuses to run
  renamed → use a real apphost.
- `HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications --no-quarantine"` lives in
  `~/.zshrc` — export it before brew cask commands in non-interactive shells.
- Avoid apostrophes in commit messages (the tool shell wrapper breaks on
  single quotes).
- repkger CLI: scratch home via `--home`, records via `REPKGER_DATA`; keeps
  `/Users/Shared` + `/tmp` in place; never walks `/` or `$HOME` recursively.
