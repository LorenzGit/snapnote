import AppKit
import XCTest
@testable import SnapNote

final class TextBackgroundTests: XCTestCase {
    override class func setUp() { super.setUp(); _ = NSApplication.shared }

    func testBackgroundPixelsForArrowAndMultilineText() throws {
        let size = CGSize(width: 500, height: 300)
        let image = NSImage(size: size)
        image.lockFocus(); NSColor.white.setFill(); CGRect(origin: .zero, size: size).fill(); image.unlockFocus()
        for tool: Tool in [.arrow, .text] {
            var mark = Mark(tool: tool, points: [CGPoint(x: 150, y: 100), CGPoint(x: 400, y: 200)], color: .red, width: 4, text: tool == .arrow ? "Move" : "First\nSecond", fontSize: 24)
            for scale: CGFloat in [1, 2] {
                for enabled in [false, true] {
                    mark.textBackground = enabled
                    let rect = tool == .arrow ? try XCTUnwrap(ArrowGeometry(mark, imageSize: size)).labelBounds : mark.bounds
                    let sample = CGPoint(x: rect.minX + (enabled ? 2 : -2), y: rect.midY)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Renderer.export(image: image, marks: [mark], blurb: "", scale: scale)))
                    let color = try XCTUnwrap(bitmap.colorAt(x: Int(sample.x*scale), y: Int(sample.y*scale))?.usingColorSpace(.deviceRGB))
                    if enabled { XCTAssertLessThan(color.redComponent, 0.1) }
                    else { XCTAssertGreaterThan(color.redComponent, 0.9) }
                }
            }
        }
    }

    func testSelectedBackgroundChangesCanBeUndoneAndDefaultsAreSeparate() {
        let doc = Document()
        let text = Mark(tool: .text, points: [.zero], color: .red, width: 4, text: "Text")
        let arrow = Mark(tool: .arrow, points: [.zero, CGPoint(x: 100, y: 100)], color: .red, width: 4, text: "Move")
        XCTAssertFalse(doc.textBackground); XCTAssertFalse(doc.arrowTextBackground)
        doc.commit([text, arrow]); doc.selected = text.id
        doc.setTextBackground(true)
        XCTAssertTrue(doc.marks[0].textBackground); XCTAssertFalse(doc.marks[1].textBackground)
        XCTAssertFalse(doc.arrowTextBackground)
        doc.selected = arrow.id; doc.setArrowTextBackground(true)
        XCTAssertTrue(doc.marks[1].textBackground)
        doc.undo(); XCTAssertFalse(doc.marks[1].textBackground)
        doc.undo(); XCTAssertFalse(doc.marks[0].textBackground)
    }

    func testShortcutTogglesWhileTypingWithoutCommittingText() throws {
        let app = AppDelegate(); let doc = app.document
        doc.load(Sample.image()); doc.tool = .text
        let canvas = AnnotationCanvas(document: doc)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.beginText(Mark(tool: .text, points: [CGPoint(x: 100, y: 100)], color: .red, width: 4))
        let field = try XCTUnwrap(canvas.textField)
        field.stringValue = "Still editing"
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "B", charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11))
        XCTAssertNil(app.handleKey(key))
        canvas.updateTextBackground()
        XCTAssertTrue(doc.editingText?.textBackground == true)
        XCTAssertTrue(field.drawsBackground)
        XCTAssertTrue((field.currentEditor() as? NSTextView)?.drawsBackground == true)
        XCTAssertTrue(doc.marks.isEmpty)
        XCTAssertTrue(canvas.textField === field)
        XCTAssertEqual(field.stringValue, "Still editing")
        canvas.finishText()
        XCTAssertEqual(doc.marks.first?.text, "Still editing")
        XCTAssertTrue(doc.marks.first?.textBackground == true)
        doc.undo(); XCTAssertTrue(doc.marks.isEmpty)
        app.arrowLabelPopoverOpen = true; doc.tool = .arrow
        XCTAssertNil(app.handleKey(key))
        XCTAssertTrue(doc.arrowTextBackground)
    }
}
