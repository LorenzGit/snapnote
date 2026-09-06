import AppKit
import XCTest
@testable import SnapNote

final class GuideTests: XCTestCase {
    override class func setUp() { super.setUp(); _ = NSApplication.shared }

    func testPercentageAndLabelsStayWithinImageAtEveryEdge() throws {
        for size in [CGSize(width: 1000, height: 600), CGSize(width: 20, height: 12), CGSize(width: 1, height: 1), CGSize(width: 1, height: 500)] {
            for axis in GuideAxis.allCases {
                for fraction: CGFloat in [0, 0.25, 0.5, 0.99, 1] {
                    var mark = Mark(tool: .guide, points: [], color: .red, width: 11)
                    mark.guideAxis = axis
                    mark = GuideGeometry.positioned(mark, at: CGPoint(x: size.width*fraction, y: size.height*fraction), imageSize: size)
                    let guide = try XCTUnwrap(GuideGeometry(mark, imageSize: size))
                    XCTAssertEqual(guide.percentage, 100*fraction, accuracy: 0.0001)
                    XCTAssertGreaterThanOrEqual(guide.labelRect.minX, 0)
                    XCTAssertGreaterThanOrEqual(guide.labelRect.minY, 0)
                    XCTAssertLessThanOrEqual(guide.labelRect.maxX, size.width)
                    XCTAssertLessThanOrEqual(guide.labelRect.maxY, size.height)
                }
            }
        }
    }

    func testGuidePlacementDragToggleOrientationAndUndo() throws {
        let doc = Document(); let size = CGSize(width: 800, height: 600)
        doc.load(NSImage(size: size)); doc.tool = .guide
        let canvas = AnnotationCanvas(document: doc)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: p.x, y: 600-p.y), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func drag(_ start: CGPoint, _ end: CGPoint) {
            canvas.mouseDown(with: event(.leftMouseDown, start))
            canvas.mouseDragged(with: event(.leftMouseDragged, end))
            canvas.mouseUp(with: event(.leftMouseUp, end))
        }
        let p = CGPoint(x: 200, y: 150)
        canvas.mouseDown(with: event(.leftMouseDown, p)); canvas.mouseUp(with: event(.leftMouseUp, p))
        XCTAssertEqual(doc.marks.count, 1)
        XCTAssertEqual(doc.selectedGuide?.points, [CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 600)])
        drag(CGPoint(x: 200, y: 300), CGPoint(x: 400, y: 350))
        XCTAssertEqual(doc.marks.count, 1)
        XCTAssertEqual(try XCTUnwrap(GuideGeometry(doc.marks[0], imageSize: size)).label, "50%")
        doc.setGuideAxis(.horizontal)
        XCTAssertEqual(doc.marks[0].points, [CGPoint(x: 0, y: 300), CGPoint(x: 800, y: 300)])
        doc.setGuidePercentage(false); XCTAssertFalse(doc.marks[0].showsPercentage)
        doc.undo(); XCTAssertTrue(doc.marks[0].showsPercentage)
        doc.undo(); XCTAssertEqual(doc.marks[0].guideAxis, .vertical)
        doc.tool = .select
        drag(CGPoint(x: 400, y: 300), CGPoint(x: 1200, y: 300))
        XCTAssertEqual(try XCTUnwrap(GuideGeometry(doc.marks[0], imageSize: size)).label, "100%")
        doc.undo(); doc.undo(); doc.undo(); XCTAssertTrue(doc.marks.isEmpty)
        doc.redo(); XCTAssertEqual(doc.marks.count, 1)
    }

    func testGuideExportHasDotsAndOptionalPercentage() throws {
        let size = CGSize(width: 240, height: 180)
        let image = NSImage(size: size)
        image.lockFocus(); NSColor.white.setFill(); CGRect(origin: .zero, size: size).fill(); image.unlockFocus()
        for axis in GuideAxis.allCases {
            for scale: CGFloat in [1, 2] {
                var mark = Mark(tool: .guide, points: [], color: .red, width: 2)
                mark.guideAxis = axis
                mark = GuideGeometry.positioned(mark, at: CGPoint(x: 120, y: 90), imageSize: size)
                let guide = try XCTUnwrap(GuideGeometry(mark, imageSize: size))
                let labeled = try XCTUnwrap(NSBitmapImageRep(data: Renderer.export(image: image, marks: [mark], blurb: "", scale: scale)))
                mark.showsPercentage = false
                let plain = try XCTUnwrap(NSBitmapImageRep(data: Renderer.export(image: image, marks: [mark], blurb: "", scale: scale)))
                var dots = 0, gaps = 0, labelPixels = 0
                for step in 30..<80 {
                    let p = axis == .vertical ? CGPoint(x: 120, y: step) : CGPoint(x: step, y: 90)
                    let c = try XCTUnwrap(plain.colorAt(x: Int(p.x*scale), y: Int(p.y*scale))?.usingColorSpace(.deviceRGB))
                    if c.greenComponent < 0.5 { dots += 1 } else { gaps += 1 }
                }
                XCTAssertGreaterThan(dots, 3); XCTAssertGreaterThan(gaps, 3)
                let rect = guide.labelRect
                for y in Int(rect.minY*scale)..<Int(ceil(rect.maxY*scale)) {
                    for x in Int(rect.minX*scale)..<Int(ceil(rect.maxX*scale)) {
                        let a = try XCTUnwrap(labeled.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                        let b = try XCTUnwrap(plain.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                        if a.greenComponent < b.greenComponent - 0.1 { labelPixels += 1 }
                    }
                }
                XCTAssertGreaterThan(labelPixels, 20, "Percentage must disappear when disabled")
            }
        }
    }
}
