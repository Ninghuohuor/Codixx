import XCTest
@testable import CodixxApp
import CodixxCore

final class AppLogViewModelTests: XCTestCase {
    func testTimestampFormatterShowsTimeFirstForToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3_600))
        let formatter = AppLogTimestampFormatter(calendar: calendar, timeZone: calendar.timeZone)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-12T10:00:00Z"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-12T09:54:38Z"))

        XCTAssertEqual(formatter.string(for: date, now: now), "17:54:38")
    }

    func testTimestampFormatterShowsDateForOlderEntries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3_600))
        let formatter = AppLogTimestampFormatter(calendar: calendar, timeZone: calendar.timeZone)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-12T10:00:00Z"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-11T09:54:38Z"))

        XCTAssertEqual(formatter.string(for: date, now: now), "05/11 17:54")
    }

    func testErrorFilterIncludesFailedSwitchesAndErrorEvents() {
        let failedSwitch = AppLogEntry(
            id: "switch",
            timestamp: Date(timeIntervalSince1970: 10),
            category: .switching,
            title: "Failed",
            detail: nil,
            status: "Error",
            iconName: "exclamationmark.triangle.fill",
            severity: .error
        )
        let accountEvent = AppLogEntry(
            id: "account",
            timestamp: Date(timeIntervalSince1970: 20),
            category: .account,
            title: "Saved",
            detail: nil,
            status: nil,
            iconName: "person.crop.circle.badge.checkmark",
            severity: .normal
        )
        let errorEvent = AppLogEntry(
            id: "error",
            timestamp: Date(timeIntervalSince1970: 30),
            category: .system,
            title: "Restart failed",
            detail: nil,
            status: nil,
            iconName: "exclamationmark.triangle.fill",
            severity: .error
        )

        let filtered = AppLogEntry.filtered([failedSwitch, accountEvent, errorEvent], by: .error)

        XCTAssertEqual(filtered.map(\.id), ["switch", "error"])
    }

    func testEntriesCombineActivityAndSwitchLogsNewestFirst() {
        let accountEvent = AppLogEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: Date(timeIntervalSince1970: 20),
            kind: .accountSaved,
            accountId: nil,
            accountAlias: "Pro",
            secondaryAlias: nil,
            detail: nil
        )
        let switchEvent = SwitchAuditEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            timestamp: Date(timeIntervalSince1970: 10),
            trigger: .manual,
            sourceAccountId: nil,
            sourceAlias: "Plus",
            targetAccountId: nil,
            targetAlias: "Pro",
            sourcePrimaryUsedPercent: nil,
            sourceSecondaryUsedPercent: nil,
            threshold: nil,
            result: .success,
            errorSummary: nil,
            backupPath: nil
        )

        let entries = AppLogEntry.entries(
            switchEvents: [switchEvent],
            appEvents: [accountEvent],
            strings: CodixxStrings(language: .english)
        )

        XCTAssertEqual(entries.map(\.id), ["app-00000000-0000-0000-0000-000000000001", "switch-00000000-0000-0000-0000-000000000002"])
        XCTAssertEqual(entries.map(\.category), [.account, .switching])
    }
}
