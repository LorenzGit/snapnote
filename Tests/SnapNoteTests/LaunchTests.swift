import AppKit
import Carbon
import XCTest
@testable import SnapNote

final class LaunchTests: XCTestCase {
    override class func setUp() { super.setUp(); _ = NSApplication.shared }

    private func launchEvent(reason: AEKeyword? = nil, id: AEEventID = kAEOpenApplication) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: id, targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let reason { event.setParam(NSAppleEventDescriptor(enumCode: reason), forKeyword: keyAEPropData) }
        return event
    }

    func testAutomaticLaunchStaysHiddenButReopenShowsEditor() {
        for reason in [keyAELaunchedAsLogInItem, keyAELaunchedAsServiceItem] {
            let delegate = AppDelegate()
            delegate.window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 680, height: 440), styleMask: [.titled], backing: .buffered, defer: false)
            delegate.window.isReleasedWhenClosed = false
            defer { delegate.window.close() }
            delegate.presentAtLaunch(event: launchEvent(reason: reason))
            XCTAssertFalse(delegate.window.isVisible)
            XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
            XCTAssertTrue(delegate.window.isVisible)
        }
    }

    func testManualLaunchShowsEditor() {
        for event in [nil, launchEvent(), launchEvent(reason: keyAELaunchedAsLogInItem, id: kAEReopenApplication)] {
            let delegate = AppDelegate()
            delegate.window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 680, height: 440), styleMask: [.titled], backing: .buffered, defer: false)
            delegate.window.isReleasedWhenClosed = false
            defer { delegate.window.close() }
            delegate.presentAtLaunch(event: event)
            XCTAssertTrue(delegate.window.isVisible)
        }
    }
}
