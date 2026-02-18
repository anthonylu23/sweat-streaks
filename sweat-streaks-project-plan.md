# Sweat Streaks Project Plan (macOS Menu Bar)

## Summary
Build a native SwiftUI macOS menu bar app that tracks daily activity and streaks for:
1. GitHub activity days
2. LeetCode activity days
3. Combined days where both are active

The project is local-only and optimized for personal use, with periodic sync, manual refresh, resilient unknown-state handling, manual day overrides (audited), and reminder/risk notifications.

## Product Scope

### Goals
- Always-visible menu bar indicator for current streak health.
- Accurate per-day status for GitHub, LeetCode, and Combined.
- Clear streak metrics: current streak, longest streak, 7/30-day completion.
- Reliable behavior under API failures (unknown-state handling, retry, manual correction).
- Daily reminder and streak-risk notification near end of day.

### Out of Scope
- Cloud sync / shared accounts.
- Multi-account support (GitHub/LeetCode).
- App Store packaging/release workflow.
- Deep analytics dashboards/charts.

## Technical Decisions (Locked)

- Stack: Native SwiftUI + AppKit menu bar integration (`MenuBarExtra`).
- Persistence: Local SQLite via GRDB.
- GitHub source: Contribution graph day status from GitHub GraphQL with PAT (`read:user`).
- LeetCode source: Public-profile-driven fetch path with fallback adapter.
- Day boundary: User's local macOS timezone.
- Refresh: App launch + periodic timer (every 60 min) + manual refresh.
- Sync policy contract:
  - Retry: up to 3 attempts per provider run (initial + 2 retries).
  - Backoff: exponential with jitter.
  - Rate limit cooldown: pause provider for 30 min after explicit rate-limit response.
  - Stale data warning: warning if last successful provider sync > 24h.
- Failures: Keep last known values, mark day/source as `unknown`, never auto-convert to inactive.
- Manual override: enabled with visible audit marker, note, and source attribution.
- Combined rule contract:
  - `active` only when GitHub = `active` AND LeetCode = `active`.
  - `inactive` when either source = `inactive`.
  - `unknown` when no source is `inactive` and at least one source is `unknown`.
- Combined derivation uses effective source statuses after manual overrides.
- Secret handling: GitHub PAT stored in Keychain; invalid/revoked token transitions to explicit auth-error state.
- Rust domain module remains optional and post-usable-app.

## Architecture

### App Modules
- `MenuBarUI`
  - Menu bar label/icon state.
  - Popover with streak cards, daily status timeline, sync status, settings entry.
- `SyncEngine`
  - Coordinates providers, retries, cooldown, stale-state checks, and state merge.
- `Providers`
  - `GitHubProvider`
  - `LeetCodeProvider`
- `StreakEngine`
  - Computes current/longest streaks and completion rates from normalized day records.
- `Persistence`
  - SQLite models + repository.
- `NotificationEngine`
  - Schedules and triggers reminder/risk alerts.
- `Settings`
  - PAT, usernames, refresh interval, notification hour.
- `RustCore` (optional)
  - Pure functions for combined-day derivation + streak metrics.

### Data Flow
1. Timer/manual/app-launch triggers `SyncEngine`.
2. Providers fetch normalized daily activity windows.
3. `SyncEngine` writes source day records and provider run state.
4. Manual overrides are applied to source status resolution.
5. `StreakEngine` recomputes source + combined metrics.
6. UI updates menu bar + popover.
7. `NotificationEngine` evaluates today status and schedules/dispatches alerts.

## Public Interfaces / Types

