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

    init?(_ mark: Mark) {
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
        let size = (mark.text as NSString).size(withAttributes: [.font: labelFont])
        labelRect = mark.text.isEmpty ? .null : CGRect(x: start.x-size.width/2, y: start.y-size.height-10, width: size.width, height: size.height)
    }

    func point(at t: CGFloat) -> CGPoint {
        let u = 1-t
        return CGPoint(x: u*u*start.x+2*u*t*control.x+t*t*end.x, y: u*u*start.y+2*u*t*control.y+t*t*end.y)
    }

    var handle: CGPoint { point(at: 0.5) }
    var bounds: CGRect { shaft.bounds.insetBy(dx: -shaftWidth/2, dy: -shaftWidth/2).union(head.bounds).union(labelRect) }

    func contains(_ point: CGPoint) -> Bool {
        if labelRect.contains(point) || head.contains(point) { return true }
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
