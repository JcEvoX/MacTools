cask "mactools" do
  version "1.0.11"
  sha256 "6c0cbfdcd81701a13db4bb00a99d09efd5a1497e5318311123f5aa0cc0ed064a"

  url "https://github.com/ggbond268/MacTools/releases/download/v1.0.11/MacTools.dmg"
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
