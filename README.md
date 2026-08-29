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

Pick whichever fits how you'll use repkger:

| You want…                              | Install with…                                                                 |
|----------------------------------------|-------------------------------------------------------------------------------|
| The **CLI** on PATH (terminal)         | `brew install ksl-testing/tap/repkger`  (formula)                            |
| The **GUI app** (drag-drop)            | `brew install --cask ksl-testing/tap/repkger`  (cask) — or download `Repkger-<v>.app.zip` |
| No Homebrew at all                     | download `repkger-<v>.zip` (CLI) or `repkger` (raw script) → drop on PATH    |
| Part of the Noren/tpl-bootkit suite    | `./bin/private-casks.sh install repkger`  (resolves the latest release)      |
| Auto rootless `brew install --cask`    | `repkger self-install`  (adds `brew()`/`brewpkg()`/`rbrew()`/`rpkg()` shims) |

The tap publishes both `Formula/repkger.rb` (CLI) and `Casks/repkger.rb` (GUI app)
into `ksl-testing/homebrew-tap`, so the two `brew install` lines above always
track the latest release. Both assets are public, so brew's own downloader works
(no GitHub auth needed) — unlike the tpl-bootkit private casks. The cask's
`postflight` also symlinks the embedded CLI to `$(brew --prefix)/bin/repkger`,
so `repkger` is on PATH even from a GUI-only install.

Or grab an asset from the [GitHub releases page](https://github.com/ksl-testing/repkger/releases):

- `Repkger-<version>.app.zip` — the GUI app, drag to /Applications (ad-hoc signed)
- `repkger-<version>.zip` — the CLI (this is what the formula installs)
- `repkger` — the raw script, just drop it on your PATH
- `SHA256SUMS.txt` — checksums for the above

**How the pipeline works:** every push to `main` that touches repkger sources
runs the test suite (fixture round-trip + GUI build) on macOS, then publishes a
GitHub release tagged `v<REPKGER_VERSION>` with those assets, and refreshes the
`ksl-testing/homebrew-tap` formula + cask (`Formula/repkger.rb`,
`Casks/repkger.rb`) so `brew install ksl-testing/tap/repkger` and
`brew install --cask ksl-testing/tap/repkger` always get the latest build.

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
 brew install --cask gamemaker                                 # same, with the brew() shim (auto rootless)
 repkger brew link gamemaker                                   # make it appear in `brew list --cask`
bin/repkger gui                                                 # open the Repkger.app GUI (Python/Tk)
bin/repkger self-install                                        # ~/bin symlink + brew()/brewpkg()/rbrew()/rpkg() shims
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

The GUI is a real windowed front-end (Python/Tk), **not** the old AppleScript
droplet — the droplet mishandled launch/droplet `argv` and errored on open. The
Python app gets clean `argv`, so double-click, Finder drag-drop onto the icon,
and "Open With" all work.

```bash
scripts/make-gui-app.sh                       # -> build/Repkger.app
open -a build/Repkger.app                     # windowed mode chooser
open -a build/Repkger.app some.pkg            # pre-loads the dropped pkg(s)
python3 gui/repkger_gui.py --smoketest x.pkg  # headless: prints the repkger command it would run
```

The app is self-contained: `Contents/MacOS/repkger-gui` (the Python GUI) plus
`Contents/Resources/repkger` (the embedded CLI), so it runs without repkger on
PATH. Modes in the chooser: **install** a `.pkg`/`.mpkg`/`.dmg`/`.zip`/`.bundle`,
**inspect** (file list + where each file lands), **bom-redo** (predictive BOM +
rewrite plan, preview), **brew cask** (rootless install of `--cask <name>`), and
**uninstall** a recorded install. There's a Finder file-chooser, a target-dir
picker, and options for `--run-scripts`, `--home-rooted`, and `--only <prefix>`.
The bundle registers `.pkg`/`.mpkg`/`.dmg`/`.zip`/`.bundle` as document types, is
ad-hoc signed, and the quarantine is cleared on build.

`make-gui-app.sh` assembles it: writes `Contents/Info.plist`
(`CFBundleExecutable` = `repkger-gui`, document types), copies in the CLI + GUI,
`codesign -s -`, strips `com.apple.quarantine`, and `lsregister`s it.

Drop `gui/NorenHodoki.icns` into the repo for a custom icon (used when
`APP_NAME="Noren Hodoki" scripts/make-gui-app.sh`). The AppleScript droplet
source `gui/Repkger.applescript` and `scripts/make-app.sh` are kept for the
Noren Suite build below.

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
bash test/roundtrip.sh                     # 112 checks: install -> uninstall round-trip + bom-redo + --rootless
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

## Rootless cask installs (`brew install --cask`)

Casks whose downloaded artifact is a `.pkg` normally install via brew's `pkg`
DSL, which runs `installer` and prompts for an admin password. repkger's brew
wrapper intercepts those automatically — **`brew install --cask <name>` always
installs pkg/dmg/zip casks rootlessly** (no `--rpkg` needed). Add
**`--rootless`** (alias `--rpkg`, or `-r`) to make that the *only* behavior for a
cask — it never falls through to brew's installer and errors out (instead of
silently running it) if the artifact isn't a `.pkg`. `--rootless` also handles
**dmg/zip casks that contain a `.pkg`/`.mpkg` inside**: the archive is downloaded
+ hash-verified, mounted (`hdiutil attach -readonly`) or unzipped, the inner
package is installed rootlessly, and the mount/extract dir is cleaned up. Any
other artifact type — or a container with no `.pkg` inside — fails loudly:

```bash
repkger self-install                 # symlink into ~/bin + brew()/brewpkg()/rbrew()/rpkg() shims in ~/.zshrc
brew install --cask gamemaker        # -> rootless repkger install, no sudo (DEFAULT)
repkger brew install --cask gamemaker
brew install --cask --rootless gamemaker     # -r is a shorthand for --rootless
repkger brew install --cask --rootless gamemaker
brewpkg install --cask gamemaker             # the pre-existing wrapper (no brew() shim)
rbrew install --cask gamemaker               # = repkger brew --rootless (standalone)
rpkg install ~/Downloads/Foo.pkg             # = repkger (standalone CLI alias)
```

The `brew()` shim (added by `repkger self-install`) routes `brew install --cask
<name>` through repkger by default and passes every other `brew` call straight
through to the real Homebrew. `-r`/`--rootless`/`--rpkg` are the force flags.

### Showing rootless casks in `brew list`

A rootless install doesn't write a Homebrew receipt, so `brew list` won't know
about it. `repkger brew link <cask>` writes a Caskroom receipt
(`~/homebrew/Caskroom/<cask>/<ver>/<app>.app` symlink + `.metadata/
INSTALL_RECEIPT.json`) so the install shows up under `brew list --cask <cask>`
and `brew info --cask <cask>` — handy for tracking what you installed rootlessly.
`repkger brew install --cask <name>` links automatically; `repkger brew link` /
`repkger brew unlink <cask>` manage it by hand. This never invokes brew's
installer — it only symlinks the already-installed app into the Caskroom.

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
