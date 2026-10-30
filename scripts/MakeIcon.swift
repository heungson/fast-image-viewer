import AppKit

let directory = CommandLine.arguments[1] + "/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 58, y: 58, width: 908, height: 908), xRadius: 210, yRadius: 210)
        NSGradient(starting: NSColor(srgbRed: 0.23, green: 0.20, blue: 0.37, alpha: 1),
                   ending: NSColor(srgbRed: 0.10, green: 0.12, blue: 0.18, alpha: 1))!.draw(in: background, angle: -80)
        NSColor(srgbRed: 0.69, green: 0.63, blue: 1, alpha: 1).setStroke()
        let frame = NSBezierPath(roundedRect: NSRect(x: 245, y: 280, width: 540, height: 440), xRadius: 64, yRadius: 64)
        frame.lineWidth = 36; frame.stroke()
        let mountain = NSBezierPath()
        mountain.move(to: NSPoint(x: 265, y: 330)); mountain.line(to: NSPoint(x: 433, y: 518))
        mountain.line(to: NSPoint(x: 540, y: 410)); mountain.line(to: NSPoint(x: 621, y: 481))
        mountain.line(to: NSPoint(x: 764, y: 330)); mountain.close()
        NSColor(srgbRed: 0.69, green: 0.63, blue: 1, alpha: 1).setFill(); mountain.fill()
        NSBezierPath(ovalIn: NSRect(x: 613, y: 567, width: 70, height: 70)).fill()
        NSColor(srgbRed: 0.90, green: 0.87, blue: 1, alpha: 1).setFill()
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: 254, y: 795)); bolt.line(to: NSPoint(x: 169, y: 638))
        bolt.line(to: NSPoint(x: 241, y: 638)); bolt.line(to: NSPoint(x: 211, y: 536))
        bolt.line(to: NSPoint(x: 341, y: 700)); bolt.line(to: NSPoint(x: 264, y: 700)); bolt.close(); bolt.fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/icon_\(size)x\(size)\(suffix).png"))
    }
}
