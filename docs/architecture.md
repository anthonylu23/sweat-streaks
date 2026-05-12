# Architecture

## Modules
- `SweatStreaksApp`
  - SwiftUI menu bar scene (`MenuBarExtra` with window-style presentation), AppKit-backed settings window, popover content, settings view, app model, GitHub provider, LeetCode provider, notification engine, and sync engine.
- `SweatStreaksCore`
  - Public domain types, provider/sync contracts, combined status resolver, and streak computation.
- `SweatStreaksPersistence`
  - GRDB-backed SQLite database manager, schema creation, repository APIs, and Keychain secret storage abstraction.

## Data Model
- `activity_days`
  - Daily source status rows (`github|leetcode|combined`) with provenance and timestamps.
- `manual_overrides`
  - User overrides for source days (`active|inactive`) with note and audit timestamps.
- `sync_runs`
  - Provider sync execution log and status (`success|partial|failed|rate_limited|auth_error`).
- `settings`
  - Key/value storage for local app settings.
- `provider_states`
  - Current per-provider last-success, cooldown, last-error, and stale flags for UI and restart persistence.

## Data Rules
- Local day format is strict ISO `YYYY-MM-DD`.
- Combined status derives from effective source statuses after manual overrides.
- Unknown statuses do not auto-convert to inactive.
- Current streak display uses an app-level end-of-day grace anchor: provider inactive/unknown today calculates current streak through yesterday, while manual inactive overrides anchor to today and reset immediately.
- GitHub PAT is stored in Keychain, not in SQLite settings, and is not loaded back into the settings UI.
- LeetCode uses the public profile calendar and fills fetched-but-missing days as inactive.
- Provider days outside the requested local-day fetch window are ignored before persistence, and stale future rows are deleted on refresh, to avoid UTC spillover rows.
- SQLite database files are restricted to owner-only permissions (`0600`).
- Provider requests are HTTPS-only.
- Provider error summaries are sanitized before they are persisted or displayed.

## Current Runtime Flow (MVP)
1. App starts and initializes local SQLite database.
2. App model loads local settings, provider states, and GitHub PAT status from Keychain.
3. On launch/manual/timer trigger, sync engine resolves fetch range per configured provider:
   - Initial: 90 days if no prior provider data.
   - Incremental: 14 days when prior data exists.
4. GitHub provider calls GraphQL contribution calendar and maps days:
   - `contributionCount > 0` -> `active`
   - `0` -> `inactive`
5. LeetCode provider calls the public profile calendar query and maps submission-calendar days:
   - timestamp count `> 0` -> `active`
   - fetched days missing from the submission calendar -> `inactive`
6. Sync engine applies retry/backoff, auth/rate-limit classification, local-day window clamping, cooldown/stale state updates, and records `sync_runs` + `provider_states`.
7. Repository stores provider `activity_days`; combined status is derived from effective source statuses after manual overrides and persisted as `combined`.
8. App model recomputes UI status/metrics from persisted source days plus manual overrides.
9. App model chooses a current-streak anchor per source before computing metrics:
   - active today or manual active today -> today
   - provider inactive/unknown today -> yesterday
   - manual inactive today -> today
   - Combined manual inactive reset if either source has a manual inactive override today
10. App model publishes one-year square timelines for GitHub contributions, LeetCode activity, and Combined activity.
11. Notification engine sends at most one local risk notification per day when combined is not active after the configured reminder hour.

## UI Windowing Notes
- The menu bar extra uses `.menuBarExtraStyle(.window)` because its content contains controls and opens editable settings.
- The popover displays calendar-style heatmaps for GitHub contributions, LeetCode activity, and Combined activity. Square data uses the same effective day statuses as streak metrics, including manual override effects.
- The collapsed menu bar label is derived from the same published streak metrics and today statuses as the popover. It renders configurable icon-and-number pairs using shared source icons for GitHub, LeetCode, and Combined, while `MenuBarStreakDisplay` owns item selection and accessibility labels.
- The GitHub status row exposes the latest contribution-calendar day/status as hover help so users can distinguish raw commits from GitHub-counted contributions.
- Settings are hosted in a reusable `NSWindow` with an `NSHostingController`, which avoids relying on SwiftUI's settings responder-chain action from a menu-bar-only surface.
- The app uses an `NSApplicationDelegate` to set regular activation policy at launch so AppKit can give the settings window normal keyboard focus.
- The menu bar Settings button defers opening to the next main-actor turn, activates the app, explicitly makes the settings window key/front, and focuses the GitHub username field on appear.

## Remaining Architecture Work
1. Replace the current simple manual override menu with a richer editor for date selection, notes, and audit history.
2. Add a LeetCode fallback adapter if the public GraphQL calendar becomes unreliable.
3. Add UI smoke tests around menu bar state, settings, and override flows.
4. Consider extracting provider diagnostics into a dedicated view once sync history grows.
