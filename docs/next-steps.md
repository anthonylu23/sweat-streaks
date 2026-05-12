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

## Product Polish
- Gather real-world feedback on the compact menu bar labels (`GH`, `LC`, `All`) and adjust if they are too wide or unclear.
- Add true intensity levels to heatmap squares if provider storage starts preserving daily contribution/submission counts.
- Add snooze controls for risk reminders.

## Optional Later
- Revisit the Rust domain core only if Swift domain logic becomes complex enough to justify FFI.
