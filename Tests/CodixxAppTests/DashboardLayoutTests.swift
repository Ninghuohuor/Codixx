import XCTest
@testable import CodixxApp

final class DashboardLayoutTests: XCTestCase {
    func testAccountsDashboardUsesTwoColumnWidth() {
        XCTAssertEqual(DashboardLayout.accountColumnCount, 2)
        XCTAssertGreaterThanOrEqual(DashboardLayout.width, 540)
        XCTAssertEqual(DashboardLayout.popoverContentSize.width, DashboardLayout.width)
        XCTAssertEqual(DashboardLayout.accountCardMinHeight, 200)
        XCTAssertEqual(DashboardLayout.accountCardFooterSpacerMinLength, 0)
        XCTAssertEqual(DashboardLayout.draggingAccountOpacity, 1)
        XCTAssertGreaterThan(DashboardLayout.draggingAccountScale, 1)
        XCTAssertLessThanOrEqual(DashboardLayout.draggingAccountScale, 1.04)
        XCTAssertGreaterThan(DashboardLayout.dragReleaseSettlingDelay, 0)
        XCTAssertGreaterThan(DashboardLayout.dragReleaseFadeDuration, 0)
        XCTAssertGreaterThan(DashboardLayout.dropTargetStrokeWidth, 0)
    }

    func testAccountDragGridCalculatesTwoColumnFrames() {
        let frame0 = AccountDragGridLayout.frame(for: 0, containerWidth: 532)
        let frame1 = AccountDragGridLayout.frame(for: 1, containerWidth: 532)
        let frame2 = AccountDragGridLayout.frame(for: 2, containerWidth: 532)

        XCTAssertEqual(frame0.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(frame0.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(frame0.width, 259, accuracy: 0.001)
        XCTAssertEqual(frame1.origin.x, 273, accuracy: 0.001)
        XCTAssertEqual(frame1.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(frame2.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(frame2.origin.y, 214, accuracy: 0.001)
        XCTAssertEqual(AccountDragGridLayout.contentHeight(itemCount: 3), 414, accuracy: 0.001)
    }

    func testAccountDragGridChoosesNearestInsertionSlot() {
        XCTAssertEqual(
            AccountDragGridLayout.insertionIndex(
                for: CGPoint(x: 20, y: 20),
                itemCount: 3,
                containerWidth: 532
            ),
            0
        )
        XCTAssertEqual(
            AccountDragGridLayout.insertionIndex(
                for: CGPoint(x: 520, y: 20),
                itemCount: 3,
                containerWidth: 532
            ),
            1
        )
        XCTAssertEqual(
            AccountDragGridLayout.insertionIndex(
                for: CGPoint(x: 520, y: 235),
                itemCount: 3,
                containerWidth: 532
            ),
            3
        )
    }

    func testAccountDragGridReservesLandingSlot() {
        XCTAssertEqual(
            AccountDragGridLayout.displaySlotIndex(forVisibleIndex: 0, reservedInsertionIndex: nil),
            0
        )
        XCTAssertEqual(
            AccountDragGridLayout.displaySlotIndex(forVisibleIndex: 0, reservedInsertionIndex: 1),
            0
        )
        XCTAssertEqual(
            AccountDragGridLayout.displaySlotIndex(forVisibleIndex: 1, reservedInsertionIndex: 1),
            2
        )
        XCTAssertEqual(
            AccountDragGridLayout.displaySlotIndex(forVisibleIndex: 2, reservedInsertionIndex: 1),
            3
        )
    }
}
