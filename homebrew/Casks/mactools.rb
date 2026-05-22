cask "mactools" do
  version "1.0.6"
  sha256 "446ea80cf427e2e7c2090e1d99c82f9303903cecf1984ee41827f63292822754"

  url "https://github.com/ggbond268/MacTools/releases/download/v1.0.6/MacTools.dmg"
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
