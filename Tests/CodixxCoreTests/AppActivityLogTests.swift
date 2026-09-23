import XCTest
import CodixxCore

final class AppActivityLogTests: XCTestCase {
    func testAppendAndLoadEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let log = AppActivityLog(paths: paths, retention: .init(now: { now }))
        let event = AppLogEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: now,
            kind: .accountSaved,
            accountId: nil,
            accountAlias: "Pro",
            secondaryAlias: nil,
            detail: nil
        )

        try log.append(event)

        XCTAssertEqual(try log.loadEvents(), [event])
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.appActivityJSONL.path))
    }

    func testLoadEventsSortsByTimestampAscending() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let log = AppActivityLog(paths: paths, retention: .init(now: { now }))
        let newer = AppLogEvent(timestamp: now, kind: .accountDeleted, accountAlias: "Pro")
        let older = AppLogEvent(timestamp: now.addingTimeInterval(-100), kind: .authImported, accountAlias: "Plus")

        try log.append(newer)
        try log.append(older)

        XCTAssertEqual(try log.loadEvents().map(\.accountAlias), ["Plus", "Pro"])
    }

    func testAppendRotatesAndRetainsOnlyRecentEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let log = AppActivityLog(
            paths: paths,
            retention: .init(maximumAge: 86_400, maximumBytes: 300, now: { now })
        )

        try log.append(AppLogEvent(timestamp: now.addingTimeInterval(-90_000), kind: .accountSaved, accountAlias: "Expired"))
        for index in 0..<20 {
            try log.append(AppLogEvent(timestamp: now.addingTimeInterval(Double(index)), kind: .apiBalanceRefreshed, accountAlias: "Account \(index)"))
        }

        let events = try log.loadEvents()
        XCTAssertFalse(events.contains { $0.accountAlias == "Expired" })
        XCTAssertEqual(events.last?.accountAlias, "Account 19")
        XCTAssertLessThan(events.count, 20)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.applicationSupport.appendingPathComponent("app_activity.1.jsonl").path))
    }
}
