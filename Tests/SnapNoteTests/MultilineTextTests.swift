import AppKit
import XCTest
@testable import SnapNote

final class MultilineTextTests: XCTestCase {
    override class func setUp() { super.setUp(); _ = NSApplication.shared }

    func testLineBreakKeepsEditingAndReturnCommitsBothLines() throws {
        let doc = Document(); doc.load(Sample.image()); doc.tool = .text
        let canvas = AnnotationCanvas(document: doc)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.beginText(Mark(tool: .text, points: [CGPoint(x: 80, y: 80)], color: .red, width: 4, text: "First"))
        let field = try XCTUnwrap(canvas.textField)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        let initialHeight = field.frame.height
        XCTAssertTrue(canvas.control(field, textView: editor, doCommandBy: NSSelectorFromString("insertLineBreak:")))
        editor.insertText("Second", replacementRange: editor.selectedRange())
        XCTAssertEqual(editor.string, "First\nSecond")
        XCTAssertTrue(canvas.textField === field)
        XCTAssertEqual(doc.tool, .text)
        XCTAssertGreaterThan(field.frame.height, initialHeight)
        XCTAssertTrue(canvas.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertNil(canvas.textField)
        XCTAssertEqual(doc.tool, .select)
        XCTAssertEqual(doc.marks.first?.text, "First\nSecond")
        canvas.beginText(try XCTUnwrap(doc.marks.first))
        XCTAssertEqual(canvas.textField?.stringValue, "First\nSecond")
        XCTAssertGreaterThan(try XCTUnwrap(canvas.textField).frame.height, initialHeight)
        canvas.finishText(cancel: true)
        doc.undo(); XCTAssertTrue(doc.marks.isEmpty)
    }

    func testMultilineTextBoundsAndExportIncludeSecondLine() throws {
        let image = NSImage(size: CGSize(width: 300, height: 200))
        image.lockFocus(); NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 300, height: 200).fill(); image.unlockFocus()
        let one = Mark(tool: .text, points: [CGPoint(x: 40, y: 40)], color: .red, width: 4, text: "First", fontSize: 24)
        var two = one; two.text = "First\nSecond"
        XCTAssertGreaterThan(two.bounds.height, one.bounds.height)
        for scale: CGFloat in [1, 2] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Renderer.export(image: image, marks: [two], blurb: "", scale: scale)))
            var colored = 0
            for y in Int(one.bounds.maxY*scale)..<Int(two.bounds.maxY*scale) {
                for x in Int(two.bounds.minX*scale)..<Int(two.bounds.maxX*scale) {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.greenComponent < 0.5 { colored += 1 }
                }
            }
            XCTAssertGreaterThan(colored, 30, "Second line must be included in the exported image")
        }
    }
}
