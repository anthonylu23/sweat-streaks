# Architecture

## Modules
- `scripts/package-release.sh`
  - Release helper that builds the SwiftPM executable, assembles an unsigned macOS `.app`, generates an app icon, and zips it for GitHub Releases/Homebrew.
- `script/build_and_run.sh`
  - Local development helper that stages a debug `.app` bundle from SwiftPM output and launches that bundle instead of running the GUI executable directly.
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
  - Shared local JSONL file discovery, timestamp parsing, local-day status map helpers, and privacy-preserving evidence diagnostics.
- `SweatStreaksProviderCodex`
  - Codex local activity provider reading timestamped session JSONL files.
- `SweatStreaksProviderClaudeCode`
  - Claude Code local activity provider reading timestamped history/project JSONL files.
- `SweatStreaksProviderCursor`
  - Cursor local activity provider reading AI usage timestamps and metadata.

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
  |     +-- CursorProvider -> SweatStreaksProviderCursor
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
- `SweatStreaksProviderLocalSupport` owns shared local timestamp-to-day mapping mechanics so local providers do not read auth tokens or depend on remote APIs.
- Combined status accepts an explicit required-source list. App-driven sync/recompute derives that list from enabled provider tracking toggles, so disabled providers are omitted from the Combined requirement.

## Data Model
- `activity_days`
  - Daily source status rows (`github|leetcode|codex|claude_code|cursor|combined`) with provenance and timestamps.
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
- LeetCode submission-calendar epoch keys are interpreted as UTC day buckets before mapping to `LocalDay`.
- Codex uses local JSONL logs under the configured Codex path, defaulting to `~/.codex`, and scans `sessions` plus `archived_sessions`.
- Claude Code uses local JSONL logs under the configured Claude Code path, defaulting to `~/.claude`, and scans `history.jsonl` plus `projects`.
- Cursor uses AI usage evidence under configured Cursor paths, defaulting to `~/.cursor` and `~/Library/Application Support/Cursor`, including local agent transcript metadata, worker logs, chat store metadata, `ai-tracking/ai-code-tracking.db`, and global `aiCodeTracking.dailyStats` keys.
- Local providers map at least one valid timestamp/evidence item in the requested local day to `active`; fetched days with no evidence are `inactive`.
- Local-provider diagnostics summarize configured roots, evidence types, counts, and latest evidence days. They do not display matched file paths, prompt text, chat text, edited file contents, auth tokens, or raw log lines.
- Codex and Claude Code JSONL files are streamed line by line for timestamp parsing.
- Codex, Claude Code, and Cursor auth token values, prompt text, chat text, and edited file contents are not persisted, displayed, or transmitted.
- Provider days outside the requested local-day fetch window are ignored before persistence, and stale future rows are deleted on refresh, to avoid UTC spillover rows.
- Provider fetch windows cover complete local days through 23:59:59.
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
7. Codex and Claude Code providers stream local JSONL log timestamps and map days:
   - one or more timestamps in a local day -> `active`
   - fetched days with no timestamps -> `inactive`
8. Cursor provider scans local AI usage timestamps/metadata and maps days:
   - one or more evidence items in a local day -> `active`
   - fetched days with no evidence -> `inactive`
9. Sync engine applies retry/backoff, auth/rate-limit classification, local-day window clamping, cooldown/stale state updates, and records `sync_runs` + `provider_states`.
10. Repository stores provider `activity_days`; combined status is derived from effective enabled-source statuses after manual overrides and persisted as `combined`.
11. App model recomputes UI status/metrics from persisted source days plus manual overrides.
12. App model chooses a current-streak anchor per source before computing metrics:
   - active today or manual active today -> today
   - provider inactive/unknown today -> yesterday
   - manual inactive today -> today
   - Combined manual inactive reset if either source has a manual inactive override today
13. App model publishes square timelines for GitHub, LeetCode, Codex, Claude Code, Cursor, and Combined activity; the popover currently displays the latest 13 weeks.
14. App model refreshes provider diagnostics after sync/settings changes and when Settings opens. Diagnostics include recent sync runs, provider state, and local evidence summaries for tracked local providers.
15. Notification engine sends at most one local risk notification per day when combined is not active after the configured reminder hour. Notification APIs are skipped when the executable is not running from an `.app` bundle, so direct SwiftPM executable launches do not crash.

