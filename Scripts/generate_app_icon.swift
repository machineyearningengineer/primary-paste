import AppKit

let outputDirectory = URL(fileURLWithPath: "PrimaryPaste/Assets.xcassets/AppIcon.appiconset")
let sizes = [16, 32, 64, 128, 256, 512, 1024]

func drawIcon(size: Int) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create \(size)px bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = CGFloat(size) * 0.22
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(size) * 0.06, dy: CGFloat(size) * 0.06), xRadius: radius, yRadius: radius)

    NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.16, alpha: 1).setFill()
    path.fill()

    let accentRect = rect.insetBy(dx: CGFloat(size) * 0.21, dy: CGFloat(size) * 0.21)
    let accentPath = NSBezierPath(roundedRect: accentRect, xRadius: CGFloat(size) * 0.14, yRadius: CGFloat(size) * 0.14)
    NSColor(calibratedRed: 0.24, green: 0.56, blue: 0.42, alpha: 1).setFill()
    accentPath.fill()

    let text = "P"
    let font = NSFont.systemFont(ofSize: CGFloat(size) * 0.48, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributed.size()
    attributed.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

for size in sizes {
    let bitmap = drawIcon(size: size)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not generate \(size)px icon")
    }

    let url = outputDirectory.appendingPathComponent("icon_\(size).png")
    try data.write(to: url)
}