### Core Types
```swift
enum ActivitySource: String { case github, leetcode, combined }
enum DayStatus: String { case active, inactive, unknown }
enum OverrideStatus: String { case active, inactive }
enum Provenance: String { case api, fallback, derived, manual }

struct LocalDay: Hashable, Codable {
  let year: Int
  let month: Int
  let day: Int
  var isoDate: String // YYYY-MM-DD
}

struct ManualOverride {
  let day: LocalDay
  let source: ActivitySource // github|leetcode only
  let status: OverrideStatus
  let note: String?
  let createdAt: Date
  let updatedAt: Date
}

struct ActivityDayRecord {
  let day: LocalDay
  let source: ActivitySource
  let status: DayStatus
  let updatedAt: Date
  let provenance: Provenance
}

struct ProviderFetchResult {
  let source: ActivitySource
  let days: [LocalDay: DayStatus]
  let fetchedRange: ClosedRange<Date>
  let rateLimitedUntil: Date?
  let authError: Bool
  let warning: String?
}

struct StreakMetrics {
  let source: ActivitySource
  let current: Int
  let longest: Int
  let lastActiveDay: LocalDay?
  let completion7d: Double
  let completion30d: Double
}
```

### Provider Protocol
```swift
protocol ActivityProvider {
  var source: ActivitySource { get }
  func fetchActivityDays(range: ClosedRange<Date>) async throws -> ProviderFetchResult
}
```

### Sync API
```swift
protocol SyncService {
  func refreshNow(trigger: SyncTrigger) async
}
```

### Manual Override API
```swift
func setManualStatus(day: LocalDay, source: ActivitySource, status: OverrideStatus, note: String?)
func clearManualStatus(day: LocalDay, source: ActivitySource)
```

### DB Schema
- `activity_days(date_local TEXT, source TEXT, status TEXT, provenance TEXT, updated_at DATETIME, PRIMARY KEY(date_local, source), CHECK (date_local GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'), CHECK (status IN ('active','inactive','unknown')), CHECK (source IN ('github','leetcode','combined')), CHECK (provenance IN ('api','fallback','derived','manual')))`
- `manual_overrides(date_local TEXT, source TEXT, status TEXT, note TEXT, created_at DATETIME, updated_at DATETIME, PRIMARY KEY(date_local, source), CHECK (date_local GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'), CHECK (source IN ('github','leetcode')), CHECK (status IN ('active','inactive')))`
- `sync_runs(id INTEGER PRIMARY KEY, provider TEXT, started_at DATETIME, finished_at DATETIME, status TEXT, error_summary TEXT, CHECK (status IN ('success','partial','failed','rate_limited','auth_error')))`
- `settings(key TEXT PRIMARY KEY, value TEXT)`
- Indexes:
  - `idx_activity_days_source_date (source, date_local)`
  - `idx_sync_runs_provider_started_at (provider, started_at DESC)`

## Data Rules
- `date_local` storage format is strictly `YYYY-MM-DD`.
- Combined status is derived from effective source statuses after overrides.
- `unknown` never transitions automatically to `inactive`.
- Sync defaults:
  - Initial backfill window: last 90 days.
  - Incremental refresh window: last 14 days.
  - Stale warning threshold: 24h since provider success.
  - Rate-limit cooldown: 30 minutes.

## Phases

### Phase 0: Baseline + Documentation Scaffolding
- Audit current repo state and docs.
- Establish docs structure:
  - `README.md` (setup + usage)
  - `docs/architecture.md`
  - `docs/task-status.md`
  - `docs/next-steps.md`
- Validation:
  - Confirm current project build state and record blockers if present.
- Exit criteria:
  - Documentation skeleton exists and reflects baseline status.

### Phase 1: Foundation (App + Persistence + Static UI)
- Scaffold SwiftUI menu bar app.
- Add persistence layer, domain models, and settings store.
- Build static popover UI with mock data.
- Validation:
  - `swift build`
  - `swift run` launch sanity check
  - Unit tests for date serialization (`LocalDay`/`YYYY-MM-DD`).
- Exit criteria:
  - App launches and renders static streak/status sections.

