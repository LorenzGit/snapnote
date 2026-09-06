import AppKit

/// Shared geometry keeps drawing, selection, and exported arrows in agreement.
struct ArrowGeometry {
    let start: CGPoint
    let end: CGPoint
    let control: CGPoint
    let shaft: NSBezierPath
    let head: NSBezierPath
    let shaftWidth: CGFloat
    let labelRect: CGRect
    let labelFont: NSFont
    let labelBounds: CGRect
    let labelScale: CGFloat
    let labelAngle: CGFloat

    init?(_ mark: Mark, imageSize: CGSize? = nil) {
        guard mark.tool == .arrow, let start = mark.points.first, let end = mark.points.last else { return nil }
        let dx = end.x-start.x, dy = end.y-start.y, length = hypot(dx, dy)
        guard length > 2 else { return nil }
        self.start = start; self.end = end
        let bend = min(0.75, max(-0.75, mark.bend))
        let control = CGPoint(x: (start.x+end.x)/2 - dy*2*bend, y: (start.y+end.y)/2 + dx*2*bend)
        self.control = control
        func point(_ t: CGFloat) -> CGPoint {
            let u = 1-t
            return CGPoint(x: u*u*start.x + 2*u*t*control.x + t*t*end.x,
                           y: u*u*start.y + 2*u*t*control.y + t*t*end.y)
        }
        let headLength = min(max(14, mark.width*4), length*0.5)
        let depth = headLength*cos(0.48)
        // Trim the curve beneath the head instead of stroking through the pointed tip.
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<24 {
            let t = (low+high)/2, p = point(t)
            if hypot(end.x-p.x, end.y-p.y) > depth { low = t } else { high = t }
        }
        let t = (low+high)/2, base = point(t)
        let trimmedControl = CGPoint(x: start.x+t*(control.x-start.x), y: start.y+t*(control.y-start.y))
        shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.curve(to: base,
                    controlPoint1: CGPoint(x: start.x+(trimmedControl.x-start.x)*2/3, y: start.y+(trimmedControl.y-start.y)*2/3),
                    controlPoint2: CGPoint(x: base.x+(trimmedControl.x-base.x)*2/3, y: base.y+(trimmedControl.y-base.y)*2/3))
        shaftWidth = min(mark.width, headLength*sin(0.48))
        shaft.lineWidth = shaftWidth; shaft.lineCapStyle = .round
        let angle = atan2(end.y-base.y, end.x-base.x)
        head = NSBezierPath()
        head.move(to: end)
        head.line(to: CGPoint(x: end.x-headLength*cos(angle-0.48), y: end.y-headLength*sin(angle-0.48)))
        head.line(to: CGPoint(x: end.x-headLength*cos(angle+0.48), y: end.y-headLength*sin(angle+0.48)))
        head.close()
        labelFont = .systemFont(ofSize: mark.fontSize, weight: .semibold)
        if mark.text.isEmpty { labelRect = .null; labelBounds = .null; labelScale = 1; labelAngle = 0; return }
        let size = (mark.text as NSString).size(withAttributes: [.font: labelFont])
        let padding = mark.textBackground ? CGSize(width: 12, height: 8) : .zero
        let natural = CGSize(width: size.width + padding.width, height: size.height + padding.height)
        let scale = imageSize.map { min(1, $0.width / max(1, natural.width + 8), $0.height / max(1, natural.height + 8)) } ?? 1
        labelScale = scale
        let box = CGSize(width: natural.width * scale, height: natural.height * scale)
        if let offset = mark.arrowLabelOffset {
            labelAngle = 0
            var origin = CGPoint(x: start.x+offset.x, y: start.y+offset.y)
            if let imageSize {
                let margin = 4 * scale
                origin.x = min(max(margin, origin.x), imageSize.width-box.width-margin)
                origin.y = min(max(margin, origin.y), imageSize.height-box.height-margin)
            }
            labelBounds = CGRect(origin: origin, size: box)
            labelRect = labelBounds.insetBy(dx: padding.width*scale/2, dy: padding.height*scale/2)
            return
        }
        // Follow the tail tangent, including on curved arrows. Try nearby sides if
        // the image edge would push the label back onto the shaft.
        let tailAngle = atan2(start.y-control.y, start.x-control.x)
        let gap = max(10, shaftWidth / 2 + 6)
        var best = CGRect.zero
        var bestScore = CGFloat.greatestFiniteMagnitude
        var bestAngle: CGFloat = 0
        for i in 0..<(mark.arrowLabelAngle == nil ? 16 : 1) {
            let offset = mark.arrowLabelAngle ?? (CGFloat((i + 1) / 2) * .pi / 8 * (i.isMultiple(of: 2) ? 1 : -1))
            let vx = cos(tailAngle + offset), vy = sin(tailAngle + offset)
            let distance = min(box.width / 2 / max(0.0001, abs(vx)), box.height / 2 / max(0.0001, abs(vy))) + gap
            var rect = CGRect(x: start.x + vx*distance - box.width/2,
                              y: start.y + vy*distance - box.height/2, width: box.width, height: box.height)
            let desired = rect.origin
            if let imageSize {
                let margin = 4 * scale
                rect.origin.x = min(max(margin, rect.minX), imageSize.width-box.width-margin)
                rect.origin.y = min(max(margin, rect.minY), imageSize.height-box.height-margin)
            }
            let clearance = rect.insetBy(dx: -shaftWidth/2-3, dy: -shaftWidth/2-3)
            var collisions = 0
            for j in 0...64 where clearance.contains(point(CGFloat(j)/64)) { collisions += 1 }
            if rect.intersects(head.bounds) { collisions += 64 }
            let score = CGFloat(collisions)*10000 + abs(offset)*10 + hypot(rect.minX-desired.x, rect.minY-desired.y)
            if score < bestScore { bestScore = score; best = rect; bestAngle = offset }
        }
        labelAngle = bestAngle
        labelBounds = mark.text.isEmpty ? .null : best
        labelRect = mark.text.isEmpty ? .null : best.insetBy(dx: padding.width*scale/2, dy: padding.height*scale/2)

    }

    func point(at t: CGFloat) -> CGPoint {
        let u = 1-t
        return CGPoint(x: u*u*start.x+2*u*t*control.x+t*t*end.x, y: u*u*start.y+2*u*t*control.y+t*t*end.y)
    }

    var handle: CGPoint { point(at: 0.5) }
    var bounds: CGRect { shaft.bounds.insetBy(dx: -shaftWidth/2, dy: -shaftWidth/2).union(head.bounds).union(labelBounds) }

    func contains(_ point: CGPoint) -> Bool {
        if labelBounds.contains(point) || head.contains(point) { return true }
        let tolerance = max(8, shaftWidth/2+4)
        var previous = start
        for i in 1...64 {
            let next = self.point(at: CGFloat(i)/64)
            let dx = next.x-previous.x, dy = next.y-previous.y
            let lengthSquared = dx*dx+dy*dy
            let t = lengthSquared > 0 ? min(1, max(0, ((point.x-previous.x)*dx+(point.y-previous.y)*dy)/lengthSquared)) : 0
            if hypot(point.x-previous.x-t*dx, point.y-previous.y-t*dy) <= tolerance { return true }
            previous = next
        }
        return false
    }

    func bend(toward point: CGPoint) -> CGFloat {
        let dx = end.x-start.x, dy = end.y-start.y
        let offsetX = point.x-(start.x+end.x)/2, offsetY = point.y-(start.y+end.y)/2
        return min(0.75, max(-0.75, (offsetY*dx-offsetX*dy)/(dx*dx+dy*dy)))
    }
}
