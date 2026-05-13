# Next Steps

## Public Beta Polish
- Review committed public screenshots before posting broadly and replace any screenshot that exposes unwanted personal account details you do not want public.
- Post a soft-beta announcement to personal networks and small macOS/side-project communities, with clear unsigned-build install expectations.
- Defer Show HN/Product Hunt until at least one fresh install path is verified and early feedback confirms the setup flow is understandable.

## Completed Public Beta Validation
- Fresh-installed the Homebrew cask at v0.1.3, verified bundle signature, confirmed `LSUIElement=true`, launched the installed app, and quit it cleanly.
- Confirmed the GitHub repository topics are present: `macos`, `swift`, `menubar`, `streaks`, `local-first`, `github`, `leetcode`, `codex`, `cursor`, `claude-code`.
- Confirmed the latest GitHub Release and Homebrew cask both point at v0.1.3.

## Immediate Validation
- Run the app with real GitHub and LeetCode usernames.
- Verify GitHub and LeetCode tracking toggles suppress sync while preserving saved usernames/PAT state, then resume syncing when re-enabled.
- Verify Cursor tracking against your real local Cursor AI history and confirm chat/agent/code-assist activity matches the streak behavior you want.
- Verify Codex, Claude Code, and Cursor custom path settings against real alternate directories, including the Cursor app-support path.
- Verify `Start on login` registers and unregisters the bundled app in macOS Login Items on a real user account.
- Verify the compact popover on a real menu bar display with all providers enabled, especially segmented-control label fit and heatmap month-label spacing now that Cursor adds a sixth source.
- Verify LeetCode's public calendar returns expected recent days for the target account.
- Confirm macOS notification permission flow from a bundled app launch.
- Verify settings-window keyboard focus from the menu-bar-only accessory app on a fresh packaged install.

## MVP Hardening
- Add Developer ID signing, hardened runtime, notarization, and universal macOS builds.
- Decide whether automated releases should eventually update notarized/universal artifacts instead of the current unsigned arm64 zip.
- Add a richer manual override editor for arbitrary dates, custom notes, and audit review.
- Add UI smoke tests for settings window focus/text entry, settings save, refresh, provider-state display, and override toggles.
- Validate the Settings provider diagnostics section against real provider data and decide whether it should move into a dedicated window.
- Add a LeetCode fallback adapter if the public GraphQL profile calendar proves unreliable.
- Add richer local-provider diagnostics only if counts/latest-day summaries are insufficient during real-world validation.

## Product Polish
- Gather real-world feedback on the compact menu bar icon-and-number labels and adjust if they are too wide or unclear.
- Gather real-world feedback on the narrowed popover and adjust the width if the six-source picker feels cramped.
- Verify the selected dark/light app icon variants in a signed/notarized packaged `.app`.
- Add snooze controls for risk reminders.

## Optional Later
- Add optional session count, token, or cost metrics for local/agentic tools if there is a stable official source.
- Revisit the Rust domain core only if Swift domain logic becomes complex enough to justify FFI.
