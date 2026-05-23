cask "mactools" do
  version "1.0.10"
  sha256 "c26c532e6940a23a6e0f7b4f431dd3827bd80773a391a4c309a966de5fd3b85a"

  url "https://github.com/ggbond268/MacTools/releases/download/v1.0.10/MacTools.dmg"
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
