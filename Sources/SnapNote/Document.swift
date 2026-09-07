import AppKit
import Combine

enum Tool: String, CaseIterable, Identifiable {
    case select = "Move", arrow = "Arrow", pen = "Draw", rectangle = "Box", ellipse = "Ellipse", guide = "Guide", text = "Text"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .guide: return "line.diagonal"
        case .text: return "textformat"
        }
    }
    var key: String {
        switch self {
        case .select: return "V"
        case .arrow: return "A"
        case .pen: return "P"
        case .rectangle: return "R"
        case .ellipse: return "E"
        case .guide: return "G"
        case .text: return "T"
        }
    }
    var hint: String {
        switch self {
        case .select: return "Drag a mark to move it · Delete to remove · Double-click text to edit"
        case .arrow: return "Drag toward what matters"
        case .pen: return "Draw freely on the image"
        case .rectangle: return "Drag a box · Hold Shift for a square"
        case .ellipse: return "Drag an ellipse · Hold Shift for a circle"
        case .guide: return "Click or drag a dotted guide · Shift+G: change direction"
        case .text: return "Click to type · Shift+Return: new line · Return to place · Escape to cancel"
        }
    }
}

struct Mark: Identifiable {
    var id = UUID()
    var tool: Tool
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var text = ""
    var fontSize: CGFloat = 24
    var bend: CGFloat = 0
    var guideAxis: GuideAxis = .vertical
    var showsPercentage = true
    var textBackground = false
    // Drag-only placement choices: translate with the arrow, or follow its angle.
    var arrowLabelOffset: CGPoint?
    var arrowLabelAngle: CGFloat?

    var bounds: CGRect {
        guard let first = points.first else { return .zero }
        if tool == .text {
            let size = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)])
            return CGRect(origin: first, size: CGSize(width: size.width + 12, height: size.height + 8))
        }
        if let arrow = ArrowGeometry(self) { return arrow.bounds.insetBy(dx: -4, dy: -4) }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            .insetBy(dx: -max(8, width * 2), dy: -max(8, width * 2))
    }

    func translated(by delta: CGPoint) -> Mark {
        var copy = self
        copy.points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        return copy
    }
}

final class Document: ObservableObject {
    @Published var image: NSImage?
    @Published var marks: [Mark] = []
    @Published var tool: Tool = .arrow
    @Published var color: NSColor = .systemRed
    @Published var width: CGFloat = 4
    @Published var fontSize: CGFloat = 24
    @Published var blurb = ""
    @Published var arrowLabel = ""
    @Published var arrowFontSize: CGFloat = 16
    @Published var arrowBend: CGFloat = 0
    @Published var guideAxis: GuideAxis = .vertical
    @Published var guidePercentage = true
    @Published var textBackground = false
    @Published var arrowTextBackground = false
    @Published var editingText: Mark?
    static let arrowPresets = ["Move", "Too big", "Too small", "Center it", "Remove"]
    @Published var selected: UUID?
    @Published var status = "Ready when you are"
    @Published var capturing = false
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var cropRect: CGRect?
    private struct Snapshot {
        let image: NSImage?
        let marks: [Mark]
        let scale: CGFloat
    }
    private var snapshot: Snapshot { Snapshot(image: image, marks: marks, scale: pixelScale) }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    var pixelScale: CGFloat = 1

    func load(_ image: NSImage) {
        self.image = image
        let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        pixelScale = CGFloat(pixels?.width ?? Int(image.size.width)) / max(1, image.size.width)
        marks = []; blurb = ""; selected = nil; editingText = nil; cropRect = nil
        undoStack = []; redoStack = []; syncHistory()
        status = "Captured · Add a little context"
    }

