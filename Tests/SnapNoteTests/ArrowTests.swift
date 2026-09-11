import AppKit
import XCTest
@testable import SnapNote

final class ArrowTests: XCTestCase {
    override class func setUp() { super.setUp(); _ = NSApplication.shared }

    func testHeadGrowsWithStrokeAndEndpointLength() throws {
        for length: CGFloat in [12, 30, 100, 400] {
            var previous: CGFloat = 0
            for width: CGFloat in [2, 4, 7, 11] {
                let mark = Mark(tool: .arrow, points: [.zero, CGPoint(x: length, y: 0)], color: .red, width: width)
                let arrow = try XCTUnwrap(ArrowGeometry(mark))
                XCTAssertGreaterThan(arrow.head.bounds.width, previous)
                XCTAssertLessThan(arrow.head.bounds.width, length/2)
                previous = arrow.head.bounds.width
            }
        }
        for width: CGFloat in [2, 4, 7, 11] {
            var previous: CGFloat = 0
            for length: CGFloat in [12, 30, 100, 400] {
                let arrow = try XCTUnwrap(ArrowGeometry(Mark(tool: .arrow, points: [.zero, CGPoint(x: length, y: 0)], color: .red, width: width)))
                XCTAssertGreaterThan(arrow.head.bounds.width, previous)
                previous = arrow.head.bounds.width
            }
        }
    }

    func testCurveGeometryMovesAndCanBeSelectedAwayFromStraightLine() throws {
        let mark = Mark(tool: .arrow, points: [CGPoint(x: 100,y: 100), CGPoint(x: 500,y: 100)], color: .red, width: 4, text: "Move", fontSize: 16, bend: 0.4)
        let arrow = try XCTUnwrap(ArrowGeometry(mark))
        XCTAssertEqual(arrow.handle, CGPoint(x: 300,y: 260))
        XCTAssertTrue(mark.bounds.contains(arrow.handle))
        XCTAssertTrue(arrow.contains(arrow.handle))
        XCTAssertFalse(arrow.contains(CGPoint(x: 300,y: 100)))
        XCTAssertTrue(arrow.contains(CGPoint(x: 100,y: 100)))
        XCTAssertEqual(arrow.bend(toward: CGPoint(x: 300,y: -60)), -0.4, accuracy: 0.001)
        let moved = mark.translated(by: CGPoint(x: 20,y: 30))
        XCTAssertEqual(try XCTUnwrap(ArrowGeometry(moved)).handle, CGPoint(x: 320,y: 290))
        XCTAssertEqual(moved.text, "Move")
        XCTAssertEqual(moved.bend, mark.bend)
    }

