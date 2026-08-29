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

  # The CLI is embedded inside the .app — expose it on PATH for terminal users
  # (so `repkger` works without also running `repkger self-install`).
  postflight do
    cli = "#{appdir}/Repkger.app/Contents/Resources/repkger"
    if File.exist?(cli)
      (HOMEBREW_PREFIX/"bin").install Symlink.new(cli)
    end
  end

  uninstall delete: ["#{HOMEBREW_PREFIX}/bin/repkger"],
            rmdir:  ["#{appdir}/Repkger.app"]

  zap trash: ["#{appdir}/Repkger.app"]
end
