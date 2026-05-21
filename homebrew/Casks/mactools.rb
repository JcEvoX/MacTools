cask "mactools" do
  version "1.0.5"
  sha256 "04b1dfac990943b57dfdf684d73486600947b8ddc644eddb990dce0bef49e3f9"

  url "https://github.com/ggbond268/MacTools/releases/download/v1.0.5/MacTools.dmg"
  name "MacTools"
  desc "Menu bar toolbox"
  homepage "https://github.com/ggbond268/MacTools"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "MacTools.app"
end
