import AppKit
import Combine

enum Tool: String, CaseIterable, Identifiable {
    case select = "Move", arrow = "Arrow", pen = "Draw", rectangle = "Box", ellipse = "Ellipse", text = "Text"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
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
    static let arrowPresets = ["Move", "Too big", "Too small", "Center it", "Remove"]
    @Published var selected: UUID?
    @Published var status = "Ready when you are"
    @Published var capturing = false
    @Published var canUndo = false
    @Published var canRedo = false
    private var undoStack: [[Mark]] = []
    private var redoStack: [[Mark]] = []
    var pixelScale: CGFloat = 1

    func load(_ image: NSImage) {
        self.image = image
        let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        pixelScale = CGFloat(pixels?.width ?? Int(image.size.width)) / max(1, image.size.width)
        marks = []; blurb = ""; selected = nil
        undoStack = []; redoStack = []; syncHistory()
        status = "Captured · Add a little context"
    }

    func commit(_ updated: [Mark]) {
        undoStack.append(marks)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        marks = updated
        syncHistory()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(marks); marks = previous; selected = nil; syncHistory()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(marks); marks = next; selected = nil; syncHistory()
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
