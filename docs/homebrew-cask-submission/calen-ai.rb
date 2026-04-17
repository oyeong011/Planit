cask "calen-ai" do
  version "0.2.3"
  sha256 "786bcd803a96ce08028d3012306526033b56dbea2e422be529e422bb13c85c33"

  url "https://github.com/oyeong011/Planit/releases/download/v#{version}/Calen-#{version}-universal.zip",
      verified: "github.com/oyeong011/Planit/"
  name "Calen"
  desc "AI-powered menu bar calendar with Google Calendar integration"
  homepage "https://github.com/oyeong011/Planit"

  # Sparkle 자동 업데이트
  livecheck do
    url "https://github.com/oyeong011/Planit/releases.atom"
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Calen.app"

  zap trash: [
    "~/Library/Application Support/Calen",
    "~/Library/Caches/com.oy.planit",
    "~/Library/Preferences/com.oy.planit.plist",
    "~/Library/Saved Application State/com.oy.planit.savedState",
  ]
end
