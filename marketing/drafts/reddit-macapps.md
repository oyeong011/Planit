# [Release] Calen - a lightweight menu bar calendar assistant for macOS

[Screenshot: menu bar popover with month grid, event list, and assistant panel]

I built Calen because I wanted a small menu bar calendar for chores I kept postponing: finding a free 30-minute Monday slot, moving unfinished tasks to tomorrow, and keeping Google Calendar, Apple Calendar, and Reminders visible together.

Calen is for macOS 14+. It supports Google Calendar, Apple Calendar, Reminders, drag-to-reschedule, long-term goal activity detection, Claude Code / Codex CLI integration, and Sparkle updates.

The main design choice: Calen uses your local Claude or Codex CLI instead of a hosted scheduling service. That keeps the assistant flow tied to tools you already installed.

Install:

```bash
brew install --cask oyeong011/calen/calen-ai
```

Repo: https://github.com/oyeong011/Planit  
Latest: v0.2.3  
License: MIT

Known limits: beta software, rough UI edges, limited recurring event handling, and no official Homebrew/homebrew-cask registration yet because Calen still needs to meet Homebrew's notable criteria.

Compared with Fantastical or BusyCal, Calen is smaller and more opinionated: menu bar first, local CLI assistant second. It is not a full calendar-suite replacement.
