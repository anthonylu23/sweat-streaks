# Next Steps

## Immediate Validation
- Run the app with real GitHub and LeetCode usernames.
- Verify GitHub and LeetCode tracking toggles suppress sync while preserving saved usernames/PAT state, then resume syncing when re-enabled.
- Verify LeetCode's public calendar returns expected recent days for the target account.
- Confirm macOS notification permission flow from the SwiftPM-launched app.

## MVP Hardening
- Add a richer manual override editor for arbitrary dates, custom notes, and audit review.
- Add UI smoke tests for settings window focus/text entry, settings save, refresh, provider-state display, and override toggles.
- Add a diagnostics view for recent sync runs and provider error history.
- Add a LeetCode fallback adapter if the public GraphQL profile calendar proves unreliable.
- Add diagnostics for local provider log discovery, including which local paths are being scanned without exposing file contents.

## Product Polish
- Gather real-world feedback on the compact menu bar icon-and-number labels and adjust if they are too wide or unclear.
- Verify the selected dark/light app icon variants in a packaged `.app` once distribution packaging is introduced.
- Add snooze controls for risk reminders.

## Optional Later
- Add a Cursor local provider once a reliable local activity source is identified.
- Add optional session count, token, or cost metrics for agentic tools if there is a stable official source.
- Revisit the Rust domain core only if Swift domain logic becomes complex enough to justify FFI.
