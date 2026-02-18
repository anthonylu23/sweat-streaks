# Sweat Streaks v1 Project Plan (macOS Menu Bar)

## Summary
Build a native SwiftUI macOS menu bar app that tracks daily activity and streaks for:
1. GitHub activity days
2. LeetCode activity days
3. Combined days where both are active

v1 is personal-use first, local-only, with periodic sync, manual refresh, basic trends, reminders, and manual day overrides (audited).

## Product Scope

### Goals
- Always-visible menu bar indicator for current streak health.
- Accurate per-day status for GitHub, LeetCode, and Combined.
- Clear streak metrics: current streak, longest streak, 7/30-day completion.
- Reliable behavior under API failures (unknown-state handling, retry, manual correction).
- Daily reminder and streak-risk notification near end of day.

### Out of Scope (v1)
- Cloud sync / shared accounts.
- Mac App Store packaging.
- Multi-account support (GitHub/LeetCode).
- Deep analytics dashboards/charts.
- OAuth device flow for GitHub (use PAT first).

## Technical Decisions (Locked)

- Stack: Native SwiftUI + AppKit menu bar integration (`MenuBarExtra`).
- Language boundary: Swift remains the app/runtime owner; Rust is used for deterministic streak/domain logic only (learning track, no backend migration).
- Persistence: Local SQLite via GRDB (locked; chosen for explicit schema and migration control).
- GitHub source: Contribution graph day status from GitHub GraphQL with PAT (`read:user`).
- LeetCode source: Public-profile-driven fetch path with GraphQL fallback adapter.
- Day boundary: User’s local macOS timezone.
- Refresh: App launch + periodic timer (every 60 min) + manual refresh.
- Sync policy contract:
  - Retry: up to 3 attempts per provider run (initial + 2 retries).
  - Backoff: exponential with jitter (2s, 8s, 20s max delay cap).
  - Rate limit cooldown: pause provider for 30 min after explicit rate-limit response.
  - Stale data warning: surface warning banner if last successful provider sync > 24h.
- Failures: Keep last known values, mark day/source as `unknown`, never auto-convert to inactive.
- Status model: `DayStatus` remains `active|inactive|unknown`; manual overrides are modeled separately with audit metadata (not status enum variants).
- Manual override: Enabled, with visible audit marker, note, and source attribution.
- Combined rule contract:
  - `active` only when GitHub = `active` AND LeetCode = `active`.
  - `inactive` when either source = `inactive`.
  - `unknown` when no source is `inactive` and at least one source is `unknown`.
- Notifications: Daily reminder + streak-risk alert (end-of-day if missing required activity).
- Notification behavior: dedupe to one streak-risk alert per day, with optional snooze-until-tomorrow.
- Secret handling: GitHub PAT stored in Keychain; invalid/revoked token transitions to explicit auth-error state with re-auth prompt.
- Rust interop approach: C ABI FFI (`cdylib`/`staticlib`) with a thin Swift adapter; avoid introducing TypeScript/Convex in v1.
- Distribution: Local dev build for initial milestones.

## Architecture

### App Modules
- `MenuBarUI`
  - Menu bar label/icon state.
  - Popover with streak cards, daily status timeline, sync status, settings entry.
- `SyncEngine`
  - Coordinates adapters, throttling, retries, and state merge.
- `Providers`
  - `GitHubProvider`
  - `LeetCodeProvider`
- `StreakEngine`
  - Computes current/longest streaks and completion rates from normalized day records.
- `RustCore` (learning track)
  - Pure functions for combined-day derivation + streak metrics.
  - No networking, persistence, or platform APIs.
- `Persistence`
  - SQLite models + repository.
- `NotificationEngine`
  - Schedules and triggers reminder/risk alerts.
- `Settings`
  - PAT, usernames, refresh interval, notification hour, timezone mode (local default).

### Data Flow
1. Timer/manual/app-launch triggers `SyncEngine`.
2. Providers fetch normalized daily activity windows.
3. `SyncEngine` upserts day records with provenance + confidence.
4. `StreakEngine` recomputes metrics.
5. UI updates menu bar + popover.
6. `NotificationEngine` evaluates today status and schedules/dispatches alerts.

## Public Interfaces / Types

### Core Types
```swift
enum ActivitySource: String { case github, leetcode, combined }
enum DayStatus: String { case active, inactive, unknown }
enum Provenance: String { case api, fallback, derived }

struct LocalDay: Hashable, Codable {
  let year: Int
  let month: Int
  let day: Int
}

struct ManualOverride {
  let day: LocalDay
  let source: ActivitySource
  let status: DayStatus // active|inactive only
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
  let manualOverride: ManualOverride?
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
  func fetchActivityDays(range: ClosedRange<Date>) async throws -> [LocalDay: DayStatus]
}
```

### Sync API
```swift
protocol SyncService {
  func refreshNow(trigger: SyncTrigger) async
}
```

### Rust FFI Surface (planned)
```c
// Input/Output encoded as UTF-8 JSON for simple boundary management in v1.
const char* derive_combined_json(const char* github_days_json, const char* leetcode_days_json);
const char* compute_metrics_json(const char* day_windows_json, const char* source, const char* as_of_day_json);
void free_rust_string(const char* ptr);
```

### Manual Override API
```swift
func setManualStatus(day: LocalDay, source: ActivitySource, status: DayStatus, note: String?)
func clearManualStatus(day: LocalDay, source: ActivitySource)
```

