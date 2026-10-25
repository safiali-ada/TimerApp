#!/bin/bash
# Builds TimerApp.app next to this script using swiftc only, for quick local use.
# App Store releases are archived from TimerApp.xcodeproj instead (see README).
set -euo pipefail
cd "$(dirname "$0")"

APP="TimerApp.app"
EXE="TimerApp"
MIN_OS="13.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling..."
swiftc -O -swift-version 5 \
    -target "$(uname -m)-apple-macos$MIN_OS" \
    -o "$APP/Contents/MacOS/$EXE" \
    Sources/*.swift

# The asset catalog's PNGs use iconutil's naming, so the same folder doubles as an .iconset.
ICONSET="$(mktemp -d)/AppIcon.iconset"
cp -R Resources/Assets.xcassets/AppIcon.appiconset "$ICONSET"
rm "$ICONSET/Contents.json"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>TimerApp</string>
    <key>CFBundleDisplayName</key><string>Timer</string>
    <key>CFBundleIdentifier</key><string>com.syedsafiali.TimerApp</string>
    <key>CFBundleExecutable</key><string>$EXE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS treats the bundle as a valid, launchable app.
codesign --force --sign - "$APP" >/dev/null

echo "Built $(pwd)/$APP"
