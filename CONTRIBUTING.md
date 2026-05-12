# Contributing

Thanks for helping improve Sweat Streaks.

## Local Setup
```bash
swift build
swift test
swift run SweatStreaksApp
```

## Expectations
- Keep changes scoped and easy to review.
- Add or update tests for behavior changes.
- Update README or docs when setup, architecture, release flow, privacy behavior, or user-visible functionality changes.
- Do not commit local tool settings, tokens, screenshots with personal data, build artifacts, or release zips.

## Release Changes
Distribution changes should update:
- `README.md`
- `docs/releasing.md`
- `docs/task-status.md`
- `docs/next-steps.md`
- Homebrew cask metadata in `anthonylu23/homebrew-tap` when a release artifact changes.
