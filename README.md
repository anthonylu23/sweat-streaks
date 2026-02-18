# Sweat Streaks

Sweat Streaks is a local-first macOS menu bar app that tracks daily activity streaks for GitHub, LeetCode, and a Combined status.

## Current Status
- Phase 0 complete: baseline planning and docs scaffolding.
- Phase 1 complete: app scaffold, core domain types, SQLite persistence, static menu bar UI, and foundational tests.
- Phase 2 complete: GitHub GraphQL provider, sync engine with retry/cooldown/stale handling, Keychain PAT storage, and app-level sync tests.

## Requirements
- macOS 13+
- Swift 6.0+

## Setup
```bash
swift build
```

## GitHub Setup
1. Open app settings.
2. Set `GitHub Username`.
3. Set `GitHub PAT` (stored in macOS Keychain, not SQLite).
4. Use a token with at least `read:user`.
5. Click `Save`, then `Refresh Now`.

## Sync Behavior
- Launch/manual refresh trigger GitHub sync (timer cadence remains configurable and will be wired to automatic scheduling in a later phase).
- Retry policy: up to 3 attempts with backoff (2s, 8s, 20s cap with jitter).
- Rate-limit handling: provider cooldown (30 minutes default).
- Stale detection: warning when last successful sync is older than 24 hours.

## Troubleshooting
- `Set GitHub PAT in settings`: PAT is missing in Keychain.
- `GitHub authentication failed`: PAT invalid/revoked or insufficient scope.
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
- `Sources/SweatStreaksApp`: menu bar app UI and app state.
- `Sources/SweatStreaksApp/GitHubProvider.swift`: GitHub GraphQL fetch and response mapping.
- `Sources/SweatStreaksApp/SyncEngine.swift`: sync orchestration and provider state tracking.
- `Sources/SweatStreaksCore`: domain types and streak logic.
- `Sources/SweatStreaksPersistence`: SQLite schema/repository plus Keychain secret store.
- `Tests`: core, persistence, and app sync/provider tests.
- `docs/architecture.md`: architecture and data flow.
- `docs/task-status.md`: implementation progress by phase.
- `docs/next-steps.md`: prioritized upcoming work.
