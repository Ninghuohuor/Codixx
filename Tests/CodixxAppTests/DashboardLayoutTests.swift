import XCTest
@testable import CodixxApp

final class DashboardLayoutTests: XCTestCase {
    func testAccountsDashboardUsesTwoColumnWidth() {
        XCTAssertEqual(DashboardLayout.accountColumnCount, 2)
        XCTAssertGreaterThanOrEqual(DashboardLayout.width, 540)
        XCTAssertEqual(DashboardLayout.popoverContentSize.width, DashboardLayout.width)
        XCTAssertEqual(DashboardLayout.accountCardMinHeight, 200)
        XCTAssertEqual(DashboardLayout.accountCardFooterSpacerMinLength, 0)
        XCTAssertLessThan(DashboardLayout.draggingAccountOpacity, 1)
        XCTAssertGreaterThanOrEqual(DashboardLayout.draggingAccountOpacity, 0.9)
        XCTAssertGreaterThan(DashboardLayout.draggingAccountScale, 1)
        XCTAssertLessThanOrEqual(DashboardLayout.draggingAccountScale, 1.01)
        XCTAssertGreaterThan(DashboardLayout.dragReleaseSettlingDelay, 0)
        XCTAssertGreaterThan(DashboardLayout.dragReleaseFadeDuration, 0)
        XCTAssertGreaterThan(DashboardLayout.dropTargetStrokeWidth, 0)
    }
}
