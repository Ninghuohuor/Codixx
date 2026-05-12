import AppKit
import XCTest
@testable import CodixxApp

@MainActor
final class PopoverDismissalPolicyTests: XCTestCase {
    func testOutsideClickClosesPopover() {
        let popoverWindow = NSWindow()
        let statusWindow = NSWindow()
        let unrelatedWindow = NSWindow()

        XCTAssertTrue(PopoverDismissalPolicy.shouldClosePopover(
            eventWindow: nil,
            popoverWindow: popoverWindow,
            statusButtonWindow: statusWindow
        ))
        XCTAssertTrue(PopoverDismissalPolicy.shouldClosePopover(
            eventWindow: unrelatedWindow,
            popoverWindow: popoverWindow,
            statusButtonWindow: statusWindow
        ))
    }

    func testPopoverAndRelatedClicksDoNotClosePopover() {
        let popoverWindow = NSWindow()
        let statusWindow = NSWindow()
        let childPanel = NSPanel()
        popoverWindow.addChildWindow(childPanel, ordered: .above)
        defer { popoverWindow.removeChildWindow(childPanel) }

        XCTAssertFalse(PopoverDismissalPolicy.shouldClosePopover(
            eventWindow: popoverWindow,
            popoverWindow: popoverWindow,
            statusButtonWindow: statusWindow
        ))
        XCTAssertFalse(PopoverDismissalPolicy.shouldClosePopover(
            eventWindow: statusWindow,
            popoverWindow: popoverWindow,
            statusButtonWindow: statusWindow
        ))
        XCTAssertFalse(PopoverDismissalPolicy.shouldClosePopover(
            eventWindow: childPanel,
            popoverWindow: popoverWindow,
            statusButtonWindow: statusWindow
        ))
    }
}
