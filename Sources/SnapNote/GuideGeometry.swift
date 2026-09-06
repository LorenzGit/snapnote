import AppKit

enum GuideAxis: String, CaseIterable {
    case vertical = "Vertical", horizontal = "Horizontal"
}

/// Image coordinates are shared by the editor, hit testing, and export.
struct GuideGeometry {
    let mark: Mark
    let imageSize: CGSize
    let position: CGFloat
    var vertical: Bool { mark.guideAxis == .vertical }
    var length: CGFloat { vertical ? imageSize.width : imageSize.height }
    var percentage: CGFloat { 100 * position / length }
    var label: String { "\(Int(percentage.rounded()))%" }
    var start: CGPoint { vertical ? CGPoint(x: position, y: 0) : CGPoint(x: 0, y: position) }
    var end: CGPoint { vertical ? CGPoint(x: position, y: imageSize.height) : CGPoint(x: imageSize.width, y: position) }
    var labelFont: NSFont { .monospacedDigitSystemFont(ofSize: 14, weight: .semibold) }
    var naturalLabelSize: CGSize { (label as NSString).size(withAttributes: [.font: labelFont]) }
    var labelScale: CGFloat { min(1, imageSize.width / (naturalLabelSize.width + 12), imageSize.height / (naturalLabelSize.height + 12)) }
    var labelRect: CGRect {
        let size = CGSize(width: naturalLabelSize.width * labelScale, height: naturalLabelSize.height * labelScale)
        let margin = min(max(6, mark.width / 2 + 3), (imageSize.width - size.width) / 2, (imageSize.height - size.height) / 2)
        let desired = vertical ? CGPoint(x: position + margin, y: margin)
            : CGPoint(x: imageSize.width - size.width - margin, y: position + margin)
        return CGRect(x: min(max(margin, desired.x), imageSize.width - size.width - margin),
                      y: min(max(margin, desired.y), imageSize.height - size.height - margin),
                      width: size.width, height: size.height)
    }

    init?(_ mark: Mark, imageSize: CGSize) {
        guard mark.tool == .guide, let point = mark.points.first, imageSize.width > 0, imageSize.height > 0 else { return nil }
        self.mark = mark; self.imageSize = imageSize
        position = min(max(0, mark.guideAxis == .vertical ? point.x : point.y), mark.guideAxis == .vertical ? imageSize.width : imageSize.height)
    }

    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        if mark.showsPercentage && labelRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) { return true }
        return vertical ? abs(point.x-position) <= tolerance : abs(point.y-position) <= tolerance
    }

    static func positioned(_ mark: Mark, at point: CGPoint, imageSize: CGSize) -> Mark {
        var copy = mark
        copy.points = [CGPoint(x: min(max(0, point.x), imageSize.width), y: min(max(0, point.y), imageSize.height))]
        guard let guide = GuideGeometry(copy, imageSize: imageSize) else { return copy }
        copy.points = [guide.start, guide.end]
        return copy
    }
}
