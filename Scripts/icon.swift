import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let directory = root.appendingPathComponent(".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let side = CGFloat(pixels)
        let face = NSBezierPath(roundedRect: NSRect(x: side * 0.06, y: side * 0.06, width: side * 0.88, height: side * 0.88), xRadius: side * 0.20, yRadius: side * 0.20)
        NSGradient(starting: NSColor(calibratedWhite: 0.25, alpha: 1), ending: NSColor(calibratedWhite: 0.10, alpha: 1))!.draw(in: face, angle: -90)
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
        face.lineWidth = max(0.5, side * 0.002); face.stroke()
        let center = NSPoint(x: side * 0.5, y: side * 0.48)
        let track = NSBezierPath()
        track.lineWidth = side * 0.065; track.lineCapStyle = .round
        track.appendArc(withCenter: center, radius: side * 0.255, startAngle: 225, endAngle: -45, clockwise: true)
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke(); track.stroke()
        let progress = NSBezierPath()
        progress.lineWidth = side * 0.065; progress.lineCapStyle = .round
        progress.appendArc(withCenter: center, radius: side * 0.255, startAngle: 225, endAngle: 55, clockwise: true)
        NSColor(calibratedWhite: 0.91, alpha: 1).setStroke(); progress.stroke()
        let needle = NSBezierPath()
        needle.lineWidth = side * 0.038; needle.lineCapStyle = .round
        needle.move(to: center); needle.line(to: NSPoint(x: side * 0.60, y: side * 0.63)); needle.stroke()
        NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - side * 0.037, y: center.y - side * 0.037, width: side * 0.074, height: side * 0.074)).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        precondition(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
    }
}
