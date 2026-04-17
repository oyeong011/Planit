# CRUD Observability

## Silent Failure Map

- Google event create/update/delete in `CalendarViewModel` used `catch` plus `print`, then returned without user feedback on non-queueable errors.
- EventKit fallback create/update/delete returned `false` on missing writable calendar, missing event, or save/remove failure without explaining the failed action to the user.
- Todo-to-Google mirror create/update/delete used `try?` in critical paths, so a calendar mirror could fail while the local todo appeared updated.
- Offline pending edit sync intentionally keeps failed edits for retry. This remains developer-log only because the user-facing state is already represented by the queued edit count/offline path.
- Cache, category, order, and local persistence reads still use best-effort failure handling. These are not surfaced as CRUD banners because they are not direct user-requested create/update/delete operations.

## User Feedback vs Developer Logs

- User-visible: direct create/update/delete failures for Google events, local EventKit events, and todo calendar mirrors.
- Developer-log only: fetch fallback to cache, offline queue retry failures, persistence/cache/order best-effort failures, and background bulk sync failures.

## Sensitive Logging Rules

- Allowed: operation, source, event ID, sanitized error type/status.
- Disallowed: event title, location, notes, OAuth tokens, request/response bodies, calendar names derived from user content.
- Error logging must use sanitized summaries instead of raw localized descriptions when the error may contain URLs or provider payloads.
