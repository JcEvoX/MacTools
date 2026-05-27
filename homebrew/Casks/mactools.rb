cask "mactools" do
  version "1.0.13"
  sha256 "3d030537e6b1cd532376dad15c3e1ec69518465198dab6cc6810efb81cdbf0d6"

  url "https://github.com/ggbond268/MacTools/releases/download/v1.0.13/MacTools.dmg"
  name "MacTools"
  desc "Menu bar toolbox"
  homepage "https://github.com/ggbond268/MacTools"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "MacTools.app"
end
