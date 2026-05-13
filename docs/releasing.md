# Releasing

Sweat Streaks currently ships as an unsigned macOS app bundle in a zip attached to GitHub Releases. Homebrew installs use the same zip through the `anthonylu23/homebrew-tap` cask.

## Prerequisites
- macOS 13+
- Xcode command line tools
- Swift 6.0+
- GitHub CLI authenticated with permission to push releases
- Homebrew for cask validation
- Repository secret `HOMEBREW_TAP_TOKEN` with contents read/write access to `anthonylu23/homebrew-tap`

## Automated Main-Branch Releases
The `CI` GitHub Actions workflow publishes a release after the Swift build/test
job passes on every push to `main`.

The release job:
1. Fetches tags and runs `scripts/next-release-version.sh "$GITHUB_SHA"`.
2. Reuses a stable `vX.Y.Z` tag already pointing at the current commit, which makes reruns safe after a partial failure.
3. Otherwise increments the latest stable semver tag by one patch version.
4. Builds the macOS zip with `scripts/package-release.sh "$VERSION"`.
5. Creates or updates the GitHub Release with generated notes and uploads the zip plus `.sha256`.
6. Checks out `anthonylu23/homebrew-tap`, updates `Casks/sweat-streaks.rb` with `scripts/update-homebrew-cask.sh`, audits the cask, then commits and pushes the tap update.

If the workflow publishes the GitHub Release but fails before pushing the tap,
rerun the failed workflow. The version helper should reuse the tag on that same
commit instead of creating another patch version.

## Build the Release Zip
```bash
swift test
swift build
swift build -c release --product SweatStreaksApp
scripts/package-release.sh v0.1.0
```

The packaging script writes:
- `dist/v0.1.0/Sweat Streaks.app`
- `dist/v0.1.0/Sweat-Streaks-v0.1.0-macos-$(uname -m).zip`
- `dist/v0.1.0/Sweat-Streaks-v0.1.0-macos-$(uname -m).zip.sha256`

The packaging script ad-hoc signs the completed `.app` bundle after writing
`Info.plist`, resources, and icons. This seals the bundle resources so macOS
does not reject the app as damaged because of an invalid bundle signature.

The app is not Developer ID signed or notarized. Users may need to approve the first launch in macOS Privacy & Security or install the cask with Homebrew quarantine disabled for personal/local builds.

## Validate the Artifact
```bash
plutil -lint "dist/v0.1.0/Sweat Streaks.app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "dist/v0.1.0/Sweat Streaks.app"
unzip -t "dist/v0.1.0/Sweat-Streaks-v0.1.0-macos-$(uname -m).zip"
script/build_and_run.sh --verify
```

Launch the app once from the unzipped bundle before publishing.

## Publish on GitHub
Manual publishing is a fallback for local release repair or GitHub Actions
incidents. Normal releases should come from pushes to `main`.

```bash
git tag v0.1.0
git push origin main --tags
gh release create v0.1.0 \
  "dist/v0.1.0/Sweat-Streaks-v0.1.0-macos-$(uname -m).zip" \
  --title "Sweat Streaks v0.1.0" \
  --notes-file docs/releases/v0.1.0.md
```

Use a draft release if the artifact has not been manually launched yet.

## Update Homebrew
The automated workflow updates the cask during normal releases. For manual
repair, the cask lives in `anthonylu23/homebrew-tap`:

```bash
SHA256=$(cut -d ' ' -f 1 "dist/v0.1.0/Sweat-Streaks-v0.1.0-macos-$(uname -m).zip.sha256")
scripts/update-homebrew-cask.sh 0.1.0 "$SHA256" ../homebrew-tap/Casks/sweat-streaks.rb
```

Then run:

```bash
brew tap anthonylu23/tap
brew audit --cask --strict anthonylu23/tap/sweat-streaks
brew install --cask anthonylu23/tap/sweat-streaks
```

## Future Signing Path
For a smoother public install, add Developer ID signing and notarization:
- Sign with a Developer ID Application certificate.
- Enable hardened runtime.
- Submit the zip or app bundle with `xcrun notarytool`.
- Staple the notarization ticket before zipping.

Until then, keep README and release notes explicit that downloads are unsigned.
