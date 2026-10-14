import AppKit

@main
enum IconOptionsPreview {
    static func main() throws {
        let outputURL = URL(fileURLWithPath: ".artifacts/icon-options/preview.png")
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let variants = PrimaryPasteIconVariant.allCases
        let columns = 5
        let cardWidth: CGFloat = 190
        let cardHeight: CGFloat = 154
        let margin: CGFloat = 28
        let titleHeight: CGFloat = 54
        let rows = Int(ceil(Double(variants.count) / Double(columns)))
        let imageSize = NSSize(
            width: margin * 2 + CGFloat(columns) * cardWidth,
            height: margin * 2 + titleHeight + CGFloat(rows) * cardHeight
        )

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(imageSize.width),
            pixelsHigh: Int(imageSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            fatalError("Could not create preview bitmap")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(origin: .zero, size: imageSize).fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.darkGray
        ]
        NSAttributedString(string: "Primary Paste runtime icon options", attributes: titleAttributes)
            .draw(at: NSPoint(x: margin, y: imageSize.height - margin - 28))
        NSAttributedString(string: "Rendered from PrimaryPasteIconRenderer.swift", attributes: subtitleAttributes)
            .draw(at: NSPoint(x: margin, y: imageSize.height - margin - 48))

        for (index, variant) in variants.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = margin + CGFloat(column) * cardWidth
            let y = margin + CGFloat(rows - row - 1) * cardHeight
            let cardRect = NSRect(x: x, y: y, width: cardWidth - 14, height: cardHeight - 14)

            NSColor.white.setFill()
            let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 12, yRadius: 12)
            cardPath.fill()

            NSColor(calibratedWhite: 0.84, alpha: 1).setStroke()
            cardPath.lineWidth = 1
            cardPath.stroke()

            let menuImage = PrimaryPasteIconRenderer.image(for: variant, size: 34, style: .markPreview)
            menuImage.draw(in: NSRect(x: cardRect.minX + 22, y: cardRect.minY + 70, width: 42, height: 42))

            let appImage = PrimaryPasteIconRenderer.image(for: variant, size: 64, style: .appIcon)
            appImage.draw(in: NSRect(x: cardRect.minX + 82, y: cardRect.minY + 58, width: 68, height: 68))

            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
            NSAttributedString(string: variant.title, attributes: labelAttributes)
                .draw(in: NSRect(x: cardRect.minX + 12, y: cardRect.minY + 24, width: cardRect.width - 24, height: 18))
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            fatalError("Could not create PNG data")
        }
        try data.write(to: outputURL)
        print(outputURL.path)
    }
}
