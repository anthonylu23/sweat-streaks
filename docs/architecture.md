# Architecture

## Modules
- `SweatStreaksApp`
  - SwiftUI menu bar scene (`MenuBarExtra` with window-style presentation), AppKit-backed settings window, popover content, settings view, app model, provider registry, notification engine, and sync engine.
- `SweatStreaksCore`
  - Public domain types, provider/sync contracts, current provider source lists, combined status resolver, and streak computation.
- `SweatStreaksPersistence`
  - GRDB-backed SQLite database manager, schema creation, repository APIs, and Keychain secret storage abstraction.
- `SweatStreaksProviderSupport`
  - Shared provider HTTP client protocol/default implementation, HTTPS endpoint guard, and rate-limit header parsing.
- `SweatStreaksProviderGitHub`
  - GitHub GraphQL contribution-calendar provider implementation and response DTOs.
- `SweatStreaksProviderLeetCode`
  - LeetCode public GraphQL calendar provider implementation and response DTOs.
- `SweatStreaksProviderLocalSupport`
  - Shared local JSONL file discovery, timestamp parsing, and local-day status map helpers.
- `SweatStreaksProviderCodex`
  - Codex local activity provider reading timestamped session JSONL files.
- `SweatStreaksProviderClaudeCode`
  - Claude Code local activity provider reading timestamped history/project JSONL files.

## Provider Boundary
```text
SweatStreaksApp
  |
  +-- ProviderRegistry
  |     |
  |     +-- GitHubProvider  -> SweatStreaksProviderGitHub
  |     +-- LeetCodeProvider -> SweatStreaksProviderLeetCode
  |     +-- CodexProvider -> SweatStreaksProviderCodex
  |     +-- ClaudeCodeProvider -> SweatStreaksProviderClaudeCode
  |
  +-- DefaultSyncService
        |
        v
SweatStreaksCore
  |
  +-- ActivityProvider
  +-- ProviderFetchResult
  +-- ProviderError
  +-- ActivitySource.currentProviderSources
```

- Provider implementations are separate SwiftPM modules; the app only constructs them through `ProviderRegistry`.
- `SweatStreaksProviderSupport` owns shared HTTP mechanics so provider modules do not depend on each other.
- `SweatStreaksProviderLocalSupport` owns local JSONL scanning mechanics so local providers do not read auth tokens or depend on remote APIs.
- Combined status accepts an explicit required-source list. App-driven sync/recompute derives that list from enabled provider tracking toggles, so disabled providers are omitted from the Combined requirement.

## Data Model
- `activity_days`
  - Daily source status rows (`github|leetcode|codex|claude_code|combined`) with provenance and timestamps.
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
- Combined status derives from effective required-source statuses after manual overrides.
- Unknown statuses do not auto-convert to inactive.
- Current streak display uses an app-level end-of-day grace anchor: provider inactive/unknown today calculates current streak through yesterday, while manual inactive overrides anchor to today and reset immediately.
- GitHub PAT is stored in Keychain, not in SQLite settings, and is not loaded back into the settings UI.
- LeetCode uses the public profile calendar and fills fetched-but-missing days as inactive.
- Codex uses local JSONL logs under `~/.codex/sessions` and `~/.codex/archived_sessions`; Claude Code uses local JSONL logs under `~/.claude/history.jsonl` and `~/.claude/projects`.
- Local agentic providers map at least one valid timestamp in the requested local day to `active`; fetched days with no timestamp are `inactive`.
- Codex and Claude Code auth token values are not read, persisted, displayed, or transmitted.
- Provider days outside the requested local-day fetch window are ignored before persistence, and stale future rows are deleted on refresh, to avoid UTC spillover rows.
- SQLite database files are restricted to owner-only permissions (`0600`).
- Provider requests are HTTPS-only.
- Provider error summaries are sanitized before they are persisted or displayed.

## Current Runtime Flow (MVP)
1. App starts and initializes local SQLite database.
2. App model loads local settings, provider states, and GitHub PAT status from Keychain.
3. Provider registry builds factories for configured providers.
4. On launch/manual/timer trigger, sync engine resolves fetch range per configured provider:
   - Initial: 90 days if no prior provider data.
   - Incremental: 14 days when prior data exists.
