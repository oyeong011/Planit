# Product Hunt launch draft

**Tagline (60 chars):** Menu bar calendar assistant using your local CLI

**Description (260 chars):** Calen is a macOS 14+ menu bar app for Google Calendar, Apple Calendar, and Reminders. It suggests free slots, moves unfinished tasks, detects goal activity, and uses your local Claude Code or Codex CLI.

## Body

Calen helps with planning jobs that usually stay stuck in your head.

Use it from the macOS menu bar to view Google Calendar, Apple Calendar, and Reminders together. Drag an event to reschedule it. Ask your local Claude Code or Codex CLI to suggest a week plan.

Calen is a lightweight Mac app, not a full calendar suite. The assistant uses your local CLI tools, so the scheduling flow does not require a separate hosted account. Sparkle handles updates.

Install:

```bash
brew install --cask oyeong011/calen/calen-ai
```

Latest version: v0.2.3  
Platform: macOS 14+  
License: MIT  
Repo: https://github.com/oyeong011/Planit

Limitations: early stage, limited recurring edits, some UI polish needed, and official Homebrew/homebrew-cask registration still pending because the project needs to meet Homebrew's notable criteria.

Compared with Fantastical or BusyCal, Calen is intentionally narrower: menu bar planning plus local Claude/Codex scheduling help. It is for developers who already trust their terminal tools.

## Maker comment

I built Calen for my own planning loop: calendar, reminders, and long-term goals were separate, and I wanted "do this sometime this week" to become an actual slot.

The main technical choice was calling the user's local Claude Code or Codex CLI instead of adding a hosted backend. Setup is more developer-oriented, but the app stays small.

I would especially like feedback on the weekly planning flow, the menu bar UI, and what should stay manual instead of automated.
