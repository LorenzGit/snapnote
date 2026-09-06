import SwiftUI
import AppKit

struct Canvas: NSViewRepresentable {
    @ObservedObject var document: Document
    func makeNSView(context: Context) -> AnnotationCanvas { AnnotationCanvas(document: document) }
    func updateNSView(_ view: AnnotationCanvas, context: Context) {
        view.needsDisplay = true
        view.toolTip = document.selectedArrow != nil
            ? "Square handles: resize · Round handle: curve · Delete: remove · Escape: deselect"
            : "\(document.tool.hint) · \(document.tool.key)"
    }
}

final class AnnotationCanvas: NSView, NSTextFieldDelegate {
    let document: Document
    var draft: Mark?
    var dragOrigin: CGPoint?
    var moving: Mark?
    var bending: Mark?
    var resizing: Mark?
    var endpointIndex: Int?
    var textField: NSTextField?
    var editingMark: Mark?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(document: Document) {
        self.document = document
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Screenshot annotation canvas")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var imageRect: CGRect {
        guard let size = document.image?.size, size.width > 0, size.height > 0 else { return .zero }
        let scale = max(0.001, min(bounds.width/size.width, bounds.height/size.height))
        let fit = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (bounds.width-fit.width)/2, y: (bounds.height-fit.height)/2, width: fit.width, height: fit.height)
    }
    var zoom: CGFloat { imageRect.width / max(1, document.image?.size.width ?? 1) }
    func imagePoint(_ event: NSEvent, clamp: Bool = false) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        var x = (p.x-imageRect.minX)/zoom, y = (p.y-imageRect.minY)/zoom
        if clamp, let size = document.image?.size { x = min(size.width,max(0,x)); y = min(size.height,max(0,y)) }
        return CGPoint(x: x, y: y)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image = document.image, let cg = NSGraphicsContext.current?.cgContext else { return }
        let rect = imageRect
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.22); shadow.shadowBlurRadius = 16; shadow.shadowOffset = NSSize(width: 0, height: -3); shadow.set()
        NSColor.white.setFill(); rect.fill()
        NSGraphicsContext.restoreGraphicsState()
        cg.saveGState()
        cg.translateBy(x: rect.minX, y: rect.minY); cg.scaleBy(x: zoom, y: zoom)
        cg.clip(to: CGRect(origin: .zero, size: image.size))
        image.draw(in: CGRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        for mark in document.marks where mark.id != moving?.id && mark.id != bending?.id && mark.id != resizing?.id && mark.id != editingMark?.id { Renderer.draw(mark, imageSize: image.size) }
        if let draft { Renderer.draw(draft, imageSize: image.size) }
        if let selected = document.marks.first(where: { $0.id == document.selected }), moving == nil, editingMark == nil {
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: (draft ?? selected).bounds.insetBy(dx: -3, dy: -3))
            path.lineWidth = 1.5/zoom
            path.setLineDash([4/zoom, 3/zoom], count: 2, phase: 0); path.stroke()
            if let arrow = ArrowGeometry(draft ?? selected) {
                for (point, endpoint) in [(arrow.start, true), (arrow.end, true), (arrow.handle, false)] {
                    let radius = (endpoint ? 5.0 : 6.0)/zoom
                    let rect = CGRect(x: point.x-radius, y: point.y-radius, width: radius*2, height: radius*2)
                    let handle = endpoint ? NSBezierPath(roundedRect: rect, xRadius: 2/zoom, yRadius: 2/zoom) : NSBezierPath(ovalIn: rect)
                    NSColor.white.setFill(); handle.fill()
                    NSColor.controlAccentColor.setStroke(); handle.lineWidth = 2/zoom; handle.stroke()
                }
            }
        }
        cg.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        finishText()
        window?.makeFirstResponder(self)
        guard document.image != nil, imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        let p = imagePoint(event)
        if let selected = document.selectedArrow, let arrow = ArrowGeometry(selected),
           document.tool == .select || document.tool == .arrow {
            for (index, point) in [(0, arrow.start), (selected.points.count-1, arrow.end)] {
                if hypot(p.x-point.x, p.y-point.y) <= 10/zoom {
                    resizing = selected; endpointIndex = index; draft = selected
                    needsDisplay = true; return
                }
            }
            if hypot(p.x-arrow.handle.x, p.y-arrow.handle.y) <= 10/zoom {
                bending = selected; draft = selected
                needsDisplay = true; return
            }
        }
        if document.tool == .arrow, let hit = document.marks.last(where: { ArrowGeometry($0)?.contains(p) == true }) {
            document.selected = hit.id; moving = hit; draft = hit; dragOrigin = p
            needsDisplay = true; return
        }
        if document.tool == .guide, let size = document.image?.size,
           let hit = document.marks.last(where: { GuideGeometry($0, imageSize: size)?.contains(p, tolerance: max(8/zoom, $0.width)) == true }) {
            document.selected = hit.id; moving = hit; draft = hit; dragOrigin = p
            needsDisplay = true; return
        }
        if document.tool == .select {
            let hit = document.marks.last { mark in
                if let size = document.image?.size, let guide = GuideGeometry(mark, imageSize: size) { return guide.contains(p, tolerance: max(8/zoom, mark.width)) }
                return ArrowGeometry(mark)?.contains(p) ?? mark.bounds.contains(p)
            }
            document.selected = hit?.id
            if event.clickCount == 2, let hit, hit.tool == .text { beginText(hit); return }
            moving = hit; draft = hit; dragOrigin = p
        } else if document.tool == .text {
            beginText(Mark(tool: .text, points: [p], color: document.color, width: document.width, fontSize: document.fontSize))
        } else {
            document.selected = nil
            draft = Mark(tool: document.tool, points: [p], color: document.color, width: document.width)
            if document.tool == .guide, var mark = draft, let size = document.image?.size {
                mark.guideAxis = document.guideAxis; mark.showsPercentage = document.guidePercentage
                draft = GuideGeometry.positioned(mark, at: p, imageSize: size)
            }
            if document.tool == .arrow {
                draft?.text = document.arrowLabel; draft?.fontSize = document.arrowFontSize; draft?.bend = document.arrowBend
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = imagePoint(event, clamp: true)
        if let resizing, let index = endpointIndex {
            let other = resizing.points[index == 0 ? resizing.points.count-1 : 0]
            if hypot(p.x-other.x, p.y-other.y) > 2 { draft?.points[index] = p }
        } else if let bending, let arrow = ArrowGeometry(bending) {
            draft?.bend = arrow.bend(toward: p)
        } else if let moving, let origin = dragOrigin {
            draft = moving.translated(by: CGPoint(x: p.x-origin.x, y: p.y-origin.y))
            if moving.tool == .guide, let mark = draft, let point = mark.points.first, let size = document.image?.size {
                draft = GuideGeometry.positioned(mark, at: point, imageSize: size)
            }
        } else if let mark = draft, mark.tool == .guide, let size = document.image?.size {
            draft = GuideGeometry.positioned(mark, at: p, imageSize: size)
        } else if draft?.tool == .pen { draft?.points.append(p) }
        else if let first = draft?.points.first {
            var end = p
            if (draft?.tool == .ellipse || draft?.tool == .rectangle), event.modifierFlags.contains(.shift), let size = document.image?.size {
                let dx = p.x-first.x, dy = p.y-first.y
                let side = min(max(abs(dx),abs(dy)), dx >= 0 ? size.width-first.x : first.x, dy >= 0 ? size.height-first.y : first.y)
                end = CGPoint(x: first.x+(dx >= 0 ? side : -side), y: first.y+(dy >= 0 ? side : -side))
            }
            draft?.points = [first, end]
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let mark = draft else { return }
        if let resizing {
            if mark.points != resizing.points { document.commit(document.marks.map { $0.id == mark.id ? mark : $0 }) }
        } else if let bending {
            if mark.bend != bending.bend { document.commit(document.marks.map { $0.id == mark.id ? mark : $0 }) }
        } else if let moving, let origin = dragOrigin {
            let p = imagePoint(event, clamp: true)
            if hypot(p.x-origin.x, p.y-origin.y) > 0.5 && (moving.tool != .guide || mark.points != moving.points) {
                document.commit(document.marks.map { $0.id == moving.id ? mark : $0 })
            }
        } else if mark.tool == .guide || mark.tool == .pen || (mark.points.count > 1 && hypot(mark.points.last!.x-mark.points[0].x,mark.points.last!.y-mark.points[0].y) > 2) {
            let isEmptyEllipse = mark.tool == .ellipse && (abs(mark.points.last!.x-mark.points[0].x) < 1 || abs(mark.points.last!.y-mark.points[0].y) < 1)
            if !isEmptyEllipse { document.commit(document.marks + [mark]) }
            if mark.tool == .arrow || mark.tool == .guide { document.selected = mark.id }
        }
        draft = nil; moving = nil; bending = nil; resizing = nil; endpointIndex = nil; dragOrigin = nil; needsDisplay = true
    }

    func beginText(_ mark: Mark) {
        editingMark = mark
        document.status = "Text · Shift+Return: new line · Return: place"
        let p = mark.points[0]
        let x = imageRect.minX + p.x*zoom, y = imageRect.minY + p.y*zoom
        let field = NSTextField(frame: CGRect(x: x, y: y, width: max(120, min(340, bounds.width-x-8)), height: max(32, mark.fontSize*zoom+16)))
        field.font = .systemFont(ofSize: max(12,mark.fontSize*zoom), weight: .semibold)
        field.textColor = mark.color; field.drawsBackground = false
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 0
        field.cell?.wraps = false
        field.cell?.isScrollable = false
        field.lineBreakMode = .byClipping
        field.stringValue = mark.text
        field.placeholderString = "Type here…"
        field.delegate = self
        field.setAccessibilityLabel("Annotation text")
        field.toolTip = "Type a label · Shift+Return: new line · Return: place · Escape: cancel"
        addSubview(field); textField = field
        resizeTextField()
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    func controlTextDidChange(_ obj: Notification) { resizeTextField() }

    private func resizeTextField() {
        guard let field = textField, let font = field.font else { return }
        let text = (field.currentEditor()?.string ?? field.stringValue) + "\u{200B}"
        let size = (text as NSString).size(withAttributes: [.font: font])
        field.setFrameSize(CGSize(width: max(120, min(max(340, size.width + 16), bounds.width-field.frame.minX-8)),
                                 height: max(32, ceil(size.height) + 16)))
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Keep the inline editor when switching apps; commit on the next edit/export.
        if NSApp.isActive { finishText() }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finishText(cancel: true); return true }
        let newline = commandSelector == #selector(NSResponder.insertNewline(_:))
        let lineBreak = commandSelector == NSSelectorFromString("insertLineBreak:")
            || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
        if lineBreak || (newline && NSApp.currentEvent?.modifierFlags.contains(.shift) == true) {
            textView.insertNewlineIgnoringFieldEditor(nil)
            resizeTextField()
            return true
        }
        if newline { finishText(); return true }
        return false
    }

    func finishText(cancel: Bool = false) {
        guard let field = textField, var mark = editingMark else { return }
        textField = nil; editingMark = nil
        if document.tool == .text { document.tool = .select }
        mark.text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        if !cancel, !mark.text.isEmpty {
            if document.marks.contains(where: { $0.id == mark.id }) {
                document.commit(document.marks.map { $0.id == mark.id ? mark : $0 })
            } else { document.commit(document.marks + [mark]) }
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: document.deleteSelected()
        case 53: draft = nil; moving = nil; bending = nil; resizing = nil; endpointIndex = nil; document.selected = nil; needsDisplay = true
        default: super.keyDown(with: event)
        }
    }
}