    func testEveryPresetAndCurvedShaftAreExported() throws {
        let image = NSImage(size: CGSize(width: 600,height: 400))
        image.lockFocus(); NSColor.white.setFill(); CGRect(x: 0,y: 0,width: 600,height: 400).fill(); image.unlockFocus()
        for label in Document.arrowPresets {
            let mark = Mark(tool: .arrow, points: [CGPoint(x: 150,y: 100), CGPoint(x: 450,y: 100)], color: .red, width: 4, text: label, fontSize: 16, bend: 0.5)
            let geometry = try XCTUnwrap(ArrowGeometry(mark))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Renderer.export(image: image, marks: [mark], blurb: "", scale: 1)))
            let middle = try XCTUnwrap(bitmap.colorAt(x: 300,y: 250)?.usingColorSpace(.deviceRGB))
            XCTAssertLessThan(middle.greenComponent, 0.2, "Curved shaft must render")
            var labelPixels = 0
            for y in Int(geometry.labelRect.minY)..<Int(geometry.labelRect.maxY) {
                for x in Int(geometry.labelRect.minX)..<Int(geometry.labelRect.maxX) {
                    if let c = bitmap.colorAt(x: x,y: y)?.usingColorSpace(.deviceRGB), c.greenComponent < 0.5 { labelPixels += 1 }
                }
            }
            XCTAssertGreaterThan(labelPixels, 40, "Preset text must render: \(label)")
        }
    }

    func testDrawingAndBendingRemainOneUndoStepEach() throws {
        let doc = Document()
        doc.load(NSImage(size: CGSize(width: 800,height: 600)))
        doc.setArrowLabel("Too big")
        let canvas = AnnotationCanvas(document: doc)
        let window = NSWindow(contentRect: CGRect(x: 0,y: 0,width: 800,height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x,y: y), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: event(.leftMouseDown,100,450))
        canvas.mouseDragged(with: event(.leftMouseDragged,500,450))
        canvas.mouseUp(with: event(.leftMouseUp,500,450))
        XCTAssertEqual(doc.marks.count,1)
        XCTAssertEqual(doc.selectedArrow?.text,"Too big")
        canvas.mouseDown(with: event(.leftMouseDown,300,450))
        canvas.mouseDragged(with: event(.leftMouseDragged,300,350))
        canvas.mouseUp(with: event(.leftMouseUp,300,350))
        XCTAssertEqual(doc.marks.count,1)
        XCTAssertEqual(doc.marks[0].bend,0.25,accuracy: 0.001)
        doc.undo(); XCTAssertEqual(doc.marks[0].bend,0)
        doc.undo(); XCTAssertTrue(doc.marks.isEmpty)
        doc.redo(); doc.redo(); XCTAssertEqual(doc.marks[0].bend,0.25,accuracy: 0.001)
        doc.selected = doc.marks[0].id
        doc.setArrowLabel("Remove"); doc.setArrowBend(-0.25)
        XCTAssertEqual(doc.marks[0].text,"Remove")
        XCTAssertEqual(doc.marks[0].bend,-0.25)
        doc.undo(); XCTAssertEqual(doc.marks[0].bend,0.25)
        doc.undo(); XCTAssertEqual(doc.marks[0].text,"Too big")
    }
    func testArrowEndpointsAndSizesCanBeEditedAndUndone() throws {
        let doc = Document()
        doc.load(NSImage(size: CGSize(width: 800,height: 600)))
        let original = Mark(tool: .arrow, points: [CGPoint(x: 100,y: 100), CGPoint(x: 500,y: 100)], color: .red, width: 4, text: "Move", fontSize: 16, bend: 0.25)
        doc.commit([original]); doc.selected = original.id
        let canvas = AnnotationCanvas(document: doc)
        let window = NSWindow(contentRect: CGRect(x: 0,y: 0,width: 800,height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x,y: 600-y), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: event(.leftMouseDown,500,100))
        canvas.mouseDragged(with: event(.leftMouseDragged,650,200))
        canvas.mouseUp(with: event(.leftMouseUp,650,200))
        XCTAssertEqual(doc.marks.count,1)
        XCTAssertEqual(doc.marks[0].points,[CGPoint(x: 100,y: 100),CGPoint(x: 650,y: 200)])
        canvas.mouseDown(with: event(.leftMouseDown,100,100))
        canvas.mouseDragged(with: event(.leftMouseDragged,150,150))
        canvas.mouseUp(with: event(.leftMouseUp,150,150))
        XCTAssertEqual(doc.marks[0].points,[CGPoint(x: 150,y: 150),CGPoint(x: 650,y: 200)])
        XCTAssertEqual(doc.marks[0].text,"Move")
        XCTAssertEqual(doc.marks[0].bend,0.25)
        doc.setStrokeWidth(11); doc.setArrowFontSize(24)
        XCTAssertEqual(doc.marks[0].width,11)
        XCTAssertEqual(doc.marks[0].fontSize,24)
        doc.undo(); doc.undo(); doc.undo(); doc.undo()
        XCTAssertEqual(doc.marks[0].points,original.points)
        XCTAssertEqual(doc.marks[0].width,4)
        XCTAssertEqual(doc.marks[0].fontSize,16)
    }

    func testAnnotationTextHasNoWhiteBackground() throws {
        let image = NSImage(size: CGSize(width: 600,height: 400))
        image.lockFocus(); NSColor.black.setFill(); CGRect(x: 0,y: 0,width: 600,height: 400).fill(); image.unlockFocus()
        let arrow = Mark(tool: .arrow, points: [CGPoint(x: 150,y: 100),CGPoint(x: 450,y: 200)], color: .red, width: 4, text: "Too small", fontSize: 16)
        let text = Mark(tool: .text, points: [CGPoint(x: 100,y: 250)], color: .red, width: 4, text: "Plain text")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Renderer.export(image: image, marks: [arrow,text], blurb: "", scale: 1)))
        for rect in [try XCTUnwrap(ArrowGeometry(arrow)).labelRect, text.bounds] {
            var whitePixels = 0
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    let c = try XCTUnwrap(bitmap.colorAt(x: x,y: y)?.usingColorSpace(.deviceRGB))
                    if c.redComponent > 0.75 && c.greenComponent > 0.75 && c.blueComponent > 0.75 { whitePixels += 1 }
                }
            }
            XCTAssertEqual(whitePixels,0,"Text must not introduce a white background")
        }
    }

    func testCustomLabelTypingBypassesDrawingShortcuts() throws {
        let app = AppDelegate()
        app.arrowLabelPopoverOpen = true
        for modifiers: NSEvent.ModifierFlags in [[], .command] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9))
            XCTAssertTrue(app.handleKey(event) === event)
            XCTAssertEqual(app.document.tool,.arrow)
        }
    }

}
