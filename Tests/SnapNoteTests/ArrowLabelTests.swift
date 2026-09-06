import AppKit
import SwiftUI
import XCTest
@testable import SnapNote

final class ArrowLabelTests: XCTestCase {
    override class func setUp() { super.setUp(); _ = NSApplication.shared }

    func testLabelsAvoidShaftInEveryDirectionAndCurve() throws {
        for bend: CGFloat in [-0.75, 0, 0.75] {
            for direction in 0..<16 {
                let angle = CGFloat(direction) * .pi / 8
                let start = CGPoint(x: 400, y: 400)
                let end = CGPoint(x: 400 + cos(angle)*220, y: 400 + sin(angle)*220)
                let mark = Mark(tool: .arrow, points: [start, end], color: .red, width: 7, text: "Move\nthis", fontSize: 24, bend: bend, textBackground: true)
                let arrow = try XCTUnwrap(ArrowGeometry(mark, imageSize: CGSize(width: 800, height: 800)))
                XCTAssertFalse(arrow.labelBounds.intersects(arrow.head.bounds))
                for step in 0...100 {
                    XCTAssertFalse(arrow.labelBounds.insetBy(dx: -3.5, dy: -3.5).contains(arrow.point(at: CGFloat(step)/100)), "Direction \(direction), bend \(bend)")
                }
                XCTAssertTrue(arrow.contains(CGPoint(x: arrow.labelBounds.midX, y: arrow.labelBounds.midY)))
            }
        }
    }

    func testLabelFollowsEndpointContinuouslyAndReflowsOnRelease() throws {
        let doc = Document(); doc.load(NSImage(size: CGSize(width: 800, height: 600)))
        let mark = Mark(tool: .arrow, points: [CGPoint(x: 65, y: 300), CGPoint(x: 250, y: 120)], color: .red, width: 7, text: "Move\nthis", fontSize: 32, textBackground: true)
        doc.commit([mark]); doc.selected = mark.id
        let canvas = AnnotationCanvas(document: doc)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: p.x, y: 600-p.y), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let original = try XCTUnwrap(ArrowGeometry(mark, imageSize: doc.image?.size)).labelBounds
        canvas.mouseDown(with: event(.leftMouseDown, mark.points[1]))
        var end = mark.points[1]
        var previous = original
        let initialAngle = atan2(end.y-300, end.x-65)
        for step in 0...400 {
            let angle = initialAngle + CGFloat(step)*CGFloat.pi/800
            end = CGPoint(x: 65+cos(angle)*200, y: 300+sin(angle)*200)
            canvas.mouseDragged(with: event(.leftMouseDragged, end))
            let draft = try XCTUnwrap(canvas.draft)
            let rect = try XCTUnwrap(ArrowGeometry(draft, imageSize: doc.image?.size)).labelBounds
            XCTAssertLessThan(hypot(rect.midX-previous.midX, rect.midY-previous.midY), 1.5, "Small endpoint movements must not cause label jumps")
            previous = rect
        }
        XCTAssertGreaterThan(hypot(previous.midX-original.midX, previous.midY-original.midY), 10, "The label must follow the changing arrow direction")
        canvas.mouseUp(with: event(.leftMouseUp, end))
        XCTAssertNil(doc.marks[0].arrowLabelOffset)
        XCTAssertNil(doc.marks[0].arrowLabelAngle)
        XCTAssertEqual(doc.marks[0].points[1], end)
        doc.undo(); XCTAssertEqual(doc.marks[0].points, mark.points)
    }

    func testPinnedLabelFollowsTailAndClampsContinuouslyAtEdge() throws {
        let size = CGSize(width: 800, height: 600)
        var mark = Mark(tool: .arrow, points: [CGPoint(x: 200, y: 300), CGPoint(x: 400, y: 100)], color: .red, width: 7, text: "Move\nthis", fontSize: 32, textBackground: true)
        let bounds = try XCTUnwrap(ArrowGeometry(mark, imageSize: size)).labelBounds
        mark.arrowLabelOffset = CGPoint(x: bounds.minX-200, y: bounds.minY-300)
        var previous = bounds
        for step in 1...250 {
            let moved = mark.translated(by: CGPoint(x: -CGFloat(step), y: 0))
            let rect = try XCTUnwrap(ArrowGeometry(moved, imageSize: size)).labelBounds
            XCTAssertLessThanOrEqual(abs(rect.minX-previous.minX), 1.000001)
            XCTAssertEqual(rect.minY, previous.minY)
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(rect))
            previous = rect
        }
    }

    func testLabelsStayInsideImageAtEdgesAndOnTinyCaptures() throws {
        for size in [CGSize(width: 800, height: 600), CGSize(width: 20, height: 10), CGSize(width: 1, height: 1)] {
            for start in [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)] {
                let mark = Mark(tool: .arrow, points: [start, CGPoint(x: 400, y: 300)], color: .red, width: 7, text: "A very long label\nSecond line", textBackground: true)
                let arrow = try XCTUnwrap(ArrowGeometry(mark, imageSize: size))
                XCTAssertGreaterThanOrEqual(arrow.labelBounds.minX, 0)
                XCTAssertGreaterThanOrEqual(arrow.labelBounds.minY, 0)
                XCTAssertLessThanOrEqual(arrow.labelBounds.maxX, size.width)
                XCTAssertLessThanOrEqual(arrow.labelBounds.maxY, size.height)
            }
        }
    }

    func testArrowLabelLineBreakDoesNotSubmitAndBothLinesExport() throws {
        var value = "First"
        var submitted = false
        let field = ArrowLabelField(text: Binding(get: { value }, set: { value = $0 }), onSubmit: { submitted = true })
        let coordinator = field.makeCoordinator()
        let textView = NSTextView(); textView.string = value
        textView.setSelectedRange(NSRange(location: value.utf16.count, length: 0))
        XCTAssertTrue(coordinator.control(NSTextField(), textView: textView, doCommandBy: NSSelectorFromString("insertLineBreak:")))
        XCTAssertEqual(value, "First\n"); XCTAssertFalse(submitted)
        textView.insertText("Second", replacementRange: textView.selectedRange())
        XCTAssertTrue(coordinator.control(NSTextField(), textView: textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(value, "First\nSecond"); XCTAssertTrue(submitted)
        let size = CGSize(width: 500, height: 400)
        let image = NSImage(size: size)
        image.lockFocus(); NSColor.white.setFill(); CGRect(origin: .zero, size: size).fill(); image.unlockFocus()
        let mark = Mark(tool: .arrow, points: [CGPoint(x: 250, y: 220), CGPoint(x: 250, y: 40)], color: .red, width: 4, text: value, fontSize: 24, textBackground: true)
        let arrow = try XCTUnwrap(ArrowGeometry(mark, imageSize: size))
        XCTAssertGreaterThan(arrow.labelBounds.minY, 220)
        for scale: CGFloat in [1, 2] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Renderer.export(image: image, marks: [mark], blurb: "", scale: scale)))
            for half in 0..<2 {
                var redPixels = 0
                let rect = arrow.labelRect
                let minY = rect.minY + CGFloat(half)*rect.height/2
                for y in Int(minY*scale)..<Int((minY+rect.height/2)*scale) {
                    for x in Int(rect.minX*scale)..<Int(rect.maxX*scale) {
                        if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.redComponent > 0.6, c.greenComponent < 0.3 { redPixels += 1 }
                    }
                }
                XCTAssertGreaterThan(redPixels, 30)
            }
        }
    }
}
