cask "mactools" do
  version "1.0.12"
  sha256 "0386e69d565770b0b7fbdb3324933991c252fc11a25f4871dbcdd30e1c62c79a"

  url "https://github.com/ggbond268/MacTools/releases/download/v1.0.12/MacTools.dmg"
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
