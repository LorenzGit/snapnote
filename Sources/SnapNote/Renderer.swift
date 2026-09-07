import AppKit

/// Both the editor and PNG export draw in image points, with a top-left origin.
enum Renderer {
    static func draw(_ mark: Mark, imageSize: CGSize? = nil) {
        guard let start = mark.points.first else { return }
        mark.color.setStroke()
        mark.color.setFill()
        let path = NSBezierPath()
        path.lineWidth = mark.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch mark.tool {
        case .pen:
            path.move(to: start)
            if mark.points.count == 1 {
                NSBezierPath(ovalIn: CGRect(x: start.x - mark.width/2, y: start.y - mark.width/2, width: mark.width, height: mark.width)).fill()
            }
            for p in mark.points.dropFirst() { path.line(to: p) }
            path.stroke()
        case .arrow:
            guard let arrow = ArrowGeometry(mark, imageSize: imageSize) else { return }
            arrow.shaft.stroke()
            arrow.head.fill()
            if !mark.text.isEmpty {
                if mark.textBackground { drawTextBackground(in: arrow.labelBounds) }
                NSGraphicsContext.saveGraphicsState()
                let context = NSGraphicsContext.current?.cgContext
                context?.translateBy(x: arrow.labelRect.minX, y: arrow.labelRect.minY)
                context?.scaleBy(x: arrow.labelScale, y: arrow.labelScale)
                (mark.text as NSString).draw(at: .zero, withAttributes: [
                    .font: arrow.labelFont, .foregroundColor: mark.color
                ])
                NSGraphicsContext.restoreGraphicsState()
            }
        case .rectangle, .ellipse:
            guard let end = mark.points.last else { return }
            let rect = CGRect(x: min(start.x,end.x), y: min(start.y,end.y), width: abs(end.x-start.x), height: abs(end.y-start.y))
            let outline = mark.tool == .ellipse ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
            outline.withWidth(mark.width).stroke()
        case .text:
            if mark.textBackground && !mark.text.isEmpty { drawTextBackground(in: mark.bounds) }
            (mark.text as NSString).draw(at: CGPoint(x: start.x + 6, y: start.y + 4), withAttributes: [
                .font: NSFont.systemFont(ofSize: mark.fontSize, weight: .semibold), .foregroundColor: mark.color
            ])
        case .guide:
            guard let imageSize, let guide = GuideGeometry(mark, imageSize: imageSize) else { return }
            path.move(to: guide.start); path.line(to: guide.end)
            path.setLineDash([0.01, max(4, mark.width * 2.5)], count: 2, phase: 0)
            path.stroke()
            if mark.showsPercentage, let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.translateBy(x: guide.labelRect.minX, y: guide.labelRect.minY)
                context.scaleBy(x: guide.labelScale, y: guide.labelScale)
                (guide.label as NSString).draw(at: .zero, withAttributes: [.font: guide.labelFont, .foregroundColor: mark.color])
                context.restoreGState()
            }
        case .select: break
        }
    }

    private static func drawTextBackground(in rect: CGRect) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
    }

    static func footerInset(width: CGFloat) -> CGFloat { min(20, width * 0.05) }

    static func footerHeight(blurb: String, width: CGFloat) -> CGFloat {
        guard !blurb.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        let rect = (blurb as NSString).boundingRect(with: CGSize(width: max(1, width - 2 * footerInset(width: width)), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: footerAttributes)
        return ceil(rect.height) + 40
    }

    static var footerAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 4
        return [.font: NSFont.systemFont(ofSize: 12.6), .foregroundColor: NSColor(calibratedWhite: 0.13, alpha: 1), .paragraphStyle: paragraph]
    }

    static func export(image: NSImage, marks: [Mark], blurb: String, scale: CGFloat) throws -> Data {
        // A footer adds height only; it must never pad or shift the screenshot.
        let width = image.size.width
        let footer = footerHeight(blurb: blurb, width: width)
        let size = CGSize(width: width, height: image.size.height + footer)
        let scale = max(1, scale)
        let pw = Int(ceil(size.width * scale)), ph = Int(ceil(size.height * scale))
        guard pw > 0, ph > 0, Double(pw) * Double(ph) <= 120_000_000,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ExportError.tooLarge
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let cg = graphics.cgContext
        cg.translateBy(x: 0, y: CGFloat(ph)); cg.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        NSColor.white.setFill(); CGRect(origin: .zero, size: size).fill()
        cg.saveGState()
        cg.clip(to: CGRect(origin: .zero, size: image.size))
        image.draw(in: CGRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        marks.forEach { draw($0, imageSize: image.size) }
        cg.restoreGState()
        if footer > 0 {
            NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
            CGRect(x: 0, y: image.size.height, width: width, height: footer).fill()
            NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
            CGRect(x: 0, y: image.size.height, width: width, height: 1).fill()
            let inset = footerInset(width: width)
            (blurb as NSString).draw(in: CGRect(x: inset, y: image.size.height + 20, width: max(1, width-2*inset), height: footer-40), withAttributes: footerAttributes)
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw ExportError.encoding }
        return data
    }

    static func crop(image: NSImage, marks: [Mark], rect: CGRect, scale: CGFloat) throws -> NSImage {
        let pw = ceil(rect.width*scale), ph = ceil(rect.height*scale)
        guard rect.minX.isFinite, rect.minY.isFinite, scale.isFinite, scale >= 1,
              pw.isFinite, ph.isFinite, pw > 0, ph > 0, pw*ph <= 120_000_000,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pw), pixelsHigh: Int(ph), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw ExportError.tooLarge }
        // Flatten against the current image bounds before cropping. Removed pixels
        // and off-image marks cannot reappear in a later extension.
        let data = try export(image: image, marks: marks, blurb: "", scale: scale)
        guard let source = NSImage(data: data) else { throw ExportError.encoding }
        source.size = image.size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let cg = graphics.cgContext
        cg.translateBy(x: 0, y: ph); cg.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        NSColor.black.setFill(); CGRect(origin: .zero, size: rect.size).fill()
        source.draw(in: CGRect(x: -rect.minX, y: -rect.minY, width: image.size.width, height: image.size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
        let result = NSImage(size: rect.size)
        bitmap.size = rect.size; result.addRepresentation(bitmap)
        return result
    }

    enum ExportError: LocalizedError {
        case tooLarge, encoding
        var errorDescription: String? { self == .tooLarge ? "This image is too large to export. Try a smaller capture or shorter note." : "The PNG could not be encoded." }
    }
}
private extension NSBezierPath {
    func withWidth(_ width: CGFloat) -> NSBezierPath { lineWidth = width; return self }
}
