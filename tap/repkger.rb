# repkger — rootless .pkg installer for macOS (no admin, no sudo).
#
# TEMPLATE — the published copy in ksl-testing/homebrew-tap is generated from
# this file by scripts/update-tap.sh (triggered by .github/workflows/release.yml).
# The url / sha256 / version tokens are substituted at publish time.
#
#   brew install ksl-testing/tap/repkger
#   brew install ksl-testing/tap/repkgr   # alias, same formula
#
# Docs: https://github.com/ksl-testing/repkger

class Repkger < Formula
  desc "Unpacks installer .pkgs into ~/ without admin (macOS)"
  homepage "https://github.com/ksl-testing/repkger"
  url "__URL__"
  version "__VERSION__"
  sha256 "__SHA256__"

  def install
    bin.install "repkger"
  end

  test do
    assert_match "repkger", shell_output("#{bin}/repkger version")
  end
end
