# Show HN: Calen - a local-first menu bar calendar assistant for macOS

## Korean

**Title:** Show HN: Calen - macOS 메뉴바에서 일정과 할 일을 정리하는 로컬 CLI 비서

일정 앱을 계속 열어두기는 번거롭고, 캘린더/리마인더/장기 목표는 자주 흩어집니다. 저는 매주 월요일 오전 30분 빈 슬롯을 찾아 목표 작업을 넣거나, 밀린 일을 내일 빈 시간으로 옮기는 흐름이 필요했습니다.

Calen은 macOS 14+ 메뉴바 앱입니다. Google Calendar, Apple Calendar, Reminders를 한곳에서 보고, 드래그로 일정을 재배치하며, Claude Code 또는 Codex CLI로 스케줄 제안을 받습니다.

기술적으로는 SwiftUI + EventKit + Google Calendar REST API입니다. Claude/Codex는 원격 SDK 대신 로컬 CLI를 실행합니다. 일정 컨텍스트는 민감 캘린더 제외 규칙을 거친 뒤 전달됩니다. Sparkle 자동 업데이트도 포함했습니다.

영상/데모는 일부러 넣지 않았습니다. v0.2.3 early stage라 데모보다 실제 피드백이 더 필요합니다. Homebrew-cask 정식 등록 전이라 notable 요건을 채우는 중이고, 지금은 탭으로 설치합니다:

```bash
brew install --cask oyeong011/calen/calen-ai
```

MIT입니다. 버그, 거친 UI, 이상한 제안이 아직 있을 수 있습니다. "이건 일정 앱에 진짜 필요한가?" 관점의 피드백을 받고 싶습니다.

Repo: https://github.com/oyeong011/Planit

## English

**Title:** Show HN: Calen - a local CLI calendar assistant in your macOS menu bar

I kept losing planning decisions between calendar apps, reminders, and long-term goals. I wanted something that could find a 30-minute Monday slot for a goal, or move unfinished tasks into tomorrow without opening a full calendar app.

Calen is a macOS 14+ menu bar app. It brings together Google Calendar, Apple Calendar, and Reminders, lets you drag events around, and asks your local Claude Code or Codex CLI for schedule suggestions.

The app uses SwiftUI, EventKit, and the Google Calendar REST API. The assistant path uses the user's local CLI instead of a hosted backend. Calendar context is filtered before it reaches the local process, and Sparkle handles updates.

There is no polished demo on purpose. v0.2.3 is early, and I would rather get practical feedback. Calen is not yet in official Homebrew/homebrew-cask because it still needs to meet Homebrew's notable criteria, so install via tap for now:

```bash
brew install --cask oyeong011/calen/calen-ai
```

MIT licensed. Compared with Fantastical or BusyCal, Calen is narrower: menu bar workflow plus local Claude/Codex scheduling help, not a full calendar suite.

Repo: https://github.com/oyeong011/Planit
