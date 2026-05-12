# Next Steps

## Immediate Validation
- Run the app with real GitHub and LeetCode usernames.
- Verify GitHub and LeetCode tracking toggles suppress sync while preserving saved usernames/PAT state, then resume syncing when re-enabled.
- Verify Cursor tracking against your real local Cursor AI history and confirm chat/agent/code-assist activity matches the streak behavior you want.
- Verify Codex, Claude Code, and Cursor custom path settings against real alternate directories, including the Cursor app-support path.
- Verify `Start on login` registers and unregisters the SwiftPM-launched app in macOS Login Items on a real user account.
- Verify the compact popover on a real menu bar display with all providers enabled, especially segmented-control label fit and heatmap month-label spacing now that Cursor adds a sixth source.
- Verify LeetCode's public calendar returns expected recent days for the target account.
- Confirm macOS notification permission flow from the SwiftPM-launched app.

## MVP Hardening
- Add a richer manual override editor for arbitrary dates, custom notes, and audit review.
- Add UI smoke tests for settings window focus/text entry, settings save, refresh, provider-state display, and override toggles.
- Add a diagnostics view for recent sync runs and provider error history.
- Add a LeetCode fallback adapter if the public GraphQL profile calendar proves unreliable.
- Add diagnostics for local provider log discovery, including which configured local paths produced evidence without exposing file contents.

## Product Polish
- Gather real-world feedback on the compact menu bar icon-and-number labels and adjust if they are too wide or unclear.
- Gather real-world feedback on the narrowed popover and adjust the width if the six-source picker feels cramped.
- Verify the selected dark/light app icon variants in a packaged `.app` once distribution packaging is introduced.
- Add snooze controls for risk reminders.

## Optional Later
- Add optional session count, token, or cost metrics for local/agentic tools if there is a stable official source.
- Revisit the Rust domain core only if Swift domain logic becomes complex enough to justify FFI.
