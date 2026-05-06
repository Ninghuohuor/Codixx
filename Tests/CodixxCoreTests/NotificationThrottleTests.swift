import XCTest
@testable import CodixxCore

final class NotificationThrottleTests: XCTestCase {
    func testQuotaWarningAtEightyPercentIsSentOncePerFiveHourWindow() {
        var throttle = NotificationThrottle()
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(throttle.shouldSend(.quotaWarning(accountId: "account-1", quotaKind: .primary), at: now))
        XCTAssertFalse(throttle.shouldSend(.quotaWarning(accountId: "account-1", quotaKind: .primary), at: now.addingTimeInterval(4 * 60 * 60 + 59 * 60)))
        XCTAssertTrue(throttle.shouldSend(.quotaWarning(accountId: "account-1", quotaKind: .primary), at: now.addingTimeInterval(5 * 60 * 60)))
    }

    func testSameTypeNotificationsAreSuppressedWithinFiveMinutes() {
        var throttle = NotificationThrottle()
        let now = Date(timeIntervalSince1970: 2_000)

        XCTAssertTrue(throttle.shouldSend(.generic(type: "switch-completed"), at: now))
        XCTAssertFalse(throttle.shouldSend(.generic(type: "switch-completed"), at: now.addingTimeInterval(4 * 60 + 59)))
        XCTAssertTrue(throttle.shouldSend(.generic(type: "switch-completed"), at: now.addingTimeInterval(5 * 60)))
    }

    func testProtectionModeNotificationIsSentOnlyOnFirstEntry() {
        var throttle = NotificationThrottle()
        let now = Date(timeIntervalSince1970: 3_000)

        XCTAssertTrue(throttle.shouldSend(.protectionModeEntered, at: now))
        XCTAssertFalse(throttle.shouldSend(.protectionModeEntered, at: now.addingTimeInterval(24 * 60 * 60)))
    }
}
