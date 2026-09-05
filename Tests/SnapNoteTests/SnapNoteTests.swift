import XCTest
import AppKit
@testable import SnapNote

final class SnapNoteTests: XCTestCase {
    override class func setUp() { super.setUp(); _ = NSApplication.shared }

    func testUndoRedoBranchesAndDelete() {
        let doc = Document()
        let a = Mark(tool: .arrow, points: [.zero, CGPoint(x: 50, y: 50)], color: .red, width: 4)
        let b = Mark(tool: .text, points: [CGPoint(x: 10, y: 10)], color: .blue, width: 4, text: "Label")
        doc.commit([a]); doc.commit([a,b]); doc.undo()
        XCTAssertEqual(doc.marks.count, 1); XCTAssertTrue(doc.canRedo)
        doc.redo(); XCTAssertEqual(doc.marks.count, 2)
        doc.selected = b.id; doc.deleteSelected()
        XCTAssertEqual(doc.marks.map(\.id), [a.id])
        doc.undo(); XCTAssertEqual(doc.marks.count, 2)
        doc.commit([]); XCTAssertFalse(doc.canRedo)
    }

    func testExportKeepsPixelsAndOrientation() throws {
        let image = NSImage(size: CGSize(width: 200, height: 100))
        image.lockFocusFlipped(true)
        NSColor.red.setFill(); CGRect(x: 0, y: 0, width: 200, height: 50).fill()
        NSColor.blue.setFill(); CGRect(x: 0, y: 50, width: 200, height: 50).fill()
        image.unlockFocus()
        let data = try Renderer.export(image: image, marks: [], blurb: "", scale: 2)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, 400); XCTAssertEqual(bitmap.pixelsHigh, 200)
        let top = try XCTUnwrap(bitmap.colorAt(x: 20, y: 20)?.usingColorSpace(.deviceRGB))
        let bottom = try XCTUnwrap(bitmap.colorAt(x: 20, y: 170)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(top.redComponent, 0.9); XCTAssertLessThan(top.blueComponent, 0.1)
        XCTAssertGreaterThan(bottom.blueComponent, 0.9); XCTAssertLessThan(bottom.redComponent, 0.1)
    }

