import AppKit
import XCTest
@testable import SnapNote

final class CropTests: XCTestCase {
    override class func setUp() { super.setUp(); _ = NSApplication.shared }
    func source(scale: CGFloat) throws -> NSImage {
        let image = NSImage(size: CGSize(width: 100, height: 80))
        image.lockFocus(); NSColor.red.setFill(); CGRect(x:0,y:0,width:100,height:80).fill()
        NSColor.green.setFill(); CGRect(x:20,y:20,width:60,height:40).fill(); image.unlockFocus()
        let data = try Renderer.export(image:image,marks:[],blurb:"",scale:scale)
        let result = try XCTUnwrap(NSImage(data:data)); result.size = image.size; return result
    }
    func testCropThenExtendDiscardsOldPixelsAtBothResolutions() throws {
        for scale: CGFloat in [1,2] {
            let doc = Document(); doc.load(try source(scale:scale))
            doc.blurb = "Keep the footer"
            let mark = Mark(tool:.rectangle,points:[CGPoint(x:2,y:2),CGPoint(x:10,y:10)],color:.blue,width:4)
            doc.commit([mark])
            doc.cropRect = CGRect(x:20,y:20,width:60,height:40); try doc.applyCrop()
            XCTAssertTrue(doc.marks.isEmpty); XCTAssertEqual(doc.image?.size,CGSize(width:60,height:40))
            doc.cropRect = CGRect(x:-20,y:-20,width:100,height:80); try doc.applyCrop()
            XCTAssertEqual(doc.blurb,"Keep the footer"); XCTAssertEqual(doc.pixelScale,scale)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Renderer.export(image:try XCTUnwrap(doc.image),marks:[],blurb:"",scale:scale)))
            XCTAssertEqual(bitmap.pixelsWide,Int(100*scale)); XCTAssertEqual(bitmap.pixelsHigh,Int(80*scale))
            for p in [CGPoint(x:5,y:5),CGPoint(x:95,y:5),CGPoint(x:5,y:75),CGPoint(x:95,y:75)] {
                let c = try XCTUnwrap(bitmap.colorAt(x:Int(p.x*scale),y:Int(p.y*scale))?.usingColorSpace(.deviceRGB))
                XCTAssertLessThan(c.redComponent+c.greenComponent+c.blueComponent,0.01,"Trimmed pixels must never return when extended")
            }
            let green = try XCTUnwrap(bitmap.colorAt(x:Int(50*scale),y:Int(40*scale))?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(green.greenComponent,0.9)
            doc.undo(); XCTAssertEqual(doc.image?.size,CGSize(width:60,height:40))
            doc.undo(); XCTAssertEqual(doc.marks.first?.id,mark.id); XCTAssertEqual(doc.image?.size,CGSize(width:100,height:80))
            doc.redo(); doc.redo(); XCTAssertEqual(doc.image?.size,CGSize(width:100,height:80)); XCTAssertTrue(doc.marks.isEmpty)
        }
    }
    func testCancelNoOpAndInvalidCropPreserveHistory() throws {
        let doc = Document(); doc.load(try source(scale:1))
        doc.beginCrop(); try doc.applyCrop(); XCTAssertFalse(doc.canUndo)
        doc.beginCrop(); doc.cropRect = nil; XCTAssertFalse(doc.canUndo)
        doc.cropRect = CGRect(x:0,y:0,width:20000,height:20000)
        XCTAssertThrowsError(try doc.applyCrop()); XCTAssertNotNil(doc.cropRect); XCTAssertFalse(doc.canUndo)
        XCTAssertEqual(doc.image?.size,CGSize(width:100,height:80))
    }
    func testCropHandlesShrinkExtendAndMoveWithoutChangingImageBeforeApply() throws {
        let doc = Document(); doc.load(try source(scale:1)); doc.beginCrop()
        let view = CropView(document:doc)
        let window = NSWindow(contentRect:CGRect(x:0,y:0,width:800,height:600),styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView = view
        func event(_ type:NSEvent.EventType,_ p:CGPoint) -> NSEvent {
            let x = view.imageOrigin.x+p.x*view.zoom, y = view.imageOrigin.y+p.y*view.zoom
            return NSEvent.mouseEvent(with:type,location:CGPoint(x:x,y:600-y),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        }
        view.mouseDown(with:event(.leftMouseDown,CGPoint(x:0,y:40)))
        view.mouseDragged(with:event(.leftMouseDragged,CGPoint(x:20,y:40)))
        view.mouseUp(with:event(.leftMouseUp,CGPoint(x:20,y:40)))
        XCTAssertEqual(doc.cropRect,CGRect(x:20,y:0,width:80,height:80))
        view.mouseDown(with:event(.leftMouseDown,CGPoint(x:100,y:80)))
        view.mouseDragged(with:event(.leftMouseDragged,CGPoint(x:115,y:90)))
        view.mouseUp(with:event(.leftMouseUp,CGPoint(x:115,y:90)))
        XCTAssertEqual(doc.cropRect,CGRect(x:20,y:0,width:95,height:90))
        XCTAssertEqual(doc.image?.size,CGSize(width:100,height:80))
    }
}
