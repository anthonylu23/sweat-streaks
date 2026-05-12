# Security

Sweat Streaks stores GitHub PATs in macOS Keychain and keeps local activity data on the user's Mac. Local AI-tool providers should only infer activity from timestamps or metadata; they must not persist prompt text, chat text, edited file contents, or local auth tokens.

## Reporting
For now, report security issues privately to the repository owner rather than opening a public issue with exploit details. Include:
- affected version or commit
- provider or subsystem involved
- reproduction steps
- whether credentials, local files, or private activity data may be exposed

## Supported Versions
Only the latest public release is supported during the early open-source phase.
