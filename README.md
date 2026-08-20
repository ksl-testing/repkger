# repkger — rootless macOS .pkg unpacker / installer (no admin, no sudo)

Unpacks the contents of **any** Apple installer `.pkg` into locations the current
user can actually write to. Default behavior: keep system locations the user can
already write to (e.g. `/Users/Shared`), re-target everything else to `~/`
equivalents (`/Applications` → `~/Applications`, `/Library` → `~/Library`,
`/usr/local` → `~/.local`, ...). No `installer`, no GUI installer, no
escalation — works even on privilege-locked accounts. After unpacking, the
quarantine attribute is stripped from each target **and its parent dir**
(`xattr -dr com.apple.quarantine`, falling back to clearing all xattrs), so
Gatekeeper won't flag the freshly installed apps.

## Install

```bash
brew install ksl-testing/tap/repkgr        # CLI (alias: ksl-testing/tap/repkger)
```

Or grab an asset from the [GitHub releases page](https://github.com/ksl-testing/repkger/releases):

- `Repkger-<version>.app.zip` — the GUI app, drag to /Applications (ad-hoc signed)
- `repkger-<version>.zip` — the CLI (this is what brew installs)
- `repkger` — the raw script, just drop it on your PATH
- `SHA256SUMS.txt` — checksums for the above

**How the pipeline works:** every push to `main` that touches repkger sources
runs the test suite (fixture round-trip + GUI build) on macOS, then publishes a
GitHub release tagged `v<REPKGER_VERSION>` with those assets, and refreshes the
`ksl-testing/homebrew-tap` formula (`tap/repkgr.rb`) so `brew install
ksl-testing/tap/repkgr` always gets the latest build. Run it manually any time
from anywhere: `gh workflow run build-release.yml` (or the repo's Actions tab
on the web / mobile app).

## Quick start (CLI)

```bash
bin/repkger inspect  ~/Downloads/GameMaker-2026.0.0.16.pkg   # read it like Suspicious Package
bin/repkger inspect  ~/Downloads/GameMaker-2026.0.0.16.dmg   # auto-mounts DMG, finds inner .pkg
bin/repkger inspect  ~/Downloads/GameMaker.zip               # extracts zip, finds inner .pkg
bin/repkger inspect  ~/Downloads/GameMaker.app               # .bundle — works as-is (flat XAR)
bin/repkger inspect  ~/Downloads/GameMaker-2026.0.0.16.pkg --files 25   # + where each file lands
bin/repkger install  ~/Downloads/GameMaker-2026.0.0.16.dmg   # home-rooted install from .dmg
bin/repkger install  ~/Downloads/GameMaker-2026.0.0.16.dmg --run-scripts  # sanitize & run pre/postinstall
bin/repkger bom-redo ~/Downloads/GameMaker-2026.0.0.16.pkg   # repack BOM+payload to ~/ locations
bin/repkger bom-redo ~/Downloads/GameMaker-2026.0.0.16.pkg --preview   # predictive BOM first (like Suspicious Package), builds nothing
bin/repkger bom-redo ~/Downloads/GameMaker-2026.0.0.16.pkg --only /Applications   # targeted: only that subtree
bin/repkger install  ~/Downloads/GameMaker-2026.0.0.16.pkg --only /Applications   # targeted direct extraction
bin/repkger list                                                # installed records
bin/repkger uninstall com.yoyogames.gms2 --yes                  # reverse an install
bin/repkger brew --cask gamemaker                               # rootless install of a pkg-style cask
brew install --cask --rpkg gamemaker                            # same, with the brew() shim alias
bin/repkger gui                                                 # open the Repkger.app GUI
bin/repkger self-install                                        # symlink into ~/bin + brewpkg() in ~/.zshrc
```

## Build it yourself

Everything is plain bash + AppleScript + Apple's built-in tools (`pkgutil`,
`pkgbuild`, `xar`, `lsbom`, `xattr`, `codesign`, `osacompile`, `PlistBuddy`,
`ditto`) — **no Xcode, no third-party deps, no network**. Any macOS with the
Command Line Tools installed will do.

