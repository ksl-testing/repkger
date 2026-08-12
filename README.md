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
bin/repkger inspect  ~/Downloads/GameMaker-2024.14.4.222.pkg   # read it like Suspicious Package
bin/repkger inspect  ~/Downloads/GameMaker-2024.14.4.222.pkg --files 25   # + where each file lands
bin/repkger install  ~/Downloads/GameMaker-2024.14.4.222.pkg   # home-rooted install
bin/repkger list                                                # installed records
bin/repkger uninstall com.yoyogames.gms2 --yes                  # reverse an install
bin/repkger brew --cask gamemaker                               # rootless install of a pkg-style cask
bin/repkger gui                                                 # open the Repkger.app GUI
bin/repkger self-install                                        # symlink into ~/bin + brewpkg() in ~/.zshrc
```

## Quick start (GUI)

```bash
scripts/make-app.sh                       # builds build/Repkger.app
open -a build/Repkger.app                 # mode chooser (Inspect / Install / Uninstall)
open -a build/Repkger.app some.pkg        # or drop .pkg files on the app icon
```

Dropping a package on the app shows a Suspicious Package-style inspection
(components, scripts, BOM entries with their home-mapped destinations), then
offers Install / Full Report / Cancel. Install runs the CLI with `--home $HOME`
and posts a notification when done. The CLI is embedded in the app bundle
(`Contents/Resources/repkger`), so the app works without repkger on PATH.

## Validated

- **GameMaker 2024.14.4.222** (single component `com.yoyogames.gms2`,
  `/Applications`, 17,480 BOM entries, ~800 MB payload): `inspect` + `install`
  + `uninstall` all verified end-to-end (2026-08-10, v0.1.0).
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
- **Daily livecheck**: `.github/workflows/update-famistudio.yml` bumps the
  cask's `version`/`sha256` once a day (and on demand via
  `gh workflow run update-famistudio.yml`), verifying the downloaded asset
  against GitHub's published digest.

## Roadmap / status

See `llms/ROADMAP.md` and `llms/STATUS.md`. The v0.1.0 rewrite/codesign scope
bug is **fixed** in v0.2.0; the historical damage to `~/Applications` from the
v0.1.0 install is still waiting to be reversed (see `llms.md` → "TODO first").