## Distribution Flow
1. Pushes to `main` run GitHub Actions CI. After Swift validation passes, the release job computes the next stable patch tag with `scripts/next-release-version.sh`.
2. `scripts/package-release.sh vX.Y.Z` builds `SweatStreaksApp` in release mode, assembles `Sweat Streaks.app` with the SwiftPM executable/resources, generated `Info.plist`, and `.icns` icon, then zips it as `Sweat-Streaks-vX.Y.Z-macos-$(uname -m).zip`.
3. The release job creates or reuses the `vX.Y.Z` tag, publishes a GitHub Release with generated notes, and uploads the zip plus `.sha256`.
4. The same job updates `Casks/sweat-streaks.rb` in `anthonylu23/homebrew-tap` with `scripts/update-homebrew-cask.sh`, audits it with Homebrew, and pushes the cask version/checksum commit.
5. App-support directory and SQLite names intentionally stay `SweatStreaks` / `sweat_streaks.sqlite` so open-source repo renaming does not migrate local data.

## UI Windowing Notes
- The menu bar extra uses `.menuBarExtraStyle(.window)` because its content contains controls and opens editable settings.
- The popover displays compact 13-week calendar-style heatmaps for GitHub, LeetCode, Codex, Claude Code, Cursor, and Combined activity inside a fixed-width, tightly padded menu-bar window. The heatmap card groups the source label, stats, and grid into a centered compact cluster so the small 13-week grid does not appear adrift in the full card width. Square data uses the same effective day statuses as streak metrics, including manual override effects, and month labels are suppressed at tight boundaries when adjacent labels would collide.
- The popover enumerates `AppModel.trackedProviderSources` for provider status rows, source tabs, heatmap choices, and today overrides; disabled provider tracking hides that provider from the popover and returns a disabled selected source back to Combined.
- The collapsed menu bar label is derived from the same published streak metrics and today statuses as the popover. It renders configurable icon-and-number pairs using shared source icons for GitHub, LeetCode, Codex, Claude Code, Cursor, and Combined, while `MenuBarStreakDisplay` owns item selection and accessibility labels.
- Provider-specific menu bar visibility controls are disabled when their corresponding provider tracking toggle is off. `AppModel` also coerces those visibility settings off before saving, and `MenuBarStreakDisplay` filters disabled tracking sources as a defensive guard against stale persisted settings.
- The GitHub status row exposes the latest contribution-calendar day/status as hover help so users can distinguish raw commits from GitHub-counted contributions.
- Settings are hosted in a reusable `NSWindow` with an `NSHostingController`, which avoids relying on SwiftUI's settings responder-chain action from a menu-bar-only surface.
- Settings include a general `Start on login` toggle backed by `LaunchAtLoginManager`, which wraps `SMAppService.mainApp` registration/unregistration behind a testable protocol.
- Settings persist independent tracking toggles for GitHub, LeetCode, Codex, Claude Code, and Cursor. They also persist local provider root paths for Codex, Claude Code, and Cursor; folder picker controls choose those roots, reset controls restore documented defaults, and blank stored values are normalized back to defaults before save. `ProviderRegistry` only builds sync factories for providers whose tracking toggle and required account/local configuration are present, and the app passes the same enabled-source list as the Combined required-source list, so a saved username or PAT can remain in storage while provider activity sync is disabled.
- GitHub, LeetCode, Codex, Claude Code, and Cursor each render as separate settings sections with the same provider header and connection status pattern.
- Codex and Claude Code expose one folder picker each. Cursor exposes both its `~/.cursor` data root and its `~/Library/Application Support/Cursor` app-support root because usage evidence can live in either location.
- Settings include a Provider Diagnostics section with expandable rows for each provider. Rows show tracked/disabled state, persisted provider sync state, up to five recent sync runs, and local evidence summaries for tracked local providers.
- The app uses an `NSApplicationDelegate` to set accessory activation policy at launch so source-built runs stay menu-bar-only instead of appearing in the Dock. Generated debug and release bundles also set `LSUIElement=true` so macOS treats the app as a menu-bar agent from launch.
- The menu bar Settings button defers opening to the next main-actor turn, activates the app, explicitly makes the settings window key/front, and focuses the GitHub username field on appear.
- `AppIconManager` sets `NSApp.applicationIconImage` from bundled dark/light PNG resources at launch and when macOS appearance changes. This keeps the icon visible for SwiftPM-launched builds where there is no packaged app icon bundle.

## Remaining Architecture Work
1. Add Developer ID signing, hardened runtime, notarization, and universal arm64/x86_64 packaging.
2. Replace the current simple manual override menu with a richer editor for date selection, notes, and audit history.
3. Add a LeetCode fallback adapter if the public GraphQL calendar becomes unreliable.
4. Add UI smoke tests around menu bar state, settings, and override flows.
5. Consider extracting provider diagnostics into a dedicated window if the Settings section becomes too dense.
6. Consider preserving session counts or token/cost metrics separately from active-day status if product needs grow.
