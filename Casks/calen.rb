cask "calen" do
  version "0.4.55"
  sha256 "ad5f50bb41c0a1e2fc9d89595a9ca571c3657ac7e5421e85b21ca97a5f30f8ec"

  url "https://github.com/oyeong011/Planit/releases/download/v#{version}/Calen-#{version}-universal.zip"
  name "Calen"
  desc "AI-powered macOS menu bar calendar with Google Calendar integration"
  homepage "https://github.com/oyeong011/Planit"

  depends_on macos: ">= :sonoma"

  app "Calen.app"

  zap trash: [
    "~/Library/Application Support/Calen",
    "~/Library/Caches/com.oy.planit",
    "~/Library/Preferences/com.oy.planit.plist",
    "~/Library/Saved Application State/com.oy.planit.savedState",
  ]
end
