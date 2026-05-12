# Next Steps

## Immediate Validation
- Run the app with real GitHub and LeetCode usernames.
- Verify LeetCode's public calendar returns expected recent days for the target account.
- Confirm macOS notification permission flow from the SwiftPM-launched app.

## MVP Hardening
- Add a richer manual override editor for arbitrary dates, custom notes, and audit review.
- Add UI smoke tests for settings window focus/text entry, settings save, refresh, provider-state display, and override toggles.
- Add a diagnostics view for recent sync runs and provider error history.
- Add a LeetCode fallback adapter if the public GraphQL profile calendar proves unreliable.
- Before adding Codex, Claude Code, or Cursor streaks, design a local activity evidence model that can normalize sessions/events into provider day statuses without changing the sync contract.

## Product Polish
- Gather real-world feedback on the compact menu bar icon-and-number labels and adjust if they are too wide or unclear.
- Verify the selected dark/light app icon variants in a packaged `.app` once distribution packaging is introduced.
- Add snooze controls for risk reminders.

## Optional Later
- Add local tool providers for Codex, Claude Code, and Cursor once the evidence model is defined.
- Revisit the Rust domain core only if Swift domain logic becomes complex enough to justify FFI.
