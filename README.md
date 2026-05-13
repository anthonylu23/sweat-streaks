# Sweat Streaks

Sweat Streaks is a local-first macOS menu bar app for tracking daily activity streaks across GitHub, LeetCode, Codex, Claude Code, Cursor, and a Combined status. It runs as a menu-bar-only app and does not show a Dock icon while open.

It keeps activity data on your Mac, stores GitHub tokens in Keychain, and infers local AI-tool activity from timestamps and metadata without storing prompt text, chat text, edited file contents, or auth tokens.

## Status
- macOS 13+.
- Swift 6.0+ for source builds.
- First public distribution is an unsigned macOS arm64 app zip.
- Developer ID signing, notarization, universal builds, and richer screenshots are planned follow-ups.

## Install

### GitHub Release
1. Download `Sweat-Streaks-v0.1.1-macos-arm64.zip` from the latest GitHub Release.
2. Unzip it and move `Sweat Streaks.app` to `/Applications`.
3. Launch the app. Because the first release is not notarized, macOS may require approval in System Settings -> Privacy & Security.

### Homebrew
```bash
brew tap anthonylu23/tap
brew install --cask sweat-streaks
```

### From Source
```bash
git clone https://github.com/anthonylu23/sweat-streaks.git
cd sweat-streaks
swift build
script/build_and_run.sh
```

## Screenshots
Public screenshots are tracked under `docs/assets` once captured from a clean profile with placeholder accounts. Screenshots should not include real usernames, local filesystem paths, tokens, or private provider errors.

## Provider Setup

### GitHub
1. Open app settings.
2. Enable `Track GitHub activity`.
3. Set `GitHub Username`.
4. Set `New GitHub PAT`.
5. Use a token with at least `read:user`.
6. Click `Save`, then `Refresh Now`.

GitHub PATs are stored in macOS Keychain and are not stored in SQLite or loaded back into the settings field. Leave the PAT field blank to keep the existing token, or use `Clear GitHub PAT` to remove it.

### LeetCode
1. Open app settings.
2. Enable `Track LeetCode activity`.
3. Set `LeetCode Username`.
4. Click `Save`, then `Refresh Now`.

LeetCode sync uses LeetCode's public, unofficial GraphQL profile calendar. If that response shape changes, the app keeps last known values and surfaces the provider error.
Submission-calendar epoch keys are interpreted as UTC day buckets so local timezones do not shift activity to the previous day.

### Local AI Tools
1. Open app settings.
2. Enable `Track Codex local activity`, `Track Claude Code local activity`, and/or `Track Cursor local activity`.
3. Keep the default paths or use `Choose` to select custom folders.
4. Click `Save`, then `Refresh Now`.

Default scan locations:
- Codex: `~/.codex/sessions` and `~/.codex/archived_sessions`
- Claude Code: `~/.claude/history.jsonl` and `~/.claude/projects`
- Cursor: `~/.cursor` and `~/Library/Application Support/Cursor`

Cursor scans local AI usage evidence such as transcript metadata, worker logs, chat-store metadata, Cursor AI-tracking SQLite state, and global AI daily-stat keys when present.
JSONL logs are streamed line by line and only timestamp fields are parsed for active-day detection.

## Sync Behavior
- Launch, manual, and timer refreshes run configured providers independently.
- Fetch windows cover the full local day through 23:59:59.
- Disabled provider tracking preserves saved usernames/tokens/paths but omits that provider from sync and Combined streak derivation.
- Retry policy uses up to 3 attempts with backoff.
- Rate-limited providers enter a cooldown state.
- Stale detection warns when last successful sync is older than 24 hours.
- Combined days are derived from enabled provider statuses after manual overrides.
- Current streaks use an end-of-day grace rule: if today's provider status is not active yet, the displayed current streak is calculated through yesterday until local midnight. Manual inactive overrides reset immediately.
- Settings include provider diagnostics with recent sync runs, persisted sync state, and local-provider evidence counts by configured root/type.
- Local-provider diagnostics show counts and latest evidence days, not matched file paths or private content.

## Privacy and Security
- GitHub PATs are stored in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Local SQLite data uses owner-only file permissions (`0600`).
- Provider requests must use HTTPS.
- Provider errors shown in UI are sanitized and do not include response bodies or tokens.
- Local Codex, Claude Code, and Cursor providers infer activity from local timestamps/metadata only.
- Prompt text, chat text, edited file contents, and local tool auth tokens are not stored, displayed, or transmitted by Sweat Streaks.
- LeetCode activity is read from a public profile calendar; do not use it for private activity that is not intended to be visible through that endpoint.

## Build and Test
```bash
swift build
swift test
swift build -c release --product SweatStreaksApp
script/build_and_run.sh --verify
scripts/package-release.sh v0.1.1
```

See `docs/releasing.md` for the automated main-branch release flow, required Homebrew tap token, manual fallback, and local packaging checklist.

## Troubleshooting
- `Set GitHub PAT in settings`: PAT is missing in Keychain.
- `GitHub authentication failed`: PAT is invalid, revoked, or missing required scope.
- `LeetCode user calendar was unavailable`: username may be wrong or LeetCode's public calendar response changed.
- `No Codex activity logs found`: Codex tracking is enabled but no local session JSONL files were found.
- `No Claude Code activity logs found`: Claude Code tracking is enabled but no local history/project JSONL files were found.
- `No Cursor AI activity found`: Cursor tracking is enabled but no supported local AI usage evidence was found.
- `GitHub data is stale`: no successful sync in more than 24 hours.
- Use Settings -> Provider Diagnostics to inspect recent provider sync runs, cooldown/stale state, and local evidence counts.
- If unsigned builds are blocked by Gatekeeper, approve the app in System Settings -> Privacy & Security.
- If a Homebrew install says the app is damaged, verify the bundle signature with `codesign --verify --deep --strict --verbose=2 /Applications/Sweat\ Streaks.app`. A `code has no resources but signature indicates they must be present` error means the release zip was built without signing the completed app bundle.

## Project Structure
- `Package.swift`: SwiftPM package definition and targets.
- `Sources/SweatStreaksApp`: menu bar UI, app state, provider registry, sync orchestration, settings, notifications, launch-at-login, and runtime icon handling.
- `Sources/SweatStreaksCore`: domain types and streak logic.
- `Sources/SweatStreaksPersistence`: SQLite schema/repository plus Keychain secret storage.
- `Sources/SweatStreaksProviderSupport`: shared provider HTTP client, HTTPS enforcement, and rate-limit parsing.
- `Sources/SweatStreaksProviderLocalSupport`: shared local timestamp scanning helpers.
- `Sources/SweatStreaksProviderGitHub`: GitHub contribution-calendar provider.
- `Sources/SweatStreaksProviderLeetCode`: LeetCode public-calendar provider.
- `Sources/SweatStreaksProviderCodex`: Codex local session-log provider.
- `Sources/SweatStreaksProviderClaudeCode`: Claude Code local history/project-log provider.
- `Sources/SweatStreaksProviderCursor`: Cursor local usage provider.
- `Tests`: core, persistence, app sync/UI, and provider tests.
- `scripts/package-release.sh`: release app-bundle/zip packaging script.
- `docs`: architecture, release, task-status, and next-step notes.

## Contributing
Issues and pull requests are welcome. Keep changes scoped, run `swift test`, and update README/docs when behavior, setup, architecture, or release process changes. See `CONTRIBUTING.md`.

## License
MIT. See `LICENSE`.
