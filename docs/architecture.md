# Architecture

## Modules
- `SweatStreaksApp`
  - SwiftUI menu bar scene (`MenuBarExtra`), popover content, settings view, app model, GitHub provider, and sync engine.
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

## Data Rules
- Local day format is strict ISO `YYYY-MM-DD`.
- Combined status derives from effective source statuses after manual overrides.
- Unknown statuses do not auto-convert to inactive.
- GitHub PAT is stored in Keychain, not in SQLite settings.

## Current Runtime Flow (Phase 2)
1. App starts and initializes local SQLite database.
2. App model loads local settings and GitHub PAT from Keychain.
3. On launch/manual trigger, sync engine resolves fetch range:
   - Initial: 90 days if no prior GitHub data.
   - Incremental: 14 days when prior data exists.
4. GitHub provider calls GraphQL contribution calendar and maps days:
   - `contributionCount > 0` -> `active`
   - `0` -> `inactive`
5. Sync engine applies retry/backoff, auth/rate-limit classification, and cooldown/stale state updates.
6. Repository stores `activity_days` + `sync_runs`; combined status is derived and persisted.
7. UI refreshes today statuses, metrics, auth warnings, cooldown/stale warnings.

## Planned Runtime Flow (Phase 3+)
1. Add LeetCode provider primary/fallback chain.
2. Run multi-provider merge with partial-success handling.
3. Expand combined derivation to include both providers with override precedence.
4. Add notifications and operational diagnostics.
