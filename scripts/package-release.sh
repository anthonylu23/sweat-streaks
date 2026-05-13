#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/package-release.sh vX.Y.Z" >&2
  exit 64
fi

VERSION="$1"
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Version must look like v0.1.0" >&2
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Sweat Streaks"
EXECUTABLE_NAME="SweatStreaksApp"
BUNDLE_IDENTIFIER="com.anthonylu23.SweatStreaks"
RESOURCE_BUNDLE="sweat-streaks_SweatStreaksApp.bundle"
DIST_DIR="$ROOT_DIR/dist/$VERSION"
RELEASE_ARCH="${SWEAT_STREAKS_RELEASE_ARCH:-$(uname -m)}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ZIP_NAME="Sweat-Streaks-${VERSION}-macos-${RELEASE_ARCH}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
SHA_PATH="$ZIP_PATH.sha256"

rm -rf "$DIST_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

swift build -c release --product "$EXECUTABLE_NAME"
BUILD_DIR="$(swift build -c release --show-bin-path)"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"

if [[ -d "$BUILD_DIR/$RESOURCE_BUNDLE" ]]; then
  cp -R "$BUILD_DIR/$RESOURCE_BUNDLE" "$RESOURCES_DIR/$RESOURCE_BUNDLE"
else
  echo "Missing SwiftPM resource bundle: $BUILD_DIR/$RESOURCE_BUNDLE" >&2
  exit 1
fi

ICON_SOURCE="$ROOT_DIR/Sources/SweatStreaksApp/Resources/AppIcon/app-icon-light.png"
if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing icon source: $ICON_SOURCE" >&2
  exit 1
fi

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION#v}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION#v}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Anthony Lu. All rights reserved.</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS_DIR/Info.plist"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

(
  cd "$DIST_DIR"
  zip -qry -X "$ZIP_NAME" "$APP_NAME.app"
  shasum -a 256 "$ZIP_NAME" > "$SHA_PATH"
)

echo "Created $ZIP_PATH"
echo "SHA-256: $(cut -d ' ' -f 1 "$SHA_PATH")"
echo "Note: this release bundle is unsigned and not notarized."