    func commit(_ updated: [Mark]) {
        undoStack.append(snapshot)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        marks = updated
        syncHistory()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot); restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot); restore(next)
    }

    private func restore(_ state: Snapshot) {
        image = state.image; marks = state.marks; pixelScale = state.scale
        selected = nil; cropRect = nil; syncHistory()
    }

    func beginCrop() {
        guard let image else { return }
        selected = nil
        cropRect = CGRect(origin: .zero, size: image.size)
    }

    func applyCrop() throws {
        guard let image, let cropRect else { return }
        let scale = max(1, pixelScale)
        let rect = CGRect(x: (cropRect.minX*scale).rounded()/scale,
                          y: (cropRect.minY*scale).rounded()/scale,
                          width: max(1, (cropRect.width*scale).rounded())/scale,
                          height: max(1, (cropRect.height*scale).rounded())/scale)
        if rect == CGRect(origin: .zero, size: image.size) { self.cropRect = nil; return }
        let result = try Renderer.crop(image: image, marks: marks, rect: rect, scale: scale)
        undoStack.append(snapshot)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        self.image = result; marks = []; selected = nil; self.cropRect = nil
        pixelScale = scale; tool = .select; syncHistory()
        status = "Crop applied"
    }

    func deleteSelected() {
        guard let selected else { return }
        commit(marks.filter { $0.id != selected }); self.selected = nil
    }

    var selectedMark: Mark? { marks.first { $0.id == selected } }
    var adjustingTextSize: Bool { selectedMark?.tool == .text || tool == .text }
    var sizeChoices: [CGFloat] { adjustingTextSize ? [12, 16, 24, 32, 48] : [2, 4, 7, 11] }
    var activeSize: CGFloat {
        if adjustingTextSize { return selectedMark?.tool == .text ? selectedMark!.fontSize : fontSize }
        return selectedMark?.width ?? width
    }

    func setSize(_ size: CGFloat) {
        guard adjustingTextSize else { setStrokeWidth(size); return }
        fontSize = size
        guard var mark = selectedMark, mark.tool == .text, mark.fontSize != size else { return }
        mark.fontSize = size
        commit(marks.map { $0.id == mark.id ? mark : $0 })
    }

    func adjustSize(increase: Bool) {
        let next = increase ? sizeChoices.first(where: { $0 > activeSize }) : sizeChoices.last(where: { $0 < activeSize })
        if let next { setSize(next) }
    }

    var selectedArrow: Mark? { marks.first { $0.id == selected && $0.tool == .arrow } }

    var activeTextBackground: Bool { editingText?.textBackground ?? (selectedMark?.tool == .text ? selectedMark?.textBackground : nil) ?? textBackground }
    var activeArrowTextBackground: Bool { selectedArrow?.textBackground ?? arrowTextBackground }

    func setTextBackground(_ enabled: Bool) {
        textBackground = enabled
        if editingText != nil { editingText?.textBackground = enabled; return }
        guard var mark = selectedMark, mark.tool == .text, mark.textBackground != enabled else { return }
        mark.textBackground = enabled
        commit(marks.map { $0.id == mark.id ? mark : $0 })
    }

    func setArrowTextBackground(_ enabled: Bool) {
        arrowTextBackground = enabled
        guard var mark = selectedArrow, mark.textBackground != enabled else { return }
        mark.textBackground = enabled
        commit(marks.map { $0.id == mark.id ? mark : $0 })
    }

    var selectedGuide: Mark? { marks.first { $0.id == selected && $0.tool == .guide } }

    func setGuideAxis(_ axis: GuideAxis) {
        guideAxis = axis
        guard var mark = selectedGuide, let size = image?.size,
              let old = GuideGeometry(mark, imageSize: size), mark.guideAxis != axis else { return }
        let fraction = old.percentage / 100
        mark.guideAxis = axis
        mark = GuideGeometry.positioned(mark, at: CGPoint(x: size.width * fraction, y: size.height * fraction), imageSize: size)
        commit(marks.map { $0.id == mark.id ? mark : $0 })
    }

    func setGuidePercentage(_ visible: Bool) {
        guidePercentage = visible
        guard var mark = selectedGuide, mark.showsPercentage != visible else { return }
        mark.showsPercentage = visible
        commit(marks.map { $0.id == mark.id ? mark : $0 })
    }

    func setStrokeWidth(_ width: CGFloat) {
        self.width = width
        guard var mark = marks.first(where: { $0.id == selected }), mark.tool != .text, mark.width != width else { return }
        mark.width = width
        commit(marks.map { $0.id == mark.id ? mark : $0 })
    }

    func setArrowFontSize(_ size: CGFloat) {
        arrowFontSize = size
        guard var mark = selectedArrow, mark.fontSize != size else { return }
        mark.fontSize = size
        commit(marks.map { $0.id == mark.id ? mark : $0 })
    }

    func setArrowLabel(_ label: String) {
        arrowLabel = label
        if selectedArrow == nil { tool = .arrow; selected = nil }
        guard var mark = selectedArrow, mark.text != label else { return }
        mark.text = label
        commit(marks.map { $0.id == mark.id ? mark : $0 })
    }

    func setArrowBend(_ bend: CGFloat) {
        arrowBend = bend
        guard var mark = selectedArrow, mark.bend != bend else { return }
        mark.bend = bend
        commit(marks.map { $0.id == mark.id ? mark : $0 })
    }

    func syncHistory() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }
}
