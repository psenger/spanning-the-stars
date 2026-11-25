#!/bin/bash
# Renders Sources/SpanningTheStars/Resources/AppIcon.svg with NSImage (the same SVG renderer as the game) into
# build/AppIcon.iconset and builds build/AppIcon.icns with iconutil. With --readme it also refreshes the
# tracked README icon files in docs/images (icon.svg, icon-256.png, icon-512.png). Run from anywhere;
# safe to re-run.
set -euo pipefail
README=false
[[ "${1:-}" == "--readme" ]] && README=true
cd "$(dirname "$0")/.."

SVG="Sources/SpanningTheStars/Resources/AppIcon.svg"
ICONSET="build/AppIcon.iconset"
ICNS="build/AppIcon.icns"
RENDER="build/render-icon.swift"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

cat > "$RENDER" <<'SWIFT'
// Usage: swift render-icon.swift <svg> <out.png>:<pixels> ...
import AppKit
let args = CommandLine.arguments
guard args.count >= 3, let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write(Data("render-icon: cannot load \(args.dropFirst().first ?? "")\n".utf8)); exit(1)
}
for spec in args[2...] {
    let parts = spec.split(separator: ":")
    let path = String(parts[0]), px = Int(parts[1])!
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
SWIFT

swift "$RENDER" "$SVG" \
    "$ICONSET/icon_16x16.png:16"      "$ICONSET/icon_16x16@2x.png:32" \
    "$ICONSET/icon_32x32.png:32"      "$ICONSET/icon_32x32@2x.png:64" \
    "$ICONSET/icon_128x128.png:128"   "$ICONSET/icon_128x128@2x.png:256" \
    "$ICONSET/icon_256x256.png:256"   "$ICONSET/icon_256x256@2x.png:512" \
    "$ICONSET/icon_512x512.png:512"   "$ICONSET/icon_512x512@2x.png:1024"

iconutil -c icns "$ICONSET" -o "$ICNS"

if $README; then
    mkdir -p docs/images
    cp "$SVG" docs/images/icon.svg
    cp "$ICONSET/icon_256x256.png" docs/images/icon-256.png
    cp "$ICONSET/icon_512x512.png" docs/images/icon-512.png
fi

for f in "$ICONSET"/*.png; do
    printf '%-28s %s px\n' "$(basename "$f")" "$(sips -g pixelWidth "$f" | awk '/pixelWidth/ {print $2}')"
done
if $README; then
    echo "Wrote $ICNS, docs/images/icon.svg, docs/images/icon-256.png, docs/images/icon-512.png"
else
    echo "Wrote $ICNS (run with --readme to refresh docs/images)"
fi