    func testLongFooterWrapsWithoutWideningTinyImage() throws {
        let short = Renderer.footerHeight(blurb: "A note", width: 320)
        let note = String(repeating: "This is a longer explanation with useful context. ", count: 12)
        let long = Renderer.footerHeight(blurb: note, width: 320)
        XCTAssertGreaterThan(long, short * 3)
        XCTAssertEqual(Renderer.footerHeight(blurb: " \n ", width: 100), 0)
        let image = NSImage(size: CGSize(width: 40, height: 40))
        image.lockFocus(); NSColor.orange.setFill(); CGRect(x: 0, y: 0, width: 40, height: 40).fill(); image.unlockFocus()
        let data = try Renderer.export(image: image, marks: [], blurb: note, scale: 1)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, 40)
        XCTAssertEqual(bitmap.pixelsHigh, Int(40 + Renderer.footerHeight(blurb: note, width: 40)))
    }

    func testFooterNeverAddsSideBordersOrShiftsAnnotations() throws {
        for width: CGFloat in [40, 310, 320, 640] {
            let image = NSImage(size: CGSize(width: width,height: 80))
            image.lockFocus()
            NSColor.black.setFill(); CGRect(x: 0,y: 0,width: width,height: 80).fill()
            image.unlockFocus()
            let mark = Mark(tool: .rectangle, points: [CGPoint(x: 0,y: 15),CGPoint(x: 15,y: 60)], color: .red, width: 4)
            for scale: CGFloat in [1,2] {
                let plain = try XCTUnwrap(NSBitmapImageRep(data: Renderer.export(image: image, marks: [mark], blurb: "", scale: scale)))
                let captioned = try XCTUnwrap(NSBitmapImageRep(data: Renderer.export(image: image, marks: [mark], blurb: "A footer that wraps under the screenshot.", scale: scale)))
                XCTAssertEqual(captioned.pixelsWide,Int(width*scale))
                XCTAssertGreaterThan(captioned.pixelsHigh,plain.pixelsHigh)
                for x in [0, 1, plain.pixelsWide/2, plain.pixelsWide-2, plain.pixelsWide-1] {
                    for y in [Int(5*scale),Int(30*scale),Int(75*scale)] {
                        let expected = try XCTUnwrap(plain.colorAt(x: x,y: y)?.usingColorSpace(.deviceRGB))
                        let actual = try XCTUnwrap(captioned.colorAt(x: x,y: y)?.usingColorSpace(.deviceRGB))
                        XCTAssertEqual(actual.redComponent,expected.redComponent,accuracy: 0.01)
                        XCTAssertEqual(actual.greenComponent,expected.greenComponent,accuracy: 0.01)
                        XCTAssertEqual(actual.blueComponent,expected.blueComponent,accuracy: 0.01)
                    }
                }
            }
        }
    }

    func testMarksAndFooterAreActuallyRendered() throws {
        let image = NSImage(size: CGSize(width: 400, height: 200))
        image.lockFocus(); NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 400, height: 200).fill(); image.unlockFocus()
        let marks = [Mark(tool: .rectangle, points: [CGPoint(x: 20,y: 20), CGPoint(x: 80,y: 80)], color: .red, width: 4),
                     Mark(tool: .arrow, points: [CGPoint(x: 120,y: 50), CGPoint(x: 180,y: 50)], color: .blue, width: 4),
                     Mark(tool: .text, points: [CGPoint(x: 220,y: 40)], color: .black, width: 4, text: "Hello")]
        let data = try Renderer.export(image: image, marks: marks, blurb: "Please review this.", scale: 1)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let red = try XCTUnwrap(bitmap.colorAt(x: 20,y: 40)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(red.redComponent, 0.9); XCTAssertLessThan(red.greenComponent, 0.25)
        let blue = try XCTUnwrap(bitmap.colorAt(x: 150,y: 50)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(blue.blueComponent, 0.9); XCTAssertLessThan(blue.redComponent, 0.1)
        var darkPixels = 0
        for y in 218..<bitmap.pixelsHigh-10 {
            for x in 20..<250 {
                if let c = bitmap.colorAt(x: x,y: y)?.usingColorSpace(.deviceRGB), c.redComponent < 0.5 { darkPixels += 1 }
            }
        }
        XCTAssertGreaterThan(darkPixels, 100, "Footer text must be present, not clipped or off-canvas")
    }

    func testTranslatedMarkKeepsOriginalAndDirection() {
        let mark = Mark(tool: .arrow, points: [CGPoint(x: 80,y: 60), CGPoint(x: 20,y: 10)], color: .red, width: 4)
        let moved = mark.translated(by: CGPoint(x: 10,y: -5))
        XCTAssertEqual(moved.points[1], CGPoint(x: 30,y: 5))
        XCTAssertEqual(mark.points[1], CGPoint(x: 20,y: 10))
        XCTAssertTrue(mark.bounds.contains(CGPoint(x: 40,y: 40)))
    }

    func testArrowDoesNotPaintBeyondItsTip() throws {
        let image = NSImage(size: CGSize(width: 240, height: 240))
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 240, height: 240).fill()
        image.unlockFocus()
        for width: CGFloat in [4, 28] {
            for length: CGFloat in [12, 160] {
                for direction in 0..<8 {
                    let angle = CGFloat(direction) * .pi / 4
                    let unit = CGPoint(x: cos(angle), y: sin(angle))
                    let start = CGPoint(x: 120-unit.x*length/2, y: 120-unit.y*length/2)
                    let end = CGPoint(x: 120+unit.x*length/2, y: 120+unit.y*length/2)
                    let mark = Mark(tool: .arrow, points: [start, end], color: .red, width: width)
                    let data = try Renderer.export(image: image, marks: [mark], blurb: "", scale: 2)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
                    var painted = 0
                    for y in 0..<bitmap.pixelsHigh {
                        for x in 0..<bitmap.pixelsWide {
                            let c = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                            guard c.greenComponent < 0.5 else { continue }
                            painted += 1
                            let pastTip = ((CGFloat(x)+0.5)/2-end.x)*unit.x + ((CGFloat(y)+0.5)/2-end.y)*unit.y
                            XCTAssertLessThanOrEqual(pastTip, 0.75, "Arrow extends beyond tip: width \(width), length \(length), direction \(direction)")
                        }
                    }
                    XCTAssertGreaterThan(painted, 12, "Arrow must still render")
                }
            }
        }
    }
    func testCanvasTextPlacementAndCommit() {
        let doc = Document(); doc.load(Sample.image()); doc.tool = .text
        let canvas = AnnotationCanvas(document: doc)
        let window = NSWindow(contentRect: CGRect(x: 0,y: 0,width: 1000,height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 400,y: 150), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        canvas.mouseDown(with: event)
        XCTAssertNotNil(canvas.textField)
        canvas.textField?.stringValue = "A useful annotation"
        canvas.finishText()
        XCTAssertEqual(doc.marks.count, 1)
        XCTAssertEqual(doc.marks.first?.text, "A useful annotation")
    }

    func testClickOutsideTextCommitsAndReturnsToSelection() {
        let doc = Document(); doc.load(Sample.image()); doc.tool = .text
        let canvas = AnnotationCanvas(document: doc)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        func click(_ x: CGFloat, _ y: CGFloat, count: Int = 1) {
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: x, y: 560-y), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: count, pressure: 1)!
            canvas.mouseDown(with: event)
        }
        click(100, 100)
        canvas.textField?.stringValue = "First label"
        click(700, 400)
        XCTAssertEqual(doc.tool, .select)
        XCTAssertEqual(doc.marks.count, 1)
        XCTAssertEqual(doc.marks[0].text, "First label")
        XCTAssertNil(canvas.textField, "Clicking outside must not start another label")
        click(105, 105, count: 2)
        XCTAssertNotNil(canvas.textField)
        canvas.textField?.stringValue = "Edited label"
        click(700, 400)
        XCTAssertEqual(doc.tool, .select)
        XCTAssertEqual(doc.marks.count, 1)
        XCTAssertEqual(doc.marks[0].text, "Edited label")
        doc.undo(); XCTAssertEqual(doc.marks[0].text, "First label")
        doc.tool = .text
        click(500, 300)
        click(700, 400)
        XCTAssertEqual(doc.tool, .select)
        XCTAssertEqual(doc.marks.count, 1, "An empty label must be discarded")
        XCTAssertNil(canvas.textField)
    }

    func testEnlargedPreviewMapsDrawingBackToOriginalImage() throws {
        let doc = Document()
        let image = NSImage(size: CGSize(width: 200, height: 100))
        image.lockFocus(); NSColor.white.setFill(); CGRect(x: 0,y: 0,width: 200,height: 100).fill(); image.unlockFocus()
        doc.load(image)
        let canvas = AnnotationCanvas(document: doc)
        let window = NSWindow(contentRect: CGRect(x: 0,y: 0,width: 800,height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        XCTAssertEqual(canvas.imageRect, CGRect(x: 0,y: 100,width: 800,height: 400))
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x,y: y), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: event(.leftMouseDown,200,400))
        canvas.mouseDragged(with: event(.leftMouseDragged,600,200))
        canvas.mouseUp(with: event(.leftMouseUp,600,200))
        XCTAssertEqual(doc.marks.first?.points, [CGPoint(x: 50,y: 25), CGPoint(x: 150,y: 75)])
        let data = try Renderer.export(image: image, marks: doc.marks, blurb: "", scale: 1)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide,200)
        XCTAssertEqual(bitmap.pixelsHigh,100)
    }

}
