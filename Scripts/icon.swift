import AppKit
// Render the downloaded Lucide SVG as the foreground of the macOS app icon.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let svg = try String(contentsOf: root.appendingPathComponent("Assets/memory-stick.svg"), encoding: .utf8)
let source = svg.replacingOccurrences(of: "currentColor", with: "#eeeeee")
guard let foreground = NSImage(data: Data(source.utf8)) else { fatalError("SVG decoding failed") }
let directory = root.appendingPathComponent(".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let side = CGFloat(pixels)
        NSColor(calibratedWhite: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: side * 0.06, y: side * 0.06, width: side * 0.88, height: side * 0.88), xRadius: side * 0.19, yRadius: side * 0.19).fill()
        foreground.draw(in: NSRect(x: side * 0.2, y: side * 0.2, width: side * 0.6, height: side * 0.6))
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
    }
}
