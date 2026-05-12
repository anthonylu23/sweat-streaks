# Releasing

Sweat Streaks currently ships as an unsigned macOS arm64 app bundle in a zip attached to GitHub Releases. Homebrew installs use the same zip through the `anthonylu23/homebrew-tap` cask.

## Prerequisites
- macOS 13+
- Xcode command line tools
- Swift 6.0+
- GitHub CLI authenticated with permission to push releases
- Homebrew for cask validation

## Build the Release Zip
```bash
swift test
swift build
swift build -c release --product SweatStreaksApp
scripts/package-release.sh v0.1.0
```

The packaging script writes:
- `dist/v0.1.0/Sweat Streaks.app`
- `dist/v0.1.0/Sweat-Streaks-v0.1.0-macos-arm64.zip`
- `dist/v0.1.0/Sweat-Streaks-v0.1.0-macos-arm64.zip.sha256`

The app is not Developer ID signed or notarized. Users may need to approve the first launch in macOS Privacy & Security.

## Validate the Artifact
```bash
plutil -lint "dist/v0.1.0/Sweat Streaks.app/Contents/Info.plist"
unzip -t dist/v0.1.0/Sweat-Streaks-v0.1.0-macos-arm64.zip
```

Launch the app once from the unzipped bundle before publishing.

## Publish on GitHub
```bash
git tag v0.1.0
git push origin main --tags
gh release create v0.1.0 \
  dist/v0.1.0/Sweat-Streaks-v0.1.0-macos-arm64.zip \
  --title "Sweat Streaks v0.1.0" \
  --notes-file dist/v0.1.0/release-notes.md
```

Use a draft release if the artifact has not been manually launched yet.

## Update Homebrew
The cask lives in `anthonylu23/homebrew-tap`:

```bash
SHA256=$(cut -d ' ' -f 1 dist/v0.1.0/Sweat-Streaks-v0.1.0-macos-arm64.zip.sha256)
```

Update `Casks/sweat-streaks.rb` with the new version and checksum, then run:

```bash
brew audit --cask --strict Casks/sweat-streaks.rb
brew install --cask --no-quarantine ./Casks/sweat-streaks.rb
```

## Future Signing Path
For a smoother public install, add Developer ID signing and notarization:
- Sign with a Developer ID Application certificate.
- Enable hardened runtime.
- Submit the zip or app bundle with `xcrun notarytool`.
- Staple the notarization ticket before zipping.

Until then, keep README and release notes explicit that downloads are unsigned/ad-hoc signed.
