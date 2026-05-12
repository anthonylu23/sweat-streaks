# Sweat Streaks

Sweat Streaks is a local-first macOS menu bar app that tracks daily activity streaks for GitHub, LeetCode, Codex, Claude Code, and a Combined status.

The menu bar popover uses window-style presentation for interactive controls, and account/preferences fields open in a dedicated macOS settings window with normal keyboard focus.
The collapsed menu bar item can show GitHub, LeetCode, Codex, Claude Code, and Combined current streak values; each source can be hidden from Settings. Settings also include provider tracking toggles so a configured account can be kept saved while its activity sync is disabled.

## Current Status
- Phase 0 complete: baseline planning and docs scaffolding.
- Phase 1 complete: app scaffold, core domain types, SQLite persistence, static menu bar UI, and foundational tests.
- Phase 2 complete: GitHub GraphQL provider, sync engine with retry/cooldown/stale handling, Keychain PAT storage, and app-level sync tests.
- MVP provider flow complete: GitHub + LeetCode sync, provider-generic orchestration, persisted provider state, effective manual overrides, combined status derivation, automatic refresh, and daily risk notifications.
- Provider module refactor complete: GitHub and LeetCode providers now live in separate SwiftPM targets behind the shared core provider contract.
- Agentic local provider flow complete: Codex and Claude Code local session/history logs map to active days and participate in Combined.

## Requirements
- macOS 13+
- Swift 6.0+

## Setup
```bash
swift build
```

## GitHub Setup
1. Open app settings.
2. Enable `Track GitHub activity`.
3. Set `GitHub Username`.
4. Set `New GitHub PAT` (stored in macOS Keychain, not SQLite).
5. Use a token with at least `read:user`.
6. Click `Save`, then `Refresh Now`.

The PAT field is write-only in normal use: leave it blank to keep the existing token. Use `Clear GitHub PAT` to remove it from Keychain.
Use `Save` to persist settings and keep the settings window open, or `Done` to save and close it.

## LeetCode Setup
1. Open app settings.
2. Enable `Track LeetCode activity`.
3. Set `LeetCode Username`.
4. Click `Save`, then `Refresh Now`.

LeetCode sync uses LeetCode's public, unofficial GraphQL profile calendar. If that response shape changes, the app will keep last known values and surface the provider error.

## Agentic Tool Setup
1. Open app settings.
2. Enable `Track Codex local activity` and/or `Track Claude Code local activity`.
3. Click `Save`, then `Refresh Now`.

Codex sync reads JSONL timestamps from `~/.codex/sessions` and `~/.codex/archived_sessions`.
Claude Code sync reads JSONL timestamps from `~/.claude/history.jsonl` and `~/.claude/projects`.
The app does not read, persist, display, or transmit Codex or Claude Code auth tokens.

## Sync Behavior
- Launch/manual/timer refresh configured providers independently.
- GitHub and LeetCode tracking can be disabled without clearing saved usernames or the saved GitHub PAT; disabled providers are omitted from sync until re-enabled.
- Disabled provider tracking is omitted from Combined streak derivation; re-enabling tracking includes that provider in Combined again.
- Disabled providers are hidden from the menu bar popover status rows, source picker, heatmap choices, and today override menu.
- Retry policy: up to 3 attempts with backoff (2s, 8s, 20s cap with jitter).
- Rate-limit handling: provider cooldown (30 minutes default).
- Stale detection: warning when last successful sync is older than 24 hours.
- Combined days are derived from enabled tracked provider statuses after manual overrides.
- Current streaks use an end-of-day grace rule: if today's provider status is not active yet, the displayed current streak is calculated through yesterday until local midnight. Manual inactive overrides reset immediately.
- Provider activity is clamped to the requested local-day window before persistence so UTC spillover dates do not create future local rows; stale future rows from earlier runs are removed on refresh.
- Manual overrides are stored separately from provider data and marked in the popover.
- The menu bar popover shows compact one-year calendar heatmaps for each provider and Combined activity.
- The runtime app icon uses bundled dark and light neutral variants and refreshes when the macOS appearance changes.

