import AppKit

// Draw at every target resolution so the app icon has native Retina variants.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 74, y: 74, width: 876, height: 876), xRadius: 192, yRadius: 192)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowBlurRadius = 24; shadow.set()
    NSColor(calibratedWhite: 0.12, alpha: 1).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedWhite: 0.25, alpha: 1), ending: NSColor(calibratedWhite: 0.08, alpha: 1))!.draw(in: tile, angle: -65)
    NSColor.white.withAlphaComponent(0.13).setStroke(); tile.lineWidth = 3; tile.stroke()

    // A paper sheet with a red margin echoes the editor's red list markers.
    let paper = NSBezierPath(roundedRect: NSRect(x: 260, y: 218, width: 514, height: 608), xRadius: 45, yRadius: 45)
    NSGraphicsContext.saveGraphicsState()
    let paperShadow = NSShadow(); paperShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    paperShadow.shadowOffset = NSSize(width: 0, height: -10); paperShadow.shadowBlurRadius = 18; paperShadow.set()
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill(); paper.fill()
    NSGraphicsContext.restoreGraphicsState()
    let margin = NSBezierPath(roundedRect: NSRect(x: 313, y: 282, width: 17, height: 480), xRadius: 8, yRadius: 8)
    NSColor(calibratedRed: 0.98, green: 0.23, blue: 0.28, alpha: 1).setFill(); margin.fill()
    for (y, width) in [(710.0, 295.0), (603, 295), (496, 295), (389, 205)] {
        NSColor(calibratedWhite: y == 710 ? 0.20 : 0.48, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 377, y: y, width: width, height: y == 710 ? 32 : 22), xRadius: 11, yRadius: 11).fill()
    }
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try drawIcon(size: points * scale).write(to: output.appendingPathComponent(name))
    }
}
