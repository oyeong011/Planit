# OAuth Scope Justification — Calen

Submitted for Google OAuth app verification.

## App Information

- **App name**: Calen
- **App type**: Desktop client (macOS native)
- **Homepage**: https://github.com/oyeong011/Planit
- **Privacy Policy**: https://oyeong011.github.io/Planit/privacy.html
- **Terms of Service**: https://oyeong011.github.io/Planit/terms.html
- **Support contact**: beetleboy_@naver.com
- **OAuth client type**: Desktop
- **Distribution**: Open source (MIT). Signed + notarized by Apple Developer ID

## Scopes Requested

### 1. `https://www.googleapis.com/auth/calendar.events`
**Purpose**: Read and create/update/delete calendar events.
**Justification**:
- The core user-facing feature is a macOS menu bar calendar that displays Google Calendar events alongside Apple Calendar, allowing the user to see a unified view of their day.
- Users can drag events to reschedule, tap events to edit titles/times, and delete events from the menu bar popover. All these actions require read+write on calendar events.
- AI chat feature allows the user to say "move my 3pm meeting to 5pm" — this requires update access. Each AI action requires explicit user confirmation before execution.

### 2. `https://www.googleapis.com/auth/calendar.calendarlist.readonly`
**Purpose**: List the user's calendars.
**Justification**:
- Users often have multiple calendars (personal, work, shared). Calen lets the user toggle which calendars to display and also flag sensitive calendars (e.g., health, personal) to exclude from AI context. We need the calendar list to render these per-calendar toggles.
- No write access to calendar list itself — read-only scope.

### 3. `https://www.googleapis.com/auth/userinfo.email`
**Purpose**: Identify the signed-in user.
**Justification**:
- Display the signed-in account email in the app's settings screen, so users with multiple Google accounts can verify which account is active.
- Used as a key in the Keychain for token storage per-user.

## Why these are the minimum

We intentionally do **not** request:
- `contacts` / `contacts.readonly` — not needed.
- `drive` — not needed; attachments are uploaded to the user's local filesystem only.
- `gmail` — not needed.
- `profile` or full OpenID — only email is needed, not profile photo / name.

## Data Handling

- **Storage**: Calendar data is fetched on demand and kept only in memory or in a local encrypted JSON cache (`~/Library/Application Support/Planit/events_cache.json`, file mode 0o600).
- **Transmission**: Calendar data never leaves the user's device except:
  1. TLS to `googleapis.com` (trusted destination) — for sync only.
  2. Stdin pipe to the user's locally installed Claude Code or Codex CLI when the user types an AI message. We do not operate any server-side receiver.
- **Sensitive calendars**: Users can flag calendars as sensitive; such calendars are filtered out before AI context is built.
- **Retention**: Sign out = delete tokens + local cache. No residual data.
- **Tokens**: Stored in macOS Keychain with accessibility `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `kSecAttrSynchronizable = false`.

## Limited Use Compliance

Calen complies with Google's [Limited Use requirements](https://developers.google.com/terms/api-services-user-data-policy#additional_requirements_for_specific_api_scopes):

1. **Allowed use**: The app uses user data to provide user-facing features (calendar viewing, scheduling assistance).
2. **Allowed transfer**: Data is only transferred to the user's own device and their own locally-installed AI CLI; never to our servers (we do not operate servers that receive user data).
3. **No advertising**: Calen does not use Google user data for advertising.
4. **No humans read data**: No human at our end reads or analyzes user calendar data. All processing is automated and local.

## Demo Video

A recording demonstrating the in-app OAuth flow, scope usage, and data handling is available at: **[To be recorded before submission]**

Minimum required demo segments:
1. Installing Calen fresh
2. Clicking "Sign in with Google"
3. Showing the OAuth consent screen with scopes
4. Showing the calendar view after signing in
5. Showing a create/update/delete action
6. Showing "Sign out" → tokens cleared from Keychain