## Security Model
- GitHub PATs are stored in macOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- PATs are not stored in SQLite and are not loaded back into the settings field.
- Local SQLite data uses owner-only file permissions (`0600`).
- Provider endpoints must use HTTPS.
- Provider errors shown in UI are sanitized and do not include response bodies or tokens.
- LeetCode activity is read from a public profile calendar; do not use this app for private LeetCode activity that is not intended to be visible through that public endpoint.
- Codex and Claude Code activity is inferred from local timestamped JSONL logs only; prompt content and auth token values are not stored or displayed by Sweat Streaks.

## Notifications
- Enable `Send daily reminder` in settings.
- Configure `Notify after`.
- The app sends at most one risk notification per local day when today's combined status is not active after the reminder hour.

## Menu Bar Display
- Enable or hide `GitHub`, `LeetCode`, `Codex`, `Claude Code`, and `Combined` streak values from the Settings window.
- Provider menu-bar visibility toggles are disabled when that provider's activity tracking is disabled.
- The default collapsed status item shows current streak counts as compact icon-and-number pairs.
- If every source is hidden, the app shows `Sweat` in the menu bar.
- Hover the GitHub status dot for the latest GitHub contribution-calendar day/status. GitHub streaks only count activity that GitHub reports as contributions.

## Troubleshooting
- `Set GitHub PAT in settings`: PAT is missing in Keychain.
- `GitHub authentication failed`: PAT invalid/revoked or insufficient scope.
- `LeetCode user calendar was unavailable`: username may be wrong or LeetCode's public calendar response changed.
- `No Codex activity logs found`: Codex tracking is enabled but no local session JSONL files were found.
- `No Claude Code activity logs found`: Claude Code tracking is enabled but no local history/project JSONL files were found.
- `GitHub data is stale`: no successful sync in >24h.
- If `swift run` fails in a restricted shell, run outside sandboxed execution.

## Run
```bash
swift run SweatStreaksApp
```

## Test
```bash
swift test
```

## Project Structure
- `Package.swift`: package definition and targets.
- `Sources/SweatStreaksApp`: menu bar app UI, app state, provider registry, sync orchestration, and settings.
- `Sources/SweatStreaksApp/Resources/AppIcon`: dark and light 1024px app icon PNG variants used by the runtime icon manager.
- `Sources/SweatStreaksApp/SyncEngine.swift`: sync orchestration and provider state tracking.
- `Sources/SweatStreaksApp/NotificationEngine.swift`: once-per-day combined-streak risk notification logic.
- `Sources/SweatStreaksApp/CurrentStreakAnchorPolicy.swift`: app-level end-of-day grace policy for current streak metrics.
- `Sources/SweatStreaksApp/MenuBarStreakDisplay.swift`: compact status item selection and accessibility labels for configurable visible streaks.
- `Sources/SweatStreaksCore`: domain types and streak logic.
- `Sources/SweatStreaksPersistence`: SQLite schema/repository plus Keychain secret store.
- `Sources/SweatStreaksProviderSupport`: shared provider HTTP client, HTTPS enforcement, and rate-limit header parsing.
- `Sources/SweatStreaksProviderGitHub`: GitHub GraphQL fetch and response mapping.
- `Sources/SweatStreaksProviderLeetCode`: LeetCode public calendar fetch and response mapping.
- `Sources/SweatStreaksProviderLocalSupport`: shared local JSONL timestamp scanning helpers.
- `Sources/SweatStreaksProviderCodex`: Codex local session-log provider.
- `Sources/SweatStreaksProviderClaudeCode`: Claude Code local history/project-log provider.
- `Tests`: core, persistence, app sync/UI, and provider-module tests.
- `docs/architecture.md`: architecture and data flow.
- `docs/task-status.md`: implementation progress by phase.
- `docs/next-steps.md`: prioritized upcoming work.