5. GitHub provider calls GraphQL contribution calendar and maps days:
   - `contributionCount > 0` -> `active`
   - `0` -> `inactive`
6. LeetCode provider calls the public profile calendar query and maps submission-calendar days:
   - timestamp count `> 0` -> `active`
   - fetched days missing from the submission calendar -> `inactive`
7. Codex and Claude Code providers scan local JSONL log timestamps and map days:
   - one or more timestamps in a local day -> `active`
   - fetched days with no timestamps -> `inactive`
8. Sync engine applies retry/backoff, auth/rate-limit classification, local-day window clamping, cooldown/stale state updates, and records `sync_runs` + `provider_states`.
9. Repository stores provider `activity_days`; combined status is derived from effective enabled-source statuses after manual overrides and persisted as `combined`.
10. App model recomputes UI status/metrics from persisted source days plus manual overrides.
11. App model chooses a current-streak anchor per source before computing metrics:
   - active today or manual active today -> today
   - provider inactive/unknown today -> yesterday
   - manual inactive today -> today
   - Combined manual inactive reset if either source has a manual inactive override today
12. App model publishes one-year square timelines for GitHub, LeetCode, Codex, Claude Code, and Combined activity.
13. Notification engine sends at most one local risk notification per day when combined is not active after the configured reminder hour.

## UI Windowing Notes
- The menu bar extra uses `.menuBarExtraStyle(.window)` because its content contains controls and opens editable settings.
- The popover displays compact calendar-style heatmaps for GitHub, LeetCode, Codex, Claude Code, and Combined activity. Square data uses the same effective day statuses as streak metrics, including manual override effects, and month labels are suppressed at tight boundaries when adjacent labels would collide.
- The popover enumerates `AppModel.trackedProviderSources` for provider status rows, source tabs, heatmap choices, and today overrides; disabled provider tracking hides that provider from the popover and returns a disabled selected source back to Combined.
- The collapsed menu bar label is derived from the same published streak metrics and today statuses as the popover. It renders configurable icon-and-number pairs using shared source icons for GitHub, LeetCode, Codex, Claude Code, and Combined, while `MenuBarStreakDisplay` owns item selection and accessibility labels.
- Provider-specific menu bar visibility controls are disabled when their corresponding provider tracking toggle is off. `AppModel` also coerces those visibility settings off before saving, and `MenuBarStreakDisplay` filters disabled tracking sources as a defensive guard against stale persisted settings.
- The GitHub status row exposes the latest contribution-calendar day/status as hover help so users can distinguish raw commits from GitHub-counted contributions.
- Settings are hosted in a reusable `NSWindow` with an `NSHostingController`, which avoids relying on SwiftUI's settings responder-chain action from a menu-bar-only surface.
- Settings persist independent tracking toggles for GitHub, LeetCode, Codex, and Claude Code. `ProviderRegistry` only builds sync factories for providers whose tracking toggle and required account/local configuration are present, and the app passes the same enabled-source list as the Combined required-source list, so a saved username or PAT can remain in storage while provider activity sync is disabled.
- The app uses an `NSApplicationDelegate` to set regular activation policy at launch so AppKit can give the settings window normal keyboard focus.
- The menu bar Settings button defers opening to the next main-actor turn, activates the app, explicitly makes the settings window key/front, and focuses the GitHub username field on appear.
- `AppIconManager` sets `NSApp.applicationIconImage` from bundled dark/light PNG resources at launch and when macOS appearance changes. This keeps the icon visible for SwiftPM-launched builds where there is no packaged app icon bundle.

## Remaining Architecture Work
1. Replace the current simple manual override menu with a richer editor for date selection, notes, and audit history.
2. Add a LeetCode fallback adapter if the public GraphQL calendar becomes unreliable.
3. Add UI smoke tests around menu bar state, settings, and override flows.
4. Consider extracting provider diagnostics into a dedicated view once sync history grows.
5. Add Cursor as another local agentic provider once its reliable local activity source is identified.
6. Consider preserving session counts or token/cost metrics separately from active-day status if product needs grow.