### Phase 2: GitHub Provider + Sync Engine
- Implement GitHub GraphQL provider with PAT from Keychain.
- Implement sync orchestration (retry/backoff/cooldown/stale tracking).
- Add auth-error state + re-auth UX path.
- Persist provider outcomes and sync run records.
- Validation:
  - Provider parser tests.
  - Sync integration tests for success/failure/rate-limit/auth-error.
  - `swift build` + test suite.
- Exit criteria:
  - Manual refresh successfully syncs GitHub day map and surfaces failures correctly.

### Phase 3: LeetCode Provider + Multi-Provider Merge
- Implement LeetCode primary adapter and fallback adapter.
- Normalize and merge provider day maps.
- Persist per-provider run states.
- Validation:
  - Adapter fixture tests.
  - Partial-failure integration tests.
  - `swift build` + test suite.
- Exit criteria:
  - Both providers run independently; partial sync state is correctly represented.

### Phase 4: Streak Engine + Combined + Manual Overrides
- Implement deterministic streak calculations.
- Implement combined truth table using effective source statuses.
- Add manual override UI/API with audit note support.
- Validation:
  - Unit tests for truth table, override precedence, streak edge cases.
  - Integration tests for override persistence across refresh/relaunch.
  - `swift build` + test suite.
- Exit criteria:
  - Overrides correctly affect combined status and streak metrics.

### Phase 5: Notifications + UX Hardening
- Add daily reminder and once-per-day risk alert with snooze-until-tomorrow.
- Finalize stale/error banners and sync diagnostics UI.
- Validation:
  - Behavioral tests for risk dedupe and snooze behavior.
  - Launch + refresh smoke checks.
  - `swift build`, `swift run`, tests.
- Exit criteria:
  - Notification behavior and stale/error UX are reliable and non-duplicative.

### Phase 6 (Optional): Rust Domain Core
- Add narrow Rust FFI for combined derivation + streak metrics only.
- Keep Swift fallback path if Rust loading/interop fails.
- Validation:
  - Parity fixtures (Swift vs Rust outputs match).
  - Fallback-path tests.
- Exit criteria:
  - Rust module can be enabled safely without impacting app reliability.

## Testing Plan

### Unit Tests
- Streak calculations for consecutive active days, gaps, unknown days, and override precedence.
- Combined-day derivation and full truth table coverage.
- Timezone/day-boundary conversion logic.
- Provider response parsing (GitHub + LeetCode adapters).
- `LocalDay` serialization/parsing roundtrip.

### Integration Tests
- Sync run writes expected DB rows and metrics.
- Provider error handling keeps prior data and uses `unknown` correctly.
- Manual override persistence and survival through refresh/relaunch.
- Rate-limit cooldown behavior.

### UI/Behavioral Tests
- Menu bar reflects updates after refresh.
- Error/stale banners appear under expected conditions.
- Notification trigger timing, dedupe, and snooze behavior.

### Acceptance Scenarios
1. New user configures usernames + PAT; first sync populates recent history.
2. One source inactive -> combined inactive.
3. One source unknown + other active -> combined unknown.
4. API failure day -> unknown status shown with no false streak break.
5. Manual override updates streaks and remains in effect until cleared.
6. Rate-limited provider enters cooldown and stale warning appears after threshold.
7. Risk alert fires once per day; snooze suppresses until next day.

## Risks and Mitigations
- LeetCode endpoint instability: isolate adapters, maintain fixture tests, keep fallback chain.
- API rate limits/failures: retry/backoff, cooldown, unknown-state semantics.
- Timezone edge cases (travel/DST): canonical `YYYY-MM-DD` local-day storage with deterministic conversion logic.
- Rust FFI complexity (optional phase): narrow ABI + parity tests + Swift fallback.

## Assumptions and Defaults
- Single macOS user, single GitHub account, single LeetCode account.
- Local-only data storage.
- PAT authentication for GitHub.
- Local timezone as canonical day boundary.
- Refresh every 60 minutes while app runs.
- Notifications enabled after user grants permission.
- Trends are lightweight (7/30-day completion), not chart-heavy analytics.
