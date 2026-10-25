#!/bin/bash
# Builds TimerApp.app next to this script using swiftc only (no Xcode project needed).
#
#   ./build.sh            local build, ad-hoc signed, not sandboxed
#   ./build.sh appstore   sandboxed, signed for the Mac App Store, packaged as TimerApp.pkg
#
# App Store builds need Resources/embedded.provisionprofile (a "Mac App Store Connect" profile for
# the bundle id below) and the "Apple Distribution" and "Mac Installer Distribution" certificates
# in your keychain. Override VERSION / BUILD to set the version shown in the store and the build number.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-dev}"
APP="TimerApp.app"
EXE="TimerApp"
BUNDLE_ID="com.syedsafiali.TimerApp"
MIN_OS="13.0"
VERSION="${VERSION:-1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
PROFILE="Resources/embedded.provisionprofile"

if [[ "$MODE" == "appstore" ]]; then
    ARCHS=(arm64 x86_64)
    [[ -f "$PROFILE" ]] || { echo "Missing $PROFILE (download it from developer.apple.com > Profiles)." >&2; exit 1; }
else
    ARCHS=("$(uname -m)")
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "Rendering icon..."
    TMP_TOOL="$(mktemp -d)/makeicon"
    swiftc -O -swift-version 5 -o "$TMP_TOOL" Tools/MakeIcon/main.swift $(ls Sources/*.swift | grep -v main.swift)
    "$TMP_TOOL" Resources/AppIcon.icns
fi

echo "Compiling for ${ARCHS[*]}..."
SLICES=()
for arch in "${ARCHS[@]}"; do
    swiftc -O -swift-version 5 \
        -target "$arch-apple-macos$MIN_OS" \
        -o "$APP/Contents/MacOS/$EXE-$arch" \
        Sources/*.swift
    SLICES+=("$APP/Contents/MacOS/$EXE-$arch")
done
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/$EXE"
rm "${SLICES[@]}"

cp Resources/AppIcon.icns Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"

# The DT* keys tell App Store Connect which SDK and Xcode built the app.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
XCODE_VERSION="$(xcodebuild -version | awk '/^Xcode/ { split($2, v, "."); printf "%d%d%d", v[1], v[2], v[3] }')"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>TimerApp</string>
    <key>CFBundleDisplayName</key><string>Timer</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
    <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Syed Safi Ali</string>
    <key>ITSAppUsesNonExemptEncryption</key><false/>
    <key>DTPlatformName</key><string>macosx</string>
    <key>DTPlatformVersion</key><string>$SDK_VERSION</string>
    <key>DTSDKName</key><string>macosx$SDK_VERSION</string>
    <key>DTSDKBuild</key><string>$(xcrun --sdk macosx --show-sdk-build-version)</string>
    <key>DTXcode</key><string>$XCODE_VERSION</string>
    <key>DTXcodeBuild</key><string>$(xcodebuild -version | awk '/Build version/ { print $3 }')</string>
    <key>DTCompiler</key><string>com.apple.compilers.llvm.clang.1_0</string>
    <key>BuildMachineOSBuild</key><string>$(sw_vers -buildVersion)</string>
</dict>
</plist>
PLIST

if [[ "$MODE" != "appstore" ]]; then
    # Ad-hoc sign so macOS treats the bundle as a valid, launchable app.
    codesign --force --sign - "$APP" >/dev/null
    echo "Built $(pwd)/$APP"
    exit 0
fi

# The store requires the app id and team in the signature, matching the provisioning profile.
PROFILE_PLIST="$(mktemp)"
security cms -D -i "$PROFILE" > "$PROFILE_PLIST"
TEAM_ID="$(plutil -extract TeamIdentifier.0 raw "$PROFILE_PLIST")"
ENTITLEMENTS="$(mktemp).entitlements"
cp Resources/TimerApp.entitlements "$ENTITLEMENTS"
plutil -insert com\\.apple\\.application-identifier -string "$TEAM_ID.$BUNDLE_ID" "$ENTITLEMENTS"
plutil -insert com\\.apple\\.developer\\.team-identifier -string "$TEAM_ID" "$ENTITLEMENTS"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

identity() { security find-identity -v -p "$1" | grep -E "$2" | grep "$TEAM_ID" | head -1 | sed -E 's/.*"(.*)"/\1/'; }
APP_IDENTITY="${APP_IDENTITY:-$(identity codesigning '"(Apple Distribution|3rd Party Mac Developer Application):')}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-$(identity basic '"(3rd Party Mac Developer Installer|Mac Installer Distribution):')}"
[[ -n "$APP_IDENTITY" ]] || { echo "No Apple Distribution certificate for team $TEAM_ID in the keychain." >&2; exit 1; }
[[ -n "$INSTALLER_IDENTITY" ]] || { echo "No Mac Installer Distribution certificate for team $TEAM_ID in the keychain." >&2; exit 1; }

echo "Signing with $APP_IDENTITY..."
codesign --force --timestamp --sign "$APP_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict "$APP"

productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" TimerApp.pkg
echo "Built $(pwd)/TimerApp.pkg (version $VERSION, build $BUILD). Upload it with Transporter."
