import AppKit
import XCTest
@testable import SnapNote

final class EllipseTests: XCTestCase {
    override class func setUp() { super.setUp(); _ = NSApplication.shared }

    func testEllipseExportsAnOutlineInEitherDragDirection() throws {
        let image = NSImage(size: CGSize(width: 240, height: 180))
        image.lockFocus(); NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 240, height: 180).fill(); image.unlockFocus()
        for scale: CGFloat in [1, 2] {
            for points in [[CGPoint(x: 40, y: 40), CGPoint(x: 200, y: 140)], [CGPoint(x: 200, y: 140), CGPoint(x: 40, y: 40)]] {
                let mark = Mark(tool: .ellipse, points: points, color: .red, width: 4)
                let png = try Renderer.export(image: image, marks: [mark], blurb: "", scale: scale)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
                for point in [CGPoint(x: 40, y: 90), CGPoint(x: 120, y: 40), CGPoint(x: 200, y: 90), CGPoint(x: 120, y: 140)] {
                    let color = try XCTUnwrap(bitmap.colorAt(x: Int(point.x*scale), y: Int(point.y*scale))?.usingColorSpace(.deviceRGB))
                    XCTAssertLessThan(color.greenComponent, 0.3, "Ellipse edge must render")
                }
                for point in [CGPoint(x: 40, y: 40), CGPoint(x: 200, y: 140), CGPoint(x: 120, y: 90)] {
                    let color = try XCTUnwrap(bitmap.colorAt(x: Int(point.x*scale), y: Int(point.y*scale))?.usingColorSpace(.deviceRGB))
                    XCTAssertGreaterThan(color.greenComponent, 0.9, "Corners and center must remain unfilled")
                }
            }
        }
    }

    func testEllipseDragCircleConstraintMoveAndUndo() throws {
        let doc = Document()
        doc.load(NSImage(size: CGSize(width: 800, height: 600))); doc.tool = .ellipse
        let canvas = AnnotationCanvas(document: doc)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        func drag(_ start: CGPoint, _ end: CGPoint, shift: Bool = false) {
            func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: CGPoint(x: p.x, y: 600-p.y), modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            canvas.mouseDown(with: event(.leftMouseDown, start)); canvas.mouseDragged(with: event(.leftMouseDragged, end)); canvas.mouseUp(with: event(.leftMouseUp, end))
        }
        drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
        XCTAssertEqual(doc.marks[0].points, [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200)])
        doc.tool = .select
        drag(CGPoint(x: 200, y: 150), CGPoint(x: 240, y: 180))
        XCTAssertEqual(doc.marks[0].points[0], CGPoint(x: 140, y: 130))
        doc.undo(); XCTAssertEqual(doc.marks[0].points[0], CGPoint(x: 100, y: 100))
        doc.tool = .ellipse
        drag(CGPoint(x: 500, y: 400), CGPoint(x: 350, y: 320), shift: true)
        XCTAssertEqual(doc.marks[1].points, [CGPoint(x: 500, y: 400), CGPoint(x: 350, y: 250)])
        drag(CGPoint(x: 750, y: 550), CGPoint(x: 790, y: 600), shift: true)
        XCTAssertEqual(doc.marks[2].points, [CGPoint(x: 750, y: 550), CGPoint(x: 800, y: 600)])
        drag(CGPoint(x: 50, y: 50), CGPoint(x: 90, y: 50))
        XCTAssertEqual(doc.marks.count, 3, "Flat drags must not add invisible ellipses")
        doc.undo(); doc.undo(); doc.undo(); XCTAssertTrue(doc.marks.isEmpty)
    }

    func testToolAndSizeShortcutsRespectTextEditing() throws {
        let app = AppDelegate()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSView()
        window.makeFirstResponder(window.contentView)
        func key(_ value: String) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: value, charactersIgnoringModifiers: value, isARepeat: false, keyCode: 0)!
        }
        XCTAssertNil(app.handleKey(key("e"))); XCTAssertEqual(app.document.tool, .ellipse)
        let shape = Mark(tool: .ellipse, points: [.zero, CGPoint(x: 80, y: 40)], color: .red, width: 4)
        app.document.commit([shape]); app.document.selected = shape.id
        XCTAssertNil(app.handleKey(key("]"))); XCTAssertEqual(app.document.marks[0].width, 7)
        app.document.undo(); XCTAssertEqual(app.document.marks[0].width, 4)
        let text = Mark(tool: .text, points: [.zero], color: .red, width: 4, text: "Label", fontSize: 24)
        app.document.commit([text]); app.document.selected = text.id
        XCTAssertNil(app.handleKey(key("["))); XCTAssertEqual(app.document.marks[0].fontSize, 16)
        let field = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView?.addSubview(field); window.makeFirstResponder(field)
        app.document.tool = .arrow
        for value in ["e", "[", "]"] {
            let event = key(value)
            XCTAssertTrue(app.handleKey(event) === event)
        }
        XCTAssertEqual(app.document.tool, .arrow)
        XCTAssertEqual(app.document.marks[0].fontSize, 16)
    }
}
