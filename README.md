<p align="center">
  <img src="docs/assets/calen-hero.png" alt="Calen menu bar screenshot" width="720" onerror="this.style.display='none'">
</p>

<p align="center">
  <a href="https://github.com/oyeong011/Planit/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/oyeong011/Planit?label=release"></a>
  <a href="https://github.com/oyeong011/Planit/blob/main/LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black">
</p>

# Calen

Menu bar calendar planner for macOS with Google Calendar, Apple Calendar, Reminders, and local Claude/Codex CLI scheduling suggestions.

```bash
brew install --cask oyeong011/calen/calen-ai
```

## What it does

| Plan | Sync | Assistant | Updates |
|---|---|---|---|
| Find free slots, move unfinished tasks, drag events | Google Calendar, Apple Calendar, Reminders | Uses your locally installed Claude Code or Codex CLI | Sparkle auto-update |

Example workflows:
- Find a 30-minute Monday slot for a long-term goal.
- Move unfinished todos into tomorrow's open blocks.
- Ask "plan me 3 study blocks around Thursday's meetings".

## Install

### Homebrew (recommended)

```bash
brew install --cask oyeong011/calen/calen-ai
```

> Homebrew official registration (`Homebrew/homebrew-cask`) is pending — Calen needs to meet Homebrew's notable criteria first. Install through the project tap until then.

### Direct download

1. Download `Calen-0.2.3-universal.dmg` from [Releases](https://github.com/oyeong011/Planit/releases/latest)
2. Drag `Calen.app` to `/Applications`
3. Launch from Launchpad

### Enable AI features (optional)

Install Claude Code or Codex CLI:
```bash
brew install claude-code       # or:
npm install -g @openai/codex
```

## "앱이 확인되지 않음" 경고 시 (Google OAuth)

Calen is currently undergoing Google OAuth verification (1–6 weeks). Until verified, you'll see a warning during sign-in. Workaround:

1. Click **"Advanced"** on the warning screen
2. Click **"Go to Calen (unsafe)"**
3. Proceed with normal consent

The app is properly code-signed and notarized by Apple. The warning only means Google's review hasn't completed yet.

## Requirements

- macOS 14 Sonoma or later
- Universal binary (Apple Silicon + Intel)

## Comparison

| | Fantastical / BusyCal | Calen |
|---|---|---|
| Positioning | Full calendar suite | Menu bar planner + local CLI assistant |
| Pricing | Subscription | Free, MIT |
| AI scheduling | None | Uses your local Claude/Codex CLI |
| Apple Calendar | Yes | Yes |
| Google Calendar | Yes | Yes |
| Dock icon | Yes | Menu bar only |

Calen is intentionally narrower — it's for developers who already trust their terminal tools and want a lightweight planning surface.

## Known limitations

- Early stage (v0.2.3). Recurring event edits are limited.
- Some UI states need polish.
- Google OAuth verification pending (see above).
- No iOS/iPadOS/watchOS yet (planned).

## Privacy

See [Privacy Policy](https://oyeong011.github.io/Planit/privacy.html) and [Terms of Service](https://oyeong011.github.io/Planit/terms.html).

- Calendar data never leaves your device except via Google Calendar API sync.
- AI chat uses your locally installed Claude/Codex CLI — no hosted backend.
- OAuth tokens stored in macOS Keychain (`WhenUnlockedThisDeviceOnly`, no iCloud sync).
- Open source and MIT-licensed.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for branch strategy, build commands, and release process.

## License

MIT © 2026 Oyeong Gwon
