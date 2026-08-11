# NOTES — dev notes for repkger

## Architecture (single-file bash CLI)

1. **Expand**: `pkgutil --expand-full <pkg> <dir>` extracts payloads into
   directories (`<comp>.pkg/Payload/` as a dir), leaves `Bom`, `Scripts/`,
   `PackageInfo`. Fallback: `xar -xf` + manual `gunzip|cpio` (or `pbzx`).
2. **Map** (`map_path`): user `--map` (longest prefix) → keep-if-writable
   (top-level dir `-w` check) → always-keep (`/Users/Shared`, `/tmp`) →
   home-rooted defaults (`/Applications`→`$ROOT/Applications`,
   `/Library`→`$ROOT/Library`, `/usr/local`→`$ROOT/.local`, `/usr`→`$ROOT/.usr`,
   `/etc`,`/var`,`/opt`,`/bin`,`/sbin`→under `$ROOT`, `/private*`→stripped).
3. **Merge** (`merge_tree`): walks the payload tree with virtual absolute
   paths; remaps only where a mapping boundary lies *below* the current node
   (`case "$b" in "$vc/"*)`); dittos whole subtrees otherwise.
4. **Rewrite** (`rewrite_tree`/`rewrite_one`): perl -pi with OLD\034NEW pairs;
   protect-new → convert-old → restore-new (idempotent); text via
   `grep -rlIFf`, plists via `plutil` convert. ⚠️ currently scoped too broadly
   (see llms.md) — must be restricted to the package's own files.
5. **Sign**: strip `com.apple.quarantine`, `codesign --verify --deep --strict`,
   deep ad-hoc re-sign failures. Same scope warning.
6. **Record**: `~/.repkger/records/<name>-<ver>-<sha8>/record.tsv` —
   header (pkg, sha, name, ver, installed_at, home_root, user_maps),
   `component\tid\tver\tloc`, `script\tid\tname\tmd5`,
   `file\tdst\ttype\tmode\tuidgid\tsize` (only entries that exist on disk).
   `uninstall` deletes files deepest-first, rmdir recorded dirs, then the
   mapped install-location dirs.
7. **brew wrapper**: parses `brew info --cask X --json=v2`; if url is a
   `.pkg`/`.mpkg`, downloads to `~/.repkger/downloads`, verifies sha256,
   calls `install`; else execs real brew.

## macOS gotchas learned (expensive lessons)

- `pkgutil --expand-full` errors "File exists" if the destination dir exists →
  `rm -rf` first.
- BSD sed: no `\b`; attribute regex must be `<tag[^>]* attr=` (with the space).
- `lsbom` = tab-separated, paths may contain spaces → `awk -F'\t'`.
- BOM contains `._*` AppleDouble entries that `--expand-full` folds into
  xattrs → record only paths that exist.
- bash 3.2: `set -u` + empty arrays → use `${arr[@]+"${arr[@]}"}`.
- EXIT traps need globals (locals die with the function).
- `xattr ... && say` under `set -e` → silent abort on failure; use if/else.
- TCC `com.apple.macl` write-protects launched app bundles — clear once with
  `sudo xattr -rd com.apple.macl "<app dir>"` (repkger detects + prints hint).
- Brew cask DSL: `installer manual:` prints instructions only; `installer
  script:` executes as current user (`reset_uid`); `depends_on formula:` valid.

## Test fixture

GameMaker 2024.14.4.222 (`~/Downloads/repkger-test/GameMaker-2024.14.4.222.pkg`,
sha256 `8cbd33a9a92ed60ebd53734413b33afdeb8c677326ada0c80971e9f91555cc7f`).
Single component `com.yoyogames.gms2`, install-location `/Applications`,
17,480 BOM entries, ~800 MB payload, preinstall commented out, postinstall
only chmods `/Users/Shared/GameMakerStudio2` dirs. Note: `postinstall-e` /
`preinstall-e` variants exist (arch-specific copies), payload also contains
`Alice.gmplugin-e`-style `-e` files — those are real files, do not filter.
