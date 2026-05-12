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
- Status: Complete for MVP
- Completed:
  - Added `LeetCodeProvider` using the public profile calendar GraphQL query.
  - Refactored sync orchestration to run configured providers in deterministic order.
  - Persisted provider sync state (`lastSuccessAt`, cooldown, last error, stale flag).
  - Added tests for LeetCode calendar mapping, rate limits, multi-provider combined derivation, and provider-state persistence.
- Notes:
  - LeetCode is an unofficial public endpoint; fallback adapter remains a hardening task.

## Phase 4: Streak Engine + Combined + Manual Overrides
- Status: Complete for MVP
- Completed:
  - Combined status now derives from effective GitHub + LeetCode statuses after manual overrides.
  - Manual overrides are persisted and shown in the popover with an audit marker.
  - Popover supports toggling/clearing today's GitHub and LeetCode overrides.
  - Streak math now consistently uses the caller-provided timezone.
  - Current streaks now support an alternate anchor day so the app can show a through-yesterday streak before the current local day is complete.
  - Added tests for override-influenced combined derivation and DST/timezone streak behavior.
  - Added tests for end-of-day grace behavior and manual inactive reset policy.
  - Added exact regression coverage for the GitHub yesterday-only streak case.
- Notes:
  - Rich override editing for arbitrary dates and custom notes remains future work.

## Phase 5: Notifications + UX Hardening
- Status: Complete for MVP
- Completed:
  - Added automatic timer refresh based on saved refresh interval.
  - Added optional daily risk notifications when combined status is not active after the configured reminder hour.
  - Added per-provider sync summaries in the popover.
  - Added one-year calendar heatmaps for GitHub contribution squares, LeetCode activity squares, and Combined activity squares in the menu bar popover.
  - Hardened menu bar/settings windowing so the popover uses window-style presentation, the app has regular activation, and settings open in a key AppKit-backed window with focused editable SwiftUI fields.
  - Added configurable collapsed menu bar streak values for GitHub, LeetCode, and Combined.
  - Switched source markers to shared logo-style icons for GitHub, LeetCode, and Combined, including the collapsed menu bar streak label.
  - Added GitHub contribution-calendar diagnostics in the status-row tooltip.
  - Tightened heatmap square sizing and made month labels collision-aware so compact ranges do not overlap adjacent month names.
  - Clamped provider persistence to requested local-day ranges to avoid future UTC spillover rows.
  - Added tests for notification dedupe and active-status suppression.
  - Added tests for collapsed menu bar streak formatting and visibility filtering.
  - Added neutral dark/light app icon resources and runtime appearance-aware icon selection.
- Notes:
  - UI smoke tests and richer diagnostics remain future work.

## Phase 6: Optional Rust Domain Core
- Status: Not Started

## Phase 7: Provider Module Refactor
- Status: Complete
- Completed:
  - Split shared provider HTTP support into `SweatStreaksProviderSupport`.
  - Moved GitHub provider implementation and tests into `SweatStreaksProviderGitHub`.
  - Moved LeetCode provider implementation and tests into `SweatStreaksProviderLeetCode`.
  - Added an app-level `ProviderRegistry` to construct configured providers for the sync service.
  - Centralized the current provider source list in core and updated sync/anchor logic to consume it.
  - Extended combined status derivation to accept explicit required sources while preserving GitHub + LeetCode behavior.
  - Validation run completed: `swift test`, `swift build`, and `swift run SweatStreaksApp` compile/launch sanity check.
- Notes:
  - Local tool streaks for Codex, Claude Code, and Cursor remain future work and should be designed around normalized local activity evidence.
