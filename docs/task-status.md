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
  - Added calendar heatmaps for GitHub contribution squares, LeetCode activity squares, and Combined activity squares in the menu bar popover.
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

## Phase 8: Codex + Claude Code Local Providers
- Status: Complete
- Completed:
  - Added `codex` and `claude_code` activity sources.
  - Added local JSONL scanning support shared by agentic tool providers.
  - Added `CodexProvider` for `~/.codex/sessions` and `~/.codex/archived_sessions`.
  - Added `ClaudeCodeProvider` for `~/.claude/history.jsonl` and `~/.claude/projects`.
  - Added settings toggles, status rows, heatmaps, menu-bar visibility controls, and manual overrides for both providers.
  - Updated SQLite source constraints and repository override validation for the new provider IDs.
  - Updated Combined semantics so GitHub, LeetCode, Codex, and Claude Code are all required.
  - Added provider, persistence, sync, menu-bar, and combined-status tests.
  - Validation run completed: `swift test`, `swift build`, and `swift run SweatStreaksApp` compile/launch sanity check.
- Notes:
  - V1 tracks active days only. Local auth tokens, prompt content, token counts, and costs are not stored or displayed.

## Phase 9: Provider Tracking Controls
- Status: Complete
- Completed:
  - Added persisted GitHub and LeetCode activity tracking toggles to settings.
  - Updated provider factory construction so disabled GitHub/LeetCode providers are omitted from sync without clearing saved credentials or usernames.
  - Threaded enabled provider tracking sources into Combined derivation during app-driven sync/recompute, so disabled providers do not block Combined.
  - Recomputed view state after saving tracking settings so Combined reflects disabled/re-enabled providers immediately.
  - Disabled provider-specific menu bar visibility controls when tracking is off, and filtered disabled tracking sources from the rendered status item.
  - Hid disabled tracking providers from popover status rows, heatmap source tabs, and today override menus.
  - Added ProviderRegistry tests for remote provider tracking toggle behavior.
  - Validation run completed: `swift test`, `swift build`, and `swift run SweatStreaksApp` compile/launch sanity check.
- Notes:
  - GitHub and LeetCode tracking default to enabled to preserve behavior for existing installations.

## Phase 10: Settings Menu Pass
- Status: Complete
- Completed:
  - Split Codex and Claude Code into separate settings sections so each local provider matches the GitHub/LeetCode header and connection-status layout.
  - Added persisted `Start on login` settings state.
  - Added a testable launch-at-login wrapper around `SMAppService.mainApp` registration/unregistration.
  - Added app-model tests for registering, unregistering, and surfacing launch-at-login failures during settings save.
  - Increased the compact heatmap grid to a 13-week range with larger squares to reduce empty card space.
- Notes:
  - `Start on login` launches the main menu bar app for the current macOS user and is applied on `Save` or `Done`.

## Phase 11: Compact Popover Pass
- Status: Complete
- Completed:
  - Narrowed the menu bar popover frame and reduced outer spacing.
  - Tightened the hero card icon/status-row sizing while keeping the same streak copy and source indicators.
  - Switched the source picker to small segmented-control sizing.
  - Reduced activity heatmap card padding, grid gaps, weekday-label width, and square size for the selected balanced compact mockup direction.
  - Centered the heatmap source label, stats, and grid as one compact cluster to avoid excessive perceived side padding inside the card.
- Notes:
  - The heatmap continues to show the latest 13 weeks; this pass changes density and footprint, not the date range.

## Phase 12: Cursor Local Provider
- Status: Complete
- Completed:
  - Added `cursor` as a persisted activity source and current provider source.
  - Added `SweatStreaksProviderCursor` for local Cursor AI usage tracking.
  - Cursor activity reads timestamp/metadata evidence from agent transcripts, worker logs, chat store metadata, Cursor AI-tracking SQLite state, and Cursor global daily-stat keys.
  - Added Cursor settings tracking toggle, connection status, status rows, heatmap tab, today overrides, menu-bar visibility control, and collapsed menu-bar display support.
  - Extended SQLite source constraints for `activity_days`, `manual_overrides`, and `provider_states`.
  - Added provider, persistence, sync, menu-bar, icon, registry, and combined-status tests.
  - Validation run completed: `swift test`, `swift build`, and `swift run SweatStreaksApp` compile/launch sanity check.
- Notes:
  - Cursor tracking counts local Cursor AI usage evidence, including chat/agent activity and AI code-tracking state.
  - Prompt text, chat text, edited file contents, and auth tokens are not stored or displayed.

## Phase 13: Local Provider Path Settings
- Status: Complete
- Completed:
  - Added persisted Settings folder picker controls for Codex, Claude Code, and Cursor local usage scanning.
  - Defaulted Codex to `~/.codex`, Claude Code to `~/.claude`, Cursor data to `~/.cursor`, and Cursor app support to `~/Library/Application Support/Cursor`.
  - Replaced manual path text entry with native macOS folder selection and reset controls.
  - Updated `ProviderRegistry` so local provider construction and connection checks use the configured paths.
  - Normalized blank stored path values back to documented defaults on load/save.
  - Added app-model tests for path persistence/default reset and registry tests proving configured local paths feed Codex, Claude Code, and Cursor providers.
- Validation:
  - `swift test --filter SweatStreaksAppTests`
  - `swift test`
  - `swift build`
  - `swift run SweatStreaksApp` compile/launch check, then stopped after launch

