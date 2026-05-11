cask "mactools" do
  version "0.11.0"
  sha256 "8bbd9bfb67c8b8cb0e8074174803ddb768d031d85acdb6a95079fe2ae4fb339f"

  url "https://github.com/ggbond268/MacTools/releases/download/v#{version}/MacTools.dmg"
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