### The CLI

There is nothing to compile: `bin/repkger` is the whole CLI in one bash
script (macOS bash 3.2 compatible). Drop it on your `PATH` (or
`./bin/repkger self-install`) and it runs.

### The GUI app (`Repkger.app`)

```bash
scripts/make-app.sh                       # -> build/Repkger.app
open -a build/Repkger.app                 # mode chooser (see below)
open -a build/Repkger.app some.pkg        # or drop .pkg files on the app icon
osascript build/Repkger.app --cask gamemaker   # headless: rootless cask install (--rpkg)
```

The app is self-contained (the CLI lives inside the bundle) and portable —
drag it anywhere, even off a USB stick. It processes packages **independently**:
drop several `.pkg` files on the icon, or open the app and pick one or many
files (Cmd-click to multi-select in the open dialog) — each one is inspected
or installed on its own, with `(1 of N)` progress notifications, and a failure
on one doesn't stop the rest. The mode chooser is a list: install a `.pkg`,
inspect a `.pkg`, uninstall an installed one, or **install a brew cask
rootlessly** (prompts for the cask name and runs `repkger brew install --cask
--rpkg <name>` — never brew's pkg installer, no sudo). Headless:
`--install <pkg> [--home dir] [--data dir]`, `--inspect <pkg>`, and
`--cask <name> [--data dir]`.

`make-app.sh` does the whole assembly:

1. `osacompile`s the droplet source `gui/Repkger.applescript` into
   `build/Repkger.app`;
2. embeds `bin/repkger` into `Contents/Resources/repkger` so the app works
   without repkger on PATH;
3. stamps the bundle id `com.ksl-testing.repkger` + version (read from
   `bin/repkger`'s `REPKGER_VERSION`) and registers `.pkg`/`.mpkg` as
   document types via `PlistBuddy`;
4. ad-hoc signs the bundle (`codesign -s -`).

Drop `gui/Repkger.icns` into the repo to give the app a custom icon (it's
picked up automatically). The result is a standard macOS bundle — drag it to
`/Applications`, zip it, or run it straight from `build/`.

### Noren Hodoki (Noren Suite plugin build)

repkger is the engine; **Hodoki (ほどき / 解き)** is the Noren Suite face of that
engine — the "unwrapping" module for rootless package extraction at the
threshold.

**Brand assets** (from tpl-bootkit `branding/icons/`):
- Icon: `gui/NorenHodoki.icns` (kuchinashi gradient `#E07B4E`→`#B85030`, unwrapping knot glyph)
- Gradient: Kuchinashi (梔子) — warm coral-terracotta, the color of reveal
- Glyph: Open box flaps + releasing knot (untie, don't cut)

**Build the Noren Hodoki app**:
```bash
APP_NAME="Noren Hodoki" DISPLAY_NAME="Noren Hodoki" \
BUNDLE_ID=com.noren-hodoki.app \
INSTALL_DIR="$HOME/Applications/Noren Hodoki" \
./scripts/make-app.sh
# -> ~/Applications/Noren Hodoki/NorenHodoki.app
```

**Current status (v0.4.0):**
- ✅ Icon + build pipeline + post-build quarantine stripping
- ✅ Configurable bundle ID (`com.noren-hodoki.app` target)
- ✅ Installs to `~/Applications/Noren Hodoki/` via `INSTALL_DIR`
- ⚠️ Runtime integration **pending** — the app launches but the AppleScript
  mode chooser still shows "Repkger" labels; Hodoki-specific actions not yet wired
- ⚠️ `noren hodoki` CLI alias not yet added to `bin/repkger`

See tpl-bootkit `branding/HODOKI_BRIEF.md` for full brand identity.

### Running the tests

```bash
test/make-fixture.sh                       # builds a tiny mini.pkg (no downloads)
bash test/roundtrip.sh                     # 51 checks: install -> uninstall round-trip + bom-redo + --rpkg
```

### Building the distributable artifacts

The GitHub Actions workflow (`.github/workflows/release.yml`) does exactly
this on every push to `main` (or `gh workflow run build-release.yml`): run
`test/roundtrip.sh`, build the app with `make-app.sh`, then zip up
`Repkger-<v>.app.zip` + `repkger-<v>.zip` + the raw script + `SHA256SUMS.txt`
and publish them as a GitHub release — same commands you can run by hand.

Dropping a package on the app shows a Suspicious Package-style inspection
(components, scripts, BOM entries with their home-mapped destinations), then
offers Install / Full Report / Cancel. Install runs the CLI with `--home $HOME`
and posts a notification when done. The CLI is embedded in the app bundle
(`Contents/Resources/repkger`), so the app works without repkger on PATH.

## Validated

- **GameMaker 2024.14.4.222** (single component `com.yoyogames.gms2`,
  `/Applications`, 17,480 BOM entries, ~800 MB payload): `inspect` + `install`
  + `uninstall` all verified end-to-end (2026-08-10, v0.1.0).
- **Unity Editor 6000.3.22f1 (Apple silicon)** (2026-08-18, v0.3.0): the full
  Unity-Hub-parity flow, done by **redoing the BOM**. Downloaded the
  `MacEditorInstallerArm64/Unity-6000.3.22f1.pkg` (5,107,849,173 bytes;
  md5 matches Unity's published digest `revO9paHvxhkIn7BzWb6BA==`, sha256
  `a60e4a44…98d6a`) → `repkger bom-redo … --map
  "/Applications/Unity/Unity=$HOME/Applications/Unity/Hub/Editor/6000.3.22f1"`
  → a single flat rootless pkg whose BOM + payload are rooted at
  `~/Applications/Unity/Hub/Editor/6000.3.22f1` (byte-for-byte the layout
  Unity Hub produces when you pick `~/Applications`) → `repkger install` of
  that pkg (no `--map` needed; every destination is already under `$HOME`)
  → 55,077 files landed, 201 stale `/Applications/Unity/…` refs rewritten,
  editor launched headless once (`-batchmode -quit`; connected to the
  licensing client, exited cleanly with the expected unlicensed message) →
  `repkger uninstall` reversed everything. Unity quirk handled: the inner
  component is `Unity.pkg.tmp` and its `PackageInfo` version is `0` (the real
  version lives in the Distribution) — both now handled by repkger.
- **Synthetic fixture** (fast, no downloads): `test/make-fixture.sh` builds a
  tiny `mini.pkg` covering `/Applications` (+ a real `.app` bundle with stale
  path refs, a symlink, a `--prefix=`-style ref), `/Library`,
  `/usr/local/bin`, `/Users/Shared`, `/tmp`, and pre/postinstall scripts.
  Validated against it (2026-08-11, v0.2.0):
  - rewrite is scoped to the package's own files only (a decoy app pre-placed
    in the scratch home is never touched — the old v0.1.0 bug);
  - rewrite handles nesting correctly (`/usr/local/bin` → `~/.local/bin`,
    `/usr/bin:/bin` PATH lists, `/private/var` → `~/var`, spaces in paths,
    `--prefix=` refs) and is idempotent;
  - quarantine stripped from merged targets **and** parent dirs
    (`~/Applications` itself in the fixture);
  - `/Users/Shared` + `/tmp` payloads kept in place and cleaned up on
    uninstall; `_CodeSignature` artifacts from ad-hoc re-signing are recorded
    so uninstall reverses everything.
- Dry-run (`--list-only`) shows the exact mapping without touching anything.

## Design

- **Container resolution** (`resolve_pkg_input`): auto-detects `.pkg`, `.mpkg`,
  `.bundle` (flat XAR), `.dmg` (mounts read-only, finds inner `.pkg`),
  `.zip` / `.tar*` (extracts to temp dir), or a directory containing a `.pkg`.
  DMG mounts and temp dirs are cleaned up automatically via EXIT trap.
- Expand: `pkgutil --expand-full` (extracts payloads to dirs; handles modern
  compression). Fallback: `xar` + manual `gunzip|cpio` / `pbzx`.
- Map: user `--map SRC=DEST` > keep-if-writable > world-writable-keep
  (`/Users/Shared`, `/tmp`) > home-rooted defaults.
- Merge: tree-walk that remaps only at mapping boundaries, `ditto` whole
  subtrees (preserves symlinks/AppleDouble/perms).
- Rewrite: one perl pass over each path reference token — the longest stale
  prefix wins and the whole remaining token is consumed as a verbatim tail, so
  shorter roots in tails (`/bin` in `/usr/local/bin`, `/var` in
  `/private/var`) are never re-matched. Idempotent.
- Dequarantine: `xattr -dr com.apple.quarantine` on every merged dir and every
  mapped install-location dir (recursive), **plus** a non-recursive strip of
  each one's parent dir (a quarantined parent re-infects anything copied into
  it); falls back to clearing all xattrs if the attribute won't come off.
- Scope: rewrite/resign/dequarantine operate only on the package's own landed
  files, derived from the BOM — never a scan of the mapped dirs.
- Record: `~/.repkger/records/<id>-<ver>-<sha8>/record.tsv` — the BOM of what
  actually landed (skips `._*` AppleDouble that pkgutil folds into xattrs) →
  deterministic `uninstall`.
- **BOM redo** (`bom-redo`): walks the payload with the same boundary logic as
  the merge, and for each mapping boundary re-runs `pkgbuild --root <subtree>
  --install-location <mapped-dir>` (plus a minimal Distribution when there are
  several leaves). The result is a rootless `.pkg`/`.mpkg` whose **BOM and
  payload are already rooted at the accessible no-sudo locations** — installing
  it is a plain extraction with nothing re-mapped (and no stale refs to fix,
  since the rewrite is idempotent anyway). E.g. the Unity editor pkg becomes a
  pkg that installs directly to `~/Applications/Unity/Hub/Editor/<ver>/`,
  exactly like Unity Hub with `~/Applications` selected.
- **Predictive BOM** (`bom-redo --preview` / `--list-only`): Suspicious
  Package-style preview of the redone package BEFORE anything is built — every
  mapping-boundary leaf with its home-mapped destination, a sample of the
  predicted BOM entries (path → `~/` dest), predicted entry counts, and the
  script estimates. Nothing is written (no pkgbuild).
- **Targeted multi-level extraction** (`--only PREFIX`, on `bom-redo` and
  `install`): extract only payload paths at/under PREFIX (absolute, or
  relative to the component's install-location; repeatable). E.g.
  `--only /Applications/Unity/Unity` on the Unity pkg redoes just the editor
  subtree; `bom-redo --only /Applications` yields a single flat rootless
  `.pkg` instead of a multi-leaf `.mpkg`. Paths that don't match are pruned
  at every level, so nested boundaries (e.g. `/Library` inside
  `/Applications/Unity`) are honored.
- **Script adjustment** (`bom-redo`): the embedded pre/post-install scripts
  are rewritten so their absolute path references match the new (home-mapped)
  BOM — `mkdir -p /Applications/…` becomes `mkdir -p ~/Applications/…`,
  `/Library/…` → `~/Library/…`, `/usr/local/…` → `~/.local/…`. The
  pure system-tool dirs (`/usr`, `/bin`, `/sbin`) are deliberately left alone
  so `#!/bin/sh` and `/usr/bin/env` still resolve, and the shebang line is
  preserved. `--preview` shows the estimate (refs home-mapped + any lines
  that still need privileges and cannot be mapped: sudo/chown-root/
  launchctl/installer/System).
- **Script inspection** (default in `inspect`): Suspicious Package-style
  output — each script shows Name, Kind, Size, As User (from `auth`
  attribute), When (inferred from script name), and line-numbered content.
  Lines with `sudo`, `chown root`, `launchctl`, `/System/` paths are
  flagged with warnings. Use `--no-scripts` to suppress.
- **Script sanitization** (`--run-scripts`): pre/post-install scripts are
  sanitized for rootless execution before running — `sudo` prefixes are
  stripped, `launchctl`/`installer`/`chown root`/`/System/` writes are
  commented out, binary scripts are copied untouched. Path references are
  rewritten to match the home-mapped locations. Scripts run in a
  home-rooted environment (`DSTROOT`, `HOME`, etc.).
- Scripts: never run by default; recorded (name + md5) for auditing;
  `--run-scripts` opts in.

## Testing

```bash
test/make-fixture.sh                        # -> /tmp/repkger-fixture/mini.pkg
bin/repkger inspect /tmp/repkger-fixture/mini.pkg --files 10
rm -rf /tmp/rk-home /tmp/rk-data
REPKGER_DATA=/tmp/rk-data bin/repkger install /tmp/repkger-fixture/mini.pkg --home /tmp/rk-home --yes
REPKGER_DATA=/tmp/rk-data bin/repkger uninstall com.test.miniapp --yes
find /tmp/rk-home | wc -l                  # expect 1
```

## Forcing rootless extraction for pkg casks (`brew … --rpkg`)

Casks whose downloaded artifact is a `.pkg` normally install via brew's `pkg`
DSL, which runs `installer` and prompts for an admin password. repkger's brew
wrapper intercepts those automatically; add **`--rpkg`** to make that the
*only* behavior for a cask — it never falls through to brew's installer and
errors out (instead of silently running it) if the artifact isn't a `.pkg`.
`--rpkg` also handles **dmg/zip casks that contain a `.pkg`/`.mpkg` inside**:
the archive is downloaded + hash-verified, mounted (`hdiutil attach -readonly`)
or unzipped, the inner package is installed rootlessly, and the mount/extract
dir is cleaned up (no leftover volumes). Any other artifact type — or a
container with no `.pkg` inside — fails loudly:

```bash
repkger self-install                 # installs the brew() shim into ~/.zshrc
brew install --cask --rpkg gamemaker # -> rootless repkger install, no sudo
# without the shim, the same thing works as:
repkger brew install --cask --rpkg gamemaker
# or the pre-existing wrapper:
brewpkg install --cask gamemaker
```

The `brew()` shim passes every other `brew` call straight through to the real
Homebrew — it only intercepts invocations that contain `--rpkg`.

## FamiStudio cask (ksl-testing/tap) — integration showcase

`brew install --cask ksl-testing/tap/famistudio` installs the official macOS
build of FamiStudio (a .NET 8 app) and rewrites its launcher so it runs
rootlessly on a user-space runtime. The cask lives in `ksl-testing/homebrew-tap`
(templates/notes in this repo under `tap/`). Highlights of the self-healing
launcher it injects:

- **Menu name**: prefers a bundled .NET **apphost** named `FamiStudio` (a real
  Mach-O generated at install via `dotnet publish`) so the macOS menu reads
  "About/Hide/Quit **FamiStudio**" instead of "**dotnet**" — AppKit names
  those items from the executable *file name*, which the `dotnet` muxer can't
  provide (renaming it is blocked by .NET itself). `exec -a` fixes only the
  menu-bar title.
- **De-quarantine self-heal**: strips `com.apple.quarantine`/provenance from
  the bundle (recursive) + parent dir (non-recursive) on every launch — the
  same target+parent rule repkger applies to installed packages.
- **Settings/autosaves survive upgrades**: live data lives in
  `~/Library/Application Support/FamiStudio/` (outside the .app, so app
  upgrades never touch it); the cask postflight symlinks `FamiStudio.ini` +
  `AutoSaves/` into `~/Documents/FamiStudio/` next to the demo files it
  extracts, re-linking after every update.
- **Scheduled livecheck**: the associated tap's
  `.github/workflows/update-famistudio.yml` checks FamiStudio weekly on Monday
  (and remains available on demand via `gh workflow run update-famistudio.yml`),
  verifying the downloaded asset against GitHub's published digest. The tap's
  other trackers are weekly or monthly according to their source activity;
  these workflows update cask metadata only and do not publish releases.

## Roadmap / status

See `llms/ROADMAP.md` and `llms/STATUS.md`. The v0.1.0 rewrite/codesign scope
bug is **fixed** in v0.2.0; the historical damage to `~/Applications` from the
v0.1.0 install is still waiting to be reversed (see `llms.md` → "TODO first").
