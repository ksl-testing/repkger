# repkger — rootless .pkg installer for macOS (GUI app, no admin, no sudo).
#
# TEMPLATE — the published copy in ksl-testing/homebrew-tap is generated from
# this file by scripts/update-tap.sh (triggered by .github/workflows/release.yml).
# The url / sha256 / version tokens are substituted at publish time.
#
#   brew install --cask ksl-testing/tap/repkger
#
# Docs: https://github.com/ksl-testing/repkger

cask "repkger" do
  version "__VERSION__"
  # The .app lives in a public release asset, so brew's downloader works
  # (unlike the tpl-bootkit private casks, which need gh-authenticated recovery).
  url "__URL_APP__"
  name "Repkger"
  desc "Unpacks installer .pkgs into ~/ without admin (macOS GUI)"
  homepage "https://github.com/ksl-testing/repkger"
  sha256 "__SHA256_APP__"

  app "Repkger.app"

  # The CLI is embedded inside the .app — the `binary` stanza symlinks it into
  # HOMEBREW_PREFIX/bin so `repkger` works after a plain `brew install --cask`
  # (no need to also run `repkger self-install`). Rootless: it's just a symlink
  # at the app's bundled copy — no copy, no sudo.
  binary "#{appdir}/Repkger.app/Contents/Resources/repkger", target: "repkger"

  uninstall delete: ["#{appdir}/Repkger.app"]

  zap trash: ["#{appdir}/Repkger.app"]
end
