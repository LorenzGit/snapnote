import SwiftUI
import AppKit

struct CropCanvas: NSViewRepresentable {
    @ObservedObject var document: Document
    func makeNSView(context: Context) -> CropView { CropView(document: document) }
    func updateNSView(_ view: CropView, context: Context) { view.needsDisplay = true }
}

final class CropView: NSView {
    let document: Document
    private var origin: CGPoint?
    private var initial: CGRect?
    private var handle: Int?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(document: Document) {
        self.document = document
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel("Crop canvas")
        toolTip = "Drag edges or corners inward to crop, outward to extend · Drag inside to move · Return: apply · Escape: cancel"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var zoom: CGFloat {
        guard let size = document.image?.size else { return 1 }
        return max(0.001, min(max(1, bounds.width-160)/size.width, max(1, bounds.height-160)/size.height))
    }
    var imageOrigin: CGPoint {
        let size = document.image?.size ?? .zero
        return CGPoint(x: (bounds.width-size.width*zoom)/2, y: (bounds.height-size.height*zoom)/2)
    }
    func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: (p.x-imageOrigin.x)/zoom, y: (p.y-imageOrigin.y)/zoom)
    }
    func handles(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x:r.minX,y:r.minY), CGPoint(x:r.midX,y:r.minY), CGPoint(x:r.maxX,y:r.minY),
         CGPoint(x:r.maxX,y:r.midY), CGPoint(x:r.maxX,y:r.maxY), CGPoint(x:r.midX,y:r.maxY),
         CGPoint(x:r.minX,y:r.maxY), CGPoint(x:r.minX,y:r.midY)]
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let image = document.image, let crop = document.cropRect, let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState(); defer { cg.restoreGState() }
        cg.translateBy(x: imageOrigin.x, y: imageOrigin.y); cg.scaleBy(x: zoom, y: zoom)
        NSColor.black.setFill(); crop.fill()
        cg.saveGState()
        cg.clip(to: CGRect(origin: .zero, size: image.size))
        image.draw(in: CGRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        document.marks.forEach { Renderer.draw($0, imageSize: image.size) }
        cg.restoreGState()
        let visible = CGRect(x: -imageOrigin.x/zoom, y: -imageOrigin.y/zoom, width: bounds.width/zoom, height: bounds.height/zoom)
        let mask = NSBezierPath(rect: visible); mask.append(NSBezierPath(rect: crop)); mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.6).setFill(); mask.fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        let grid = NSBezierPath(); grid.lineWidth = 1/zoom
        for n in 1...2 {
            let x = crop.minX+crop.width*CGFloat(n)/3, y = crop.minY+crop.height*CGFloat(n)/3
            grid.move(to: CGPoint(x:x,y:crop.minY)); grid.line(to: CGPoint(x:x,y:crop.maxY))
            grid.move(to: CGPoint(x:crop.minX,y:y)); grid.line(to: CGPoint(x:crop.maxX,y:y))
        }
        grid.stroke()
        NSColor.white.setStroke(); let border = NSBezierPath(rect: crop); border.lineWidth = 1.5/zoom; border.stroke()
        for p in handles(crop) {
            let box = CGRect(x:p.x-4/zoom,y:p.y-4/zoom,width:8/zoom,height:8/zoom)
            NSColor.white.setFill(); box.fill()
            NSColor.black.setStroke(); let outline = NSBezierPath(rect: box); outline.lineWidth = 1/zoom; outline.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let rect = document.cropRect else { return }
        let p = point(event)
        origin = p; initial = rect
        handle = handles(rect).firstIndex { hypot($0.x-p.x,$0.y-p.y) <= 12/zoom }
        if handle == nil {
            let tolerance = 8/zoom
            if p.x >= rect.minX && p.x <= rect.maxX {
                if abs(p.y-rect.minY) <= tolerance { handle = 1 }
                else if abs(p.y-rect.maxY) <= tolerance { handle = 5 }
            }
            if p.y >= rect.minY && p.y <= rect.maxY {
                if abs(p.x-rect.minX) <= tolerance { handle = 7 }
                else if abs(p.x-rect.maxX) <= tolerance { handle = 3 }
            }
        }
        if handle == nil && !rect.contains(p) { origin = nil; initial = nil }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin, let initial else { return }
        let p = point(event), dx = p.x-origin.x, dy = p.y-origin.y
        guard let handle else {
            document.cropRect = initial.offsetBy(dx: dx, dy: dy); return
        }
        var left = initial.minX, right = initial.maxX, top = initial.minY, bottom = initial.maxY
        let minimum = 1/max(1,document.pixelScale)
        if [0,6,7].contains(handle) { left = min(right-minimum, left+dx) }
        if [2,3,4].contains(handle) { right = max(left+minimum, right+dx) }
        if [0,1,2].contains(handle) { top = min(bottom-minimum, top+dy) }
        if [4,5,6].contains(handle) { bottom = max(top+minimum, bottom+dy) }
        document.cropRect = CGRect(x:left,y:top,width:right-left,height:bottom-top)
    }
    override func mouseUp(with event: NSEvent) { origin = nil; initial = nil; handle = nil }
}
