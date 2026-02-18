# Task Status

## Phase 0: Baseline + Documentation Scaffolding
- Status: Complete
- Completed:
  - Project plan updated and tightened.
  - Core docs scaffolded (`README`, `architecture`, `task-status`, `next-steps`).

## Phase 1: Foundation (App + Persistence + Static UI)
- Status: Complete
- Completed:
  - Swift package scaffolding with app/core/persistence/test targets.
  - Core domain types and interfaces implemented.
  - Streak and combined-status domain logic implemented.
  - SQLite schema and repository APIs implemented.
  - Static menu bar popover + settings screen scaffold implemented.
  - Initial unit/integration tests added for core and persistence.
  - Validation run completed: `swift build`, `swift test`, and `swift run SweatStreaksApp` launch sanity check.

## Phase 2: GitHub Provider + Sync Engine
- Status: Complete
- Completed:
  - Added `GitHubProvider` using GitHub GraphQL contribution calendar mapping.
  - Added `DefaultSyncService` with retry/backoff, rate-limit cooldown, and stale-state logic.
  - Added Keychain-backed PAT storage via `KeychainSecretStore`.
  - Integrated app model/UI with sync state, auth error messaging, and stale warnings.
  - Added app-level tests for provider mapping/errors and sync retry/cooldown/stale scenarios.
  - Added persistence tests for latest sync/day helpers and override source validation.
  - Validation run completed: `swift build`, `swift test`, and `swift run SweatStreaksApp` launch sanity check.

## Phase 3: LeetCode Provider + Multi-Provider Merge
- Status: Not Started

## Phase 4: Streak Engine + Combined + Manual Overrides
- Status: Not Started

## Phase 5: Notifications + UX Hardening
- Status: Not Started

## Phase 6: Optional Rust Domain Core
- Status: Not Started