### DB Schema (minimal)
- `activity_days(date_local TEXT, source TEXT, status TEXT, provenance TEXT, updated_at DATETIME, PRIMARY KEY(date_local, source), CHECK (status IN ('active','inactive','unknown')), CHECK (source IN ('github','leetcode','combined')), CHECK (provenance IN ('api','fallback','derived')))`
- `manual_overrides(date_local TEXT, source TEXT, status TEXT, note TEXT, created_at DATETIME, updated_at DATETIME, PRIMARY KEY(date_local, source), CHECK (status IN ('active','inactive')))`
- `sync_runs(id, started_at, finished_at, status, error_summary, CHECK (status IN ('success','partial','failed','rate_limited')))`
- `settings(key TEXT PRIMARY KEY, value TEXT)`
- Indexes:
  - `idx_activity_days_source_date (source, date_local)`
  - `idx_sync_runs_started_at (started_at DESC)`
- Migration/versioning:
  - GRDB migrations with explicit identifiers.
  - SQLite `PRAGMA user_version` tracked and asserted at startup.

## UX Plan

### Menu Bar
- Compact indicator:
  - Primary: combined current streak (`B:12`)
  - Secondary color dot for today status (`green` active, `amber` unknown, `red` inactive).
- Popover sections:
  - Today status row: GitHub / LeetCode / Combined.
  - Streak cards: current + longest for each source.
  - 7d/30d completion summary.
  - Last sync + error banner (if any).
  - Actions: `Refresh now`, `Edit today`, `Open settings`.

### Settings
- GitHub username + PAT input (Keychain-stored secret with token validity check on save).
- LeetCode username.
- Notification toggle + reminder time.
- Risk alert dedupe + snooze preference.
- Refresh interval (default 60 min).
- Debug section: last provider response metadata.

## Milestones

1. Foundation
- Scaffold SwiftUI menu bar app.
- Add persistence layer, settings store, and domain models.
- Build static popover UI with mock data.

2. GitHub Integration
- Implement GraphQL fetch + mapper to local day statuses.
- Add retry/backoff, rate-limit handling, and unknown-state fallback.
- Enforce PAT auth error mapping and re-auth UX path.

3. LeetCode Integration
- Implement public-profile parser adapter.
- Add GraphQL fallback adapter.
- Normalize to daily activity map.

4. Streak/Combined Logic + Overrides
- Implement streak engine for each source and combined day truth table (`active`, `inactive`, `unknown`).
- Add manual override UI + audit marker.

5. Notifications + Operational Polish
- Daily reminder and streak-risk notifications.
- One risk alert per day dedupe + snooze-until-tomorrow behavior.
- Sync status/error UI and lightweight diagnostics.
- End-to-end smoke tests and acceptance pass.

6. Rust Domain Module (Learning Track, post-v1 usability)
- Define Rust crate boundary for pure domain logic (`DayStatus` truth table + streak metrics).
- Implement C ABI exports and Swift adapter layer.
- Add parity tests: Swift reference vectors must match Rust outputs exactly.
- Gate with feature flag/fallback: if Rust adapter fails, use Swift `StreakEngine`.

## Testing Plan

### Unit Tests
- Streak calculations across:
  - consecutive active days
  - gaps
  - unknown days
  - manual override precedence
- Combined-day derivation from source statuses.
- Combined-day truth table coverage including unknown/inactive precedence.
- Timezone/day-boundary conversion logic.
- Provider response parsing (GitHub + LeetCode adapters).
- `LocalDay` serialization/parsing roundtrip tests.

### Integration Tests
- Sync run writes expected DB rows and metrics.
- Failure mode: provider error marks days `unknown`, retains prior valid values.
- Manual override persists and survives refresh.
- Rate-limit cooldown behavior skips provider until cooldown expires.
- Migration smoke test (`user_version` and migration chain applies cleanly).
- Swift->Rust adapter roundtrip for JSON payloads, including malformed payload handling.
- Fallback behavior: Rust load/interop failure cleanly falls back to Swift engine.

### UI/Behavioral Tests
- Menu bar reflects updated metrics after refresh.
- Error banner appears on failed sync.
- Notification triggers at configured reminder time and risk window.
- Risk alert is not duplicated for the same local day; snooze suppresses until next day.

### Acceptance Scenarios
1. New user configures usernames + PAT; first sync populates last 30 days correctly.
2. Today has GitHub only -> combined inactive, correct streak transitions.
3. API failure day -> unknown status shown, no false streak break.
4. User manually marks day active -> streak recalculates and entry is audit-marked.
5. Next successful sync keeps manual override precedence unless user clears it.
6. One source unknown + other active -> combined unknown and no false inactive transition.
7. Rate-limited provider -> cooldown applied, stale-data warning shown after threshold.
8. Rust engine enabled -> metrics match Swift baseline for the same fixture dataset.
9. Rust engine unavailable -> app continues using Swift engine without data loss.

## Risks and Mitigations
- LeetCode endpoint instability: isolate adapter, add fallback chain, keep parser tests with fixtures.
- Rate limiting/API failures: backoff, cooldown, unknown-state semantics, manual refresh.
- Timezone edge cases (travel/DST): persist by local calendar day string and recompute on tz change.
- Rust/FFI complexity: keep boundary narrow (pure functions + JSON I/O), enforce parity fixtures, maintain Swift fallback path.

## Assumptions and Defaults
- Single macOS user, single GitHub account, single LeetCode account.
- Local-only data storage.
- PAT authentication for GitHub in v1.
- Local timezone as canonical day boundary.
- Refresh every 60 minutes while app runs.
- Notifications enabled by default after user grants permission.
- v1 includes simple trends (7/30-day completion), not chart-heavy analytics.
