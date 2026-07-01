#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ARCH="$(uname -m)"
DIST="$ROOT/dist"
APP="$DIST/LaunchDeck.app"
DMG_ROOT="$DIST/dmgroot"
DMG="$DIST/LaunchDeck-$VERSION-$ARCH.dmg"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
EXECUTABLE="$ROOT/.build/release/LaunchDeckApp"

swift build -c release --product LaunchDeckApp

rm -rf "$APP" "$DMG_ROOT" "$DMG"
mkdir -p "$MACOS" "$CONTENTS/Resources" "$DMG_ROOT"
cp "$EXECUTABLE" "$MACOS/LaunchDeck"
chmod +x "$MACOS/LaunchDeck"

/usr/libexec/PlistBuddy -c "Clear dict" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleName string LaunchDeck" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string LaunchDeck" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string io.github.launchdeck" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string LaunchDeck" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$CONTENTS/Info.plist"

plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP"

cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "LaunchDeck $VERSION" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG"
rm -rf "$DMG_ROOT"

echo "$DMG"
