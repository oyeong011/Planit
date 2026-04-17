# Calen OAuth Verification Demo Script

**Target length**: 2~3 minutes  
**Target audience**: Google OAuth verification reviewer  
**Upload destination**: YouTube (Unlisted)

## Preparation

- [ ] macOS with no existing Calen install (uninstall first: `brew uninstall --cask calen-ai`)
- [ ] Google account ready for demo (test Calendar with a few events)
- [ ] Terminal open, pwd at home
- [ ] Menu bar visible (달력 앱 실행 중이면 닫기)
- [ ] Screen recording: QuickTime Player → File → New Screen Recording → **전체 화면 + 오디오 내레이션**

## Shot List

| Time | What | Narration |
|---|---|---|
| 00:00 | **Repo home** (github.com/oyeong011/Planit 브라우저) | "Calen is an open-source macOS menu bar calendar app." |
| 00:10 | **Install** (`brew install --cask oyeong011/calen/calen-ai` in Terminal) | "Install via Homebrew tap." |
| 00:25 | **Launch** (메뉴바 달력 아이콘 클릭) | "Click the menu bar icon to open the popover." |
| 00:35 | **Google Sign-in** (Login 버튼 클릭, 브라우저 OAuth 동의 화면 표시) — ⚠️ **CRITICAL**: Google consent screen showing 3 scopes clearly visible | "On sign-in, the user explicitly consents to three scopes: read calendar list, read/edit events, and read email." |
| 00:55 | **Calendar view** (로그인 후 이벤트 표시) | "Events are displayed from Google Calendar." |
| 01:10 | **Create event** ("할 일 추가" 또는 채팅 "내일 3시 회의 추가") | "Users can create new events. The app uses the calendar.events scope for this write operation." |
| 01:30 | **Update event** (기존 이벤트 클릭 → 제목/시간 수정 → 저장) | "Existing events can be updated. Each destructive action requires explicit user confirmation." |
| 01:50 | **Delete event** (이벤트 우클릭 → 삭제 → 확인 모달) | "Delete requires explicit confirmation before proceeding." |
| 02:10 | **Sign out** (설정 → Google 로그아웃) | "On sign-out, OAuth tokens are removed from the macOS Keychain." |
| 02:25 | **Optional: Sensitive calendar toggle** (설정에서 민감 캘린더 선택) | "Users can mark calendars as sensitive to exclude them from AI context." |
| 02:40 | **Outro** (GitHub repo URL 다시 표시) | "Source at github.com/oyeong011/Planit. MIT licensed." |

## Key Visual Requirements (Reviewer will check)

1. ✅ **Google OAuth consent screen** must be visible and clearly show:
   - App name: "Calen"
   - All 3 requested scopes
   - Publisher info
2. ✅ **App logo** visible in menu bar
3. ✅ **Each scope must be demonstrated in actual UI action**:
   - `calendar.calendarlist.readonly` → calendar list in settings
   - `calendar.events` → create + update + delete operations
   - `userinfo.email` → email shown in settings
4. ✅ **Sign-out** demonstrates token cleanup

## Upload Checklist

1. Open https://studio.youtube.com
2. Click "업로드" → select your video file
3. Title: `Calen — OAuth Scope Usage Demo for Google Verification`
4. Description:
   ```
   OAuth scope usage demonstration for Google OAuth verification review.
   App: Calen (https://github.com/oyeong011/Planit)
   Scopes demonstrated:
     - https://www.googleapis.com/auth/calendar.events
     - https://www.googleapis.com/auth/calendar.calendarlist.readonly
     - https://www.googleapis.com/auth/userinfo.email
   Not for public distribution.
   ```
5. Visibility: **"일부 공개" (Unlisted)**
6. After upload, copy the URL (format: `https://youtu.be/XXXXXXXXXXX`)

## Paste Back to Google Console

1. Return to https://console.cloud.google.com/auth/verification/submit
2. Click "문제 해결" on the red warning box
3. In the "데모 동영상 URL" field, paste the YouTube URL
4. Save
5. The red warning should disappear
6. Click "확인" (Submit) at the bottom

## Common Rejection Reasons (avoid)

- ❌ Video too short (< 90s) — Google often rejects as "insufficient detail"
- ❌ Scope usage not clearly tied to visible UI action
- ❌ Consent screen skipped (must appear on camera)
- ❌ Audio missing (some reviewers require narration, not just captions)
- ❌ Video resolution under 720p
