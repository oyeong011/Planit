# X/Twitter thread

1. Calen v0.2.3을 공개합니다. macOS 메뉴바에서 Google Calendar, Apple Calendar, Reminders를 한곳에 보고, Claude Code/Codex CLI로 일정 제안을 받는 작은 앱입니다. 설치: `brew install --cask oyeong011/calen/calen-ai`

2. I built it for planning chores: find a 30-min slot every Monday morning, move unfinished tasks to tomorrow, or place 3 workout blocks around existing meetings. It is macOS 14+, MIT, and still early.

3. 핵심 선택은 로컬 CLI입니다. 별도 서버형 일정 비서 계정을 만들지 않고, 사용자가 이미 설치한 Claude Code 또는 Codex CLI를 호출합니다. 민감한 캘린더는 제외 규칙을 거친 뒤 컨텍스트로 전달합니다.

4. It is not a Fantastical or BusyCal replacement. Calen is narrower: menu bar first, local CLI scheduling help second. Known limits: rough UI edges, limited recurring edits, and official Homebrew-cask registration is still pending.

5. 써보고 피드백을 받고 싶습니다. 특히 "어떤 일정 정리는 자동화하면 안 되는가"가 궁금합니다. Repo: https://github.com/oyeong011/Planit Latest: v0.2.3 License: MIT
