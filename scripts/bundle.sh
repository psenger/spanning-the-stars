#!/bin/bash
# Builds a release binary and assembles "build/Spanning the Stars.app" (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/make-icon.sh
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Spanning the Stars.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SpanningTheStars" "$APP/Contents/MacOS/SpanningTheStars"
for b in "$BIN_DIR"/*.bundle; do
    cp -R "$b" "$APP/Contents/Resources/"
done
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Spanning the Stars</string>
    <key>CFBundleDisplayName</key><string>Spanning the Stars</string>
    <key>CFBundleIdentifier</key><string>local.spanningthestars</string>
    <key>CFBundleExecutable</key><string>SpanningTheStars</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign -s - --force --deep "$APP"
echo "Built $APP"
