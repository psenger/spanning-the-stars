// Usage: swift scripts/art-contact-sheet.swift <out-dir>
// Renders every SVG in Sources/SpanningTheStars/Resources/Art to <out-dir>/<name>.png at 2x,
// plus contact-sheet.png with a labeled grid.
import AppKit

let args = CommandLine.arguments
guard args.count == 2 else { FileHandle.standardError.write(Data("usage: art-contact-sheet.swift <out-dir>\n".utf8)); exit(2) }
let out = URL(fileURLWithPath: args[1], isDirectory: true)
let artDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/SpanningTheStars/Resources/Art")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

func render(_ img: NSImage, width: Int, height: Int, into ctxRect: NSRect? = nil) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let files = try FileManager.default.contentsOfDirectory(at: artDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "svg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

let cell = 200, pad = 12, labelH = 16, cols = 6
let rows = (files.count + cols - 1) / cols
let sheetW = cols * (cell + pad) + pad, sheetH = rows * (cell + labelH + pad) + pad
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sheetW, pixelsHigh: sheetH, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSColor(white: 0.45, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: sheetW, height: sheetH).fill()

for (i, f) in files.enumerated() {
    guard let img = NSImage(contentsOf: f) else { print("FAILED to load \(f.lastPathComponent)"); continue }
    let name = f.deletingPathExtension().lastPathComponent
    // Per-file PNG at 2x of the viewBox size.
    let w = Int(img.size.width * 2), h = Int(img.size.height * 2)
    try png(render(img, width: w, height: h)).write(to: out.appendingPathComponent("\(name).png"))
    // Fit into the grid cell, preserving aspect ratio.
    let col = i % cols, row = i / cols
    let scale = min(Double(cell) / img.size.width, Double(cell) / img.size.height)
    let dw = img.size.width * scale, dh = img.size.height * scale
    let x = Double(pad + col * (cell + pad)), y = Double(sheetH - pad - (row + 1) * (cell + labelH + pad) + labelH + pad)
        - 0 + (Double(cell) - dh) / 2 - Double(pad)
    img.draw(in: NSRect(x: x + (Double(cell) - dw) / 2, y: y, width: dw, height: dh))
    (name as NSString).draw(at: NSPoint(x: x, y: y - Double(labelH) - (Double(cell) - dh) / 2),
        withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white])
}
NSGraphicsContext.restoreGraphicsState()
try png(sheet).write(to: out.appendingPathComponent("contact-sheet.png"))
print("Rendered \(files.count) files to \(out.path)")
