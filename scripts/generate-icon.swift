import AppKit

// Authored geometric app icon. No MSI logo or third-party art.
// Run from the repository root; build iconset stays outside source control.
let folder = URL(fileURLWithPath: "build/AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func icon(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.18, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864),
        xRadius: 190, yRadius: 190).fill()

    let screen = NSBezierPath(roundedRect: NSRect(x: 210, y: 365, width: 604, height: 398),
        xRadius: 46, yRadius: 46)
    NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.98, alpha: 1).setStroke()
    screen.lineWidth = 32
    screen.stroke()

    let stand = NSBezierPath()
    stand.move(to: NSPoint(x: 512, y: 350))
    stand.line(to: NSPoint(x: 512, y: 269))
    stand.move(to: NSPoint(x: 390, y: 260))
    stand.line(to: NSPoint(x: 634, y: 260))
    stand.lineWidth = 32
    stand.lineCapStyle = .round
    stand.stroke()

    NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.30, alpha: 1).setStroke()
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 512, y: 682))
    arrow.line(to: NSPoint(x: 512, y: 513))
    arrow.move(to: NSPoint(x: 437, y: 584))
    arrow.line(to: NSPoint(x: 512, y: 509))
    arrow.line(to: NSPoint(x: 587, y: 584))
    arrow.lineWidth = 36
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.stroke()
    NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 413, y: 445, width: 198, height: 22),
        xRadius: 11, yRadius: 11).fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try icon(size: points * scale).write(to: folder.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}

// README preview uses the same authored geometry as the packaged icon.
try icon(size: 256).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
