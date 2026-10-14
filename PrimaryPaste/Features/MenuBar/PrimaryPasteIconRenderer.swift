import AppKit
import CoreGraphics

enum PrimaryPasteIconImageStyle {
    case menuBar
    case markPreview
    case appIcon
}

enum PrimaryPasteIconRenderer {
    static func image(
        for variant: PrimaryPasteIconVariant,
        size: CGFloat,
        style: PrimaryPasteIconImageStyle
    ) -> NSImage {
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 3)
        let pixelSize = max(1, Int(ceil(size * scale)))
        guard
            let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelSize,
                pixelsHigh: pixelSize,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else {
            return fallbackImage(for: variant, size: size, style: style)
        }

        representation.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)

        if let context = NSGraphicsContext.current?.cgContext {
            context.interpolationQuality = .high
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.saveGState()
            context.translateBy(x: 0, y: size)
            context.scaleBy(x: 1, y: -1)
            draw(variant, in: CGRect(x: 0, y: 0, width: size, height: size), style: style, context: context)
            context.restoreGState()
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(representation)
        image.isTemplate = style == .menuBar
        return image
    }

    private static func fallbackImage(
        for variant: PrimaryPasteIconVariant,
        size: CGFloat,
        style: PrimaryPasteIconImageStyle
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            context.interpolationQuality = .high
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.saveGState()
            context.translateBy(x: 0, y: size)
            context.scaleBy(x: 1, y: -1)
            draw(variant, in: CGRect(x: 0, y: 0, width: size, height: size), style: style, context: context)
            context.restoreGState()
        }

        image.unlockFocus()
        image.isTemplate = style == .menuBar
        return image
    }

    private static func draw(
        _ variant: PrimaryPasteIconVariant,
        in rect: CGRect,
        style: PrimaryPasteIconImageStyle,
        context: CGContext
    ) {
        let colors = Palette(style: style)
        let markRect: CGRect
        let usesTileBackground = style == .appIcon

        if usesTileBackground {
            drawAppIconBackground(in: rect, variant: variant, context: context)
            let inset: CGFloat
            if variant == .platformBridge {
                inset = rect.width * 0.045
            } else {
                inset = rect.width * 0.11
            }
            markRect = rect.insetBy(dx: inset, dy: inset)
        } else {
            let inset: CGFloat
            if variant == .platformBridge {
                inset = rect.width * 0.015
            } else {
                inset = rect.width * 0.08
            }
            markRect = rect.insetBy(dx: inset, dy: inset)
        }

        switch variant {
        case .focusFrame:
            drawFocusFrame(in: markRect, colors: colors, context: context)
        case .selectionSend:
            drawSelectionSend(in: markRect, colors: colors, context: context)
        case .lineProgress:
            drawLineProgress(in: markRect, colors: colors, context: context)
        case .pillCaret:
            drawPillCaret(in: markRect, colors: colors, context: context)
        case .cycleLines:
            drawCycleLines(in: markRect, colors: colors, context: context)
        case .pCaret:
            drawPCaret(in: markRect, colors: colors, context: context)
        case .dualLane:
            drawDualLane(in: markRect, colors: colors, context: context)
        case .returnLoop:
            drawReturnLoop(in: markRect, colors: colors, context: context)
        case .platformBridge:
            drawPlatformBridge(in: markRect, colors: colors, context: context)
        case .appPTile:
            drawAppPTileMark(in: markRect, colors: colors, context: context)
        case .handleP:
            drawHandleP(in: markRect, colors: colors, context: context)
        case .mergeSpark:
            drawMergeSpark(in: markRect, colors: colors, context: context)
        case .selectCursor:
            drawSelectCursor(in: markRect, colors: colors, context: context)
        case .mintSendTile:
            drawMintSendTile(in: markRect, colors: colors, context: context)
        case .dropIntoField:
            drawDropIntoField(in: markRect, colors: colors, context: context)
        }
    }

    private static func drawAppIconBackground(
        in rect: CGRect,
        variant: PrimaryPasteIconVariant,
        context: CGContext
    ) {
        let inset = rect.width * 0.055
        let backgroundRect = rect.insetBy(dx: inset, dy: inset)
        let corner = rect.width * 0.22
        let path = CGPath(roundedRect: backgroundRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

        context.saveGState()
        context.addPath(path)
        context.clip()

        let start: NSColor
        let end: NSColor
        switch variant {
        case .mintSendTile:
            start = NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.90, alpha: 1)
            end = NSColor(calibratedRed: 0.90, green: 0.98, blue: 0.94, alpha: 1)
        case .appPTile:
            start = NSColor(calibratedRed: 0.10, green: 0.64, blue: 1.00, alpha: 1)
            end = NSColor(calibratedRed: 0.08, green: 0.34, blue: 0.96, alpha: 1)
        default:
            start = NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.00, alpha: 1)
            end = NSColor(calibratedRed: 0.90, green: 0.94, blue: 1.00, alpha: 1)
        }

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [start.cgColor, end.cgColor] as CFArray,
            locations: [0, 1]
        )
        if let gradient {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: backgroundRect.minX, y: backgroundRect.minY),
                end: CGPoint(x: backgroundRect.maxX, y: backgroundRect.maxY),
                options: []
            )
        }
        context.restoreGState()
    }

    private static func drawFocusFrame(in rect: CGRect, colors: Palette, context: CGContext) {
        corner(x: 9, y: 13, horizontal: 20, vertical: 18, in: rect, color: colors.ink, context: context)
        corner(x: 9, y: 78, horizontal: 18, vertical: -18, in: rect, color: colors.ink, context: context)
        corner(x: 82, y: 78, horizontal: -18, vertical: -18, in: rect, color: colors.ink, context: context)
        drawCaret(x: 43, y: 27, height: 48, capWidth: 16, width: 7, color: colors.ink, in: rect, context: context)
        line(58, 32, 83, 32, width: 6, color: colors.ink, in: rect, context: context)
        line(58, 66, 79, 66, width: 6, color: colors.ink, in: rect, context: context)
        line(86, 32, 95, 32, width: 6, color: colors.ink, in: rect, context: context)
        line(84, 66, 94, 66, width: 6, color: colors.ink, in: rect, context: context)
    }

    private static func drawSelectionSend(in rect: CGRect, colors: Palette, context: CGContext) {
        dashedRoundedRect(
            x: 10, y: 17, width: 49, height: 59, corner: 8, lineWidth: 6, color: colors.accent, in: rect,
            context: context)
        roundedRect(x: 21, y: 28, width: 31, height: 7, corner: 3.5, color: colors.accent, in: rect, context: context)
        roundedRect(x: 21, y: 44, width: 23, height: 7, corner: 3.5, color: colors.accent, in: rect, context: context)
        roundedRect(x: 21, y: 60, width: 16, height: 7, corner: 3.5, color: colors.accent, in: rect, context: context)
        arrow(fromX: 59, fromY: 55, toX: 80, toY: 45, width: 6, color: colors.ink, in: rect, context: context)
        drawCaret(x: 88, y: 33, height: 39, capWidth: 12, width: 6, color: colors.ink, in: rect, context: context)
    }

    private static func drawLineProgress(in rect: CGRect, colors: Palette, context: CGContext) {
        line(14, 20, 62, 20, width: 8, color: colors.accent, in: rect, context: context)
        line(14, 34, 62, 34, width: 8, color: colors.accent, in: rect, context: context)
        line(14, 48, 62, 48, width: 8, color: colors.accent, in: rect, context: context)
        line(14, 62, 62, 62, width: 8, color: colors.accent, in: rect, context: context)
        line(14, 77, 42, 77, width: 8, color: colors.accent, in: rect, context: context)
        line(14, 91, 24, 91, width: 8, color: colors.accent, in: rect, context: context)
        circle(x: 35, y: 91, radius: 4, color: colors.accent, in: rect, context: context)
        arc(
            cx: 72, cy: 45, radius: 20, start: -70, end: 116, width: 8, color: colors.secondary, dash: [8, 7], in: rect,
            context: context)
    }

    private static func drawPillCaret(in rect: CGRect, colors: Palette, context: CGContext) {
        bracket(x: 13, y: 26, height: 35, side: .left, color: colors.ink, in: rect, context: context)
        bracket(x: 76, y: 26, height: 35, side: .right, color: colors.ink, in: rect, context: context)
        roundedRect(x: 26, y: 35, width: 45, height: 18, corner: 9, color: colors.accent, in: rect, context: context)
        circle(x: 32, y: 44, radius: 5, color: colors.knockout, in: rect, context: context)
        drawCaret(x: 91, y: 27, height: 37, capWidth: 12, width: 6, color: colors.ink, in: rect, context: context)
    }

    private static func drawCycleLines(in rect: CGRect, colors: Palette, context: CGContext) {
        line(14, 26, 52, 26, width: 8, color: colors.accent, in: rect, context: context)
        line(14, 43, 52, 43, width: 8, color: colors.green, in: rect, context: context)
        line(14, 60, 43, 60, width: 8, color: colors.secondary, in: rect, context: context)
        arc(
            cx: 66, cy: 47, radius: 29, start: -91, end: 95, width: 7, color: colors.ink, dash: nil, in: rect,
            context: context)
        arrowHead(
            atX: 51, atY: 71, angleDegrees: 145, size: 14, width: 7, color: colors.ink, in: rect, context: context)
    }

    private static func drawPCaret(in rect: CGRect, colors: Palette, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(colors.ink)
        context.setLineWidth(rect.width * 0.145)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: point(24, 84, in: rect))
        context.addLine(to: point(24, 18, in: rect))
        context.addLine(to: point(52, 18, in: rect))
        context.addCurve(
            to: point(75, 42, in: rect),
            control1: point(67, 18, in: rect),
            control2: point(75, 27, in: rect)
        )
        context.addCurve(
            to: point(46, 66, in: rect),
            control1: point(75, 57, in: rect),
            control2: point(63, 66, in: rect)
        )
        context.strokePath()
        context.restoreGState()

        drawCaret(x: 44, y: 38, height: 39, capWidth: 15, width: 6.2, color: colors.accent, in: rect, context: context)
    }

    private static func drawDualLane(in rect: CGRect, colors: Palette, context: CGContext) {
        ring(x: 15, y: 30, radius: 9, width: 6, color: colors.accent, in: rect, context: context)
        ring(x: 15, y: 70, radius: 9, width: 6, color: colors.secondary, in: rect, context: context)
        polyline([(24, 30), (52, 30), (65, 45), (78, 50)], width: 7, color: colors.accent, in: rect, context: context)
        polyline(
            [(24, 70), (52, 70), (65, 55), (78, 50)], width: 7, color: colors.secondary, in: rect, context: context)
        arrow(fromX: 69, fromY: 50, toX: 84, toY: 50, width: 7, color: colors.ink, in: rect, context: context)
        drawCaret(x: 93, y: 37, height: 31, capWidth: 11, width: 6, color: colors.ink, in: rect, context: context)
    }

    private static func drawReturnLoop(in rect: CGRect, colors: Palette, context: CGContext) {
        line(26, 37, 60, 37, width: 8, color: colors.violet, in: rect, context: context)
        line(26, 51, 60, 51, width: 8, color: colors.accent, in: rect, context: context)
        line(26, 65, 55, 65, width: 8, color: colors.lightGray, in: rect, context: context)
        arc(
            cx: 61, cy: 52, radius: 34, start: -132, end: 152, width: 7, color: colors.ink, dash: nil, in: rect,
            context: context)
        arrowHead(
            atX: 31, atY: 24, angleDegrees: 215, size: 14, width: 7, color: colors.ink, in: rect, context: context)
    }

    private static func drawPlatformBridge(in rect: CGRect, colors: Palette, context: CGContext) {
        // Original window outlines and transfer arrow; no platform mascots or logos.
        roundedRectStroke(
            x: 8, y: 22, width: 30, height: 58, corner: 6, lineWidth: 5,
            color: colors.ink, in: rect, context: context)
        roundedRectStroke(
            x: 62, y: 22, width: 30, height: 58, corner: 6, lineWidth: 5,
            color: colors.ink, in: rect, context: context)
        line(9, 40, 37, 40, width: 4, color: colors.ink, in: rect, context: context)
        line(63, 40, 91, 40, width: 4, color: colors.ink, in: rect, context: context)
        line(17, 52, 30, 52, width: 5, color: colors.accent, in: rect, context: context)
        line(17, 63, 29, 63, width: 4, color: colors.lightGray, in: rect, context: context)
        arrow(
            fromX: 44, fromY: 55, toX: 56, toY: 55, width: 5,
            color: colors.accent, in: rect, context: context)
        drawCaret(
            x: 76, y: 49, height: 17, capWidth: 7, width: 4,
            color: colors.ink, in: rect, context: context)
    }

    private static func drawAppPTileMark(in rect: CGRect, colors: Palette, context: CGContext) {
        let markColor = colors.onAppIcon
        polyline(
            [(29, 80), (29, 26), (54, 26), (69, 33), (73, 47), (68, 61), (56, 68), (45, 68)],
            width: 13,
            color: markColor,
            in: rect,
            context: context
        )
        drawCaret(
            x: 48, y: 43, height: 30, capWidth: 11, width: 5.5, color: colors.appIconAccent, in: rect, context: context)
    }

    private static func drawHandleP(in rect: CGRect, colors: Palette, context: CGContext) {
        dashedP(in: rect, color: colors.ink, context: context)
        drawCaret(x: 46, y: 31, height: 49, capWidth: 13, width: 6, color: colors.violet, in: rect, context: context)
        roundedRect(x: 15, y: 17, width: 12, height: 12, corner: 4, color: colors.violet, in: rect, context: context)
        roundedRect(x: 68, y: 17, width: 12, height: 12, corner: 4, color: colors.violet, in: rect, context: context)
        roundedRect(x: 68, y: 68, width: 12, height: 12, corner: 4, color: colors.violet, in: rect, context: context)
        roundedRect(x: 15, y: 82, width: 12, height: 12, corner: 4, color: colors.violet, in: rect, context: context)
    }

    private static func drawMergeSpark(in rect: CGRect, colors: Palette, context: CGContext) {
        ring(x: 17, y: 30, radius: 10, width: 6, color: colors.accent, in: rect, context: context)
        ring(x: 17, y: 70, radius: 10, width: 6, color: colors.secondary, in: rect, context: context)
        polyline([(30, 30), (58, 30), (72, 50)], width: 7, color: colors.ink, in: rect, context: context)
        polyline([(30, 70), (58, 70), (72, 50)], width: 7, color: colors.ink, in: rect, context: context)
        arrow(fromX: 68, fromY: 50, toX: 82, toY: 50, width: 7, color: colors.ink, in: rect, context: context)
        drawCaret(x: 90, y: 39, height: 28, capWidth: 10, width: 5.5, color: colors.ink, in: rect, context: context)
        line(95, 31, 95, 23, width: 4, color: colors.accent, in: rect, context: context)
        line(101, 36, 108, 29, width: 4, color: colors.accent, in: rect, context: context)
        line(101, 47, 110, 47, width: 4, color: colors.accent, in: rect, context: context)
    }

    private static func drawSelectCursor(in rect: CGRect, colors: Palette, context: CGContext) {
        dashedRoundedRect(
            x: 18, y: 15, width: 56, height: 67, corner: 5, lineWidth: 6, color: colors.ink, in: rect, context: context)
        line(30, 34, 63, 34, width: 7, color: colors.lightGray, in: rect, context: context)
        line(30, 49, 66, 49, width: 8, color: colors.accent, in: rect, context: context)
        line(30, 64, 51, 64, width: 7, color: colors.lightGray, in: rect, context: context)
        cursor(x: 68, y: 62, size: 25, color: colors.ink, in: rect, context: context)
    }

    private static func drawMintSendTile(in rect: CGRect, colors: Palette, context: CGContext) {
        roundedRect(x: 18, y: 24, width: 41, height: 45, corner: 6, color: colors.mintWash, in: rect, context: context)
        dashedRoundedRect(
            x: 18, y: 24, width: 41, height: 45, corner: 6, lineWidth: 5, color: colors.ink, in: rect, context: context)
        line(28, 35, 49, 35, width: 5, color: colors.green, in: rect, context: context)
        line(28, 48, 44, 48, width: 5, color: colors.green, in: rect, context: context)
        line(28, 61, 39, 61, width: 5, color: colors.green, in: rect, context: context)
        arrow(fromX: 55, fromY: 66, toX: 80, toY: 51, width: 6, color: colors.ink, in: rect, context: context)
        drawCaret(x: 89, y: 37, height: 36, capWidth: 12, width: 6, color: colors.ink, in: rect, context: context)
    }

    private static func drawDropIntoField(in rect: CGRect, colors: Palette, context: CGContext) {
        line(38, 18, 62, 18, width: 6, color: colors.green, in: rect, context: context)
        line(38, 30, 62, 30, width: 6, color: colors.green, in: rect, context: context)
        arrow(fromX: 50, fromY: 43, toX: 50, toY: 61, width: 6, color: colors.green, in: rect, context: context)
        roundedRectStroke(
            x: 14, y: 58, width: 72, height: 27, corner: 7, lineWidth: 5, color: colors.ink, in: rect, context: context)
        drawCaret(x: 72, y: 65, height: 16, capWidth: 8, width: 4.5, color: colors.ink, in: rect, context: context)
    }

    private static func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x / 100, y: rect.minY + rect.height * y / 100)
    }

    private static func line(
        _ x1: CGFloat,
        _ y1: CGFloat,
        _ x2: CGFloat,
        _ y2: CGFloat,
        width: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext,
        dash: [CGFloat]? = nil
    ) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(rect.width * width / 100)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if let dash {
            context.setLineDash(phase: 0, lengths: dash.map { rect.width * $0 / 100 })
        }
        context.move(to: point(x1, y1, in: rect))
        context.addLine(to: point(x2, y2, in: rect))
        context.strokePath()
        context.restoreGState()
    }

    private static func polyline(
        _ points: [(CGFloat, CGFloat)],
        width: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext,
        dash: [CGFloat]? = nil
    ) {
        guard let first = points.first else { return }
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(rect.width * width / 100)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if let dash {
            context.setLineDash(phase: 0, lengths: dash.map { rect.width * $0 / 100 })
        }
        context.move(to: point(first.0, first.1, in: rect))
        points.dropFirst().forEach { context.addLine(to: point($0.0, $0.1, in: rect)) }
        context.strokePath()
        context.restoreGState()
    }

    private static func roundedRect(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        corner: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext
    ) {
        let target = CGRect(
            x: rect.minX + rect.width * x / 100,
            y: rect.minY + rect.height * y / 100,
            width: rect.width * width / 100,
            height: rect.height * height / 100
        )
        let path = CGPath(
            roundedRect: target,
            cornerWidth: rect.width * corner / 100,
            cornerHeight: rect.width * corner / 100,
            transform: nil
        )
        context.saveGState()
        context.setFillColor(color)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }

    private static func roundedRectStroke(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        corner: CGFloat,
        lineWidth: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext
    ) {
        let target = CGRect(
            x: rect.minX + rect.width * x / 100,
            y: rect.minY + rect.height * y / 100,
            width: rect.width * width / 100,
            height: rect.height * height / 100
        )
        let path = CGPath(
            roundedRect: target,
            cornerWidth: rect.width * corner / 100,
            cornerHeight: rect.width * corner / 100,
            transform: nil
        )
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(rect.width * lineWidth / 100)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func dashedRoundedRect(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        corner: CGFloat,
        lineWidth: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext
    ) {
        let target = CGRect(
            x: rect.minX + rect.width * x / 100,
            y: rect.minY + rect.height * y / 100,
            width: rect.width * width / 100,
            height: rect.height * height / 100
        )
        let path = CGPath(
            roundedRect: target,
            cornerWidth: rect.width * corner / 100,
            cornerHeight: rect.width * corner / 100,
            transform: nil
        )
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(rect.width * lineWidth / 100)
        context.setLineCap(.round)
        context.setLineDash(phase: 0, lengths: [rect.width * 0.08, rect.width * 0.06])
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawCaret(
        x: CGFloat,
        y: CGFloat,
        height: CGFloat,
        capWidth: CGFloat,
        width: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext
    ) {
        line(x, y, x, y + height, width: width, color: color, in: rect, context: context)
        line(x - capWidth / 2, y, x + capWidth / 2, y, width: width, color: color, in: rect, context: context)
        line(
            x - capWidth / 2, y + height, x + capWidth / 2, y + height, width: width, color: color, in: rect,
            context: context)
    }

    private static func corner(
        x: CGFloat,
        y: CGFloat,
        horizontal: CGFloat,
        vertical: CGFloat,
        in rect: CGRect,
        color: CGColor,
        context: CGContext
    ) {
        line(x, y, x + horizontal, y, width: 6, color: color, in: rect, context: context)
        line(x, y, x, y + vertical, width: 6, color: color, in: rect, context: context)
    }

    private enum BracketSide {
        case left
        case right
    }

    private static func bracket(
        x: CGFloat,
        y: CGFloat,
        height: CGFloat,
        side: BracketSide,
        color: CGColor,
        in rect: CGRect,
        context: CGContext
    ) {
        let horizontal: CGFloat = side == .left ? 8 : -8
        line(x, y, x + horizontal, y, width: 5, color: color, in: rect, context: context)
        line(x, y, x, y + height, width: 5, color: color, in: rect, context: context)
        line(x, y + height, x + horizontal, y + height, width: 5, color: color, in: rect, context: context)
    }

    private static func circle(
        x: CGFloat,
        y: CGFloat,
        radius: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext
    ) {
        let center = point(x, y, in: rect)
        let r = rect.width * radius / 100
        context.saveGState()
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        context.restoreGState()
    }

    private static func ring(
        x: CGFloat,
        y: CGFloat,
        radius: CGFloat,
        width: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext
    ) {
        let center = point(x, y, in: rect)
        let r = rect.width * radius / 100
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(rect.width * width / 100)
        context.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        context.restoreGState()
    }

    private static func arc(
        cx: CGFloat,
        cy: CGFloat,
        radius: CGFloat,
        start: CGFloat,
        end: CGFloat,
        width: CGFloat,
        color: CGColor,
        dash: [CGFloat]?,
        in rect: CGRect,
        context: CGContext
    ) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(rect.width * width / 100)
        context.setLineCap(.round)
        if let dash {
            context.setLineDash(phase: 0, lengths: dash.map { rect.width * $0 / 100 })
        }
        let center = point(cx, cy, in: rect)
        context.addArc(
            center: center,
            radius: rect.width * radius / 100,
            startAngle: start * .pi / 180,
            endAngle: end * .pi / 180,
            clockwise: false
        )
        context.strokePath()
        context.restoreGState()
    }

    private static func arrow(
        fromX: CGFloat,
        fromY: CGFloat,
        toX: CGFloat,
        toY: CGFloat,
        width: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext
    ) {
        line(fromX, fromY, toX, toY, width: width, color: color, in: rect, context: context)
        let angle = atan2(toY - fromY, toX - fromX) * 180 / .pi
        arrowHead(
            atX: toX, atY: toY, angleDegrees: angle, size: width * 2.2, width: width, color: color, in: rect,
            context: context)
    }

    private static func arrowHead(
        atX x: CGFloat,
        atY y: CGFloat,
        angleDegrees: CGFloat,
        size: CGFloat,
        width: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext
    ) {
        let angle = angleDegrees * .pi / 180
        let left = angle + 145 * .pi / 180
        let right = angle - 145 * .pi / 180
        let p = point(x, y, in: rect)
        let length = rect.width * size / 100
        let leftPoint = CGPoint(x: p.x + cos(left) * length, y: p.y + sin(left) * length)
        let rightPoint = CGPoint(x: p.x + cos(right) * length, y: p.y + sin(right) * length)

        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(rect.width * width / 100)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: leftPoint)
        context.addLine(to: p)
        context.addLine(to: rightPoint)
        context.strokePath()
        context.restoreGState()
    }

    private static func cursor(
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext
    ) {
        let p = point(x, y, in: rect)
        let s = rect.width * size / 100
        context.saveGState()
        context.setFillColor(color)
        context.beginPath()
        context.move(to: p)
        context.addLine(to: CGPoint(x: p.x + s * 0.66, y: p.y + s * 0.50))
        context.addLine(to: CGPoint(x: p.x + s * 0.34, y: p.y + s * 0.58))
        context.addLine(to: CGPoint(x: p.x + s * 0.47, y: p.y + s))
        context.addLine(to: CGPoint(x: p.x + s * 0.28, y: p.y + s * 1.06))
        context.addLine(to: CGPoint(x: p.x + s * 0.12, y: p.y + s * 0.64))
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    private static func blob(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext
    ) {
        let origin = point(x, y, in: rect)
        let w = rect.width * width / 100
        let h = rect.height * height / 100
        context.saveGState()
        context.setFillColor(color)
        context.beginPath()
        context.move(to: CGPoint(x: origin.x + w * 0.22, y: origin.y + h))
        context.addCurve(
            to: CGPoint(x: origin.x + w * 0.72, y: origin.y + h * 0.08),
            control1: CGPoint(x: origin.x + w * 0.05, y: origin.y + h * 0.72),
            control2: CGPoint(x: origin.x + w * 0.22, y: origin.y + h * 0.18)
        )
        context.addCurve(
            to: CGPoint(x: origin.x + w, y: origin.y + h * 0.65),
            control1: CGPoint(x: origin.x + w * 0.98, y: origin.y + h * 0.02),
            control2: CGPoint(x: origin.x + w * 1.08, y: origin.y + h * 0.42)
        )
        context.addCurve(
            to: CGPoint(x: origin.x + w * 0.22, y: origin.y + h),
            control1: CGPoint(x: origin.x + w * 0.82, y: origin.y + h),
            control2: CGPoint(x: origin.x + w * 0.48, y: origin.y + h * 1.03)
        )
        context.fillPath()
        context.restoreGState()
    }

    private static func dashedP(in rect: CGRect, color: CGColor, context: CGContext) {
        polyline(
            [(24, 86), (24, 18), (58, 18), (74, 27), (78, 44), (71, 60), (56, 68), (39, 68)],
            width: 5,
            color: color,
            in: rect,
            context: context,
            dash: [7, 7]
        )
    }

    private struct Palette {
        let ink: CGColor
        let accent: CGColor
        let secondary: CGColor
        let green: CGColor
        let violet: CGColor
        let lightGray: CGColor
        let mintWash: CGColor
        let knockout: CGColor
        let onAppIcon: CGColor
        let appIconAccent: CGColor

        init(style: PrimaryPasteIconImageStyle) {
            let monochrome = style == .menuBar
            ink = Self.color(0.08, 0.09, 0.10)
            accent = monochrome ? ink : Self.color(0.08, 0.43, 1.00)
            secondary = monochrome ? ink : Self.color(0.43, 0.46, 0.50)
            green = monochrome ? ink : Self.color(0.06, 0.80, 0.46)
            violet = monochrome ? ink : Self.color(0.50, 0.31, 0.96)
            lightGray = monochrome ? ink : Self.color(0.70, 0.72, 0.76)
            mintWash = monochrome ? Self.color(0, 0, 0, alpha: 0) : Self.color(0.70, 0.96, 0.83)
            knockout = Self.color(1, 1, 1)
            onAppIcon = style == .appIcon ? Self.color(1, 1, 1) : ink
            appIconAccent = style == .appIcon ? Self.color(1, 1, 1) : accent
        }

        private static func color(
            _ red: CGFloat,
            _ green: CGFloat,
            _ blue: CGFloat,
            alpha: CGFloat = 1
        ) -> CGColor {
            NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha).cgColor
        }
    }
}