## Phase 14: Open Source Release Preparation
- Status: Complete
- Completed:
  - Chosen MIT license and first public distribution path.
  - Added release packaging documentation and a macOS app zip packaging script.
  - Added CI, contributing, security, and v0.1.0 release-note docs.
  - Added `.claude/` to `.gitignore` and prepared tracked Claude local settings for removal from the repository index.
  - Updated README for public install, provider setup, privacy/security, build/test, project structure, contribution, and license guidance.
  - Documented release architecture and Homebrew distribution flow.
  - Rename GitHub repository to `sweat-streaks`, make it public, and update local `origin`.
  - Publish `v0.1.0` release artifact.
  - Create/update the `anthonylu23/homebrew-tap` cask.
- Notes:
  - The v0.1.0 app zip is unsigned and not notarized.
  - Homebrew cask install validation completed with `brew install --cask anthonylu23/tap/sweat-streaks`.
  - The tracked `.claude/settings.local.json` file contained only a local test permission and no credentials before it was untracked.
  - Capture sanitized public screenshots from a clean profile.

## Phase 15: Release Readiness Fixes
- Status: Complete
- Completed:
  - Guarded macOS notification scheduling so direct SwiftPM executable launches do not crash outside an `.app` bundle.
  - Added `script/build_and_run.sh` and Codex Run action metadata for launching a SwiftPM-built GUI app through a staged debug `.app` bundle.
  - Changed sync fetch ranges to cover complete local days through 23:59:59.
  - Interpreted LeetCode submission-calendar epoch keys as UTC day buckets so US timezones do not shift activity to the prior local day.
  - Streamed local JSONL scanning line by line instead of loading entire agent log files into memory.
  - Replaced synthetic first-run sample activity with explicit unknown activity state.
  - Made release packaging use SwiftPM's reported release binary path and host architecture in artifact names.
  - Extended CI to run release build and package zip validation.
  - Added regression tests for notification non-bundle safety, late-night activity range coverage, LeetCode UTC day buckets, and empty first-run state.
- Validation:
  - `swift build`
  - `swift test`
  - `swift build -c release --product SweatStreaksApp`
  - `scripts/package-release.sh v0.1.0`
  - `unzip -t dist/v0.1.0/Sweat-Streaks-v0.1.0-macos-arm64.zip`
  - `script/build_and_run.sh --verify`
  - `swift run SweatStreaksApp` smoke check

## Phase 16: Homebrew Gatekeeper Fix
- Status: Complete for local packaging fix
- Completed:
  - Diagnosed the installed Homebrew cask app as failing Gatekeeper because the final `.app` bundle was never signed after resources and `Info.plist` were added.
  - Updated release packaging to ad-hoc sign and verify the completed app bundle before creating the zip.
  - Updated release docs to require bundle signature validation before publishing.
  - Rebuilt the local v0.1.0 release zip and replaced the installed `/Applications/Sweat Streaks.app` bundle with the fixed build.
- Validation:
  - `swift test`
  - `swift build`
  - `scripts/package-release.sh v0.1.0`
  - `unzip -t dist/v0.1.0/Sweat-Streaks-v0.1.0-macos-arm64.zip`
  - `codesign --verify --deep --strict --verbose=2 /Applications/Sweat Streaks.app`
  - `script/build_and_run.sh --verify`
  - `swift run SweatStreaksApp` compile/smoke check, then stopped after launch
- Notes:
  - The public v0.1.0 Homebrew artifact still needs to be rebuilt and republished with the fixed packaging script, then the cask checksum needs to be updated.
  - Developer ID signing and notarization remain the long-term distribution fix.

## Phase 17: Menu-Bar-Only App Presence
- Status: Complete
- Completed:
  - Changed app launch activation policy from regular to accessory so source-built launches do not appear in the Dock.
  - Updated debug and release app-bundle `Info.plist` generation to set `LSUIElement=true`.
  - Documented the menu-bar-only behavior in README and architecture notes.
- Validation:
  - `swift test`
  - `swift build`
  - `swift build -c release --product SweatStreaksApp`
  - `swift run SweatStreaksApp` compile/launch check, then stopped after launch
  - `scripts/package-release.sh v0.1.1-menu-bar`
  - `plutil -extract LSUIElement raw "dist/v0.1.1-menu-bar/Sweat Streaks.app/Contents/Info.plist"` returned `true`

## Phase 18: v0.1.1 Release
- Status: Complete
- Completed:
  - Added v0.1.1 release notes for the menu-bar-only patch release.
  - Updated README install/build examples to reference v0.1.1.
  - Built and validated the v0.1.1 macOS arm64 release zip.
  - Published GitHub Release v0.1.1 with `Sweat-Streaks-v0.1.1-macos-arm64.zip`.
  - Updated and pushed the Homebrew tap cask to version 0.1.1 with the new zip checksum.
- Validation:
  - `scripts/package-release.sh v0.1.1`
  - `unzip -t dist/v0.1.1/Sweat-Streaks-v0.1.1-macos-arm64.zip`
  - `codesign --verify --deep --strict --verbose=2 "dist/v0.1.1/Sweat Streaks.app"`
  - `plutil -extract LSUIElement raw "dist/v0.1.1/Sweat Streaks.app/Contents/Info.plist"` returned `true`
  - `gh release create v0.1.1 dist/v0.1.1/Sweat-Streaks-v0.1.1-macos-arm64.zip --title "Sweat Streaks v0.1.1" --notes-file docs/releases/v0.1.1.md`
  - `brew audit --cask --strict anthonylu23/tap/sweat-streaks`
  - `brew fetch --cask anthonylu23/tap/sweat-streaks`
