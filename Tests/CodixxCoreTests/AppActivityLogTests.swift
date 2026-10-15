import XCTest
@testable import CodixxCore

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

    func testUnchangedLoadsDoNotReadOrDecodeHistoryAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let now = Date()
        let log = AppActivityLog(paths: paths, retention: .init(now: { now }))
        for index in 0..<100 {
            try log.append(AppLogEvent(timestamp: now.addingTimeInterval(Double(index)), kind: .apiBalanceRefreshed))
        }
        let expected = try log.loadEvents()
        let bytesRead = log.bytesRead
        let decoded = log.decodedEventCount
        for _ in 0..<100 { XCTAssertEqual(try log.loadEvents(), expected) }
        XCTAssertEqual(log.bytesRead, bytesRead)
        XCTAssertEqual(log.decodedEventCount, decoded)
    }

    func testAppendPreservesFileAndDecodesOnlyTheNewRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let now = Date()
        let log = AppActivityLog(paths: paths, retention: .init(now: { now }))
        try log.append(AppLogEvent(timestamp: now, kind: .accountSaved))
        _ = try log.loadEvents()
        let original = try Data(contentsOf: paths.appActivityJSONL)
        let number = try FileManager.default.attributesOfItem(atPath: paths.appActivityJSONL.path)[.systemFileNumber] as? NSNumber
        let decoded = log.decodedEventCount
        let bytesRead = log.bytesRead
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: paths.appActivityJSONL.path)
        let next = AppLogEvent(timestamp: now.addingTimeInterval(1), kind: .apiBalanceRefreshed)
        try log.append(next)
        XCTAssertEqual(try log.loadEvents().last, next)
        XCTAssertEqual(log.decodedEventCount - decoded, 1)
        XCTAssertLessThan(log.bytesRead - bytesRead, 512)
        XCTAssertTrue(try Data(contentsOf: paths.appActivityJSONL).starts(with: original))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: paths.appActivityJSONL.path)[.systemFileNumber] as? NSNumber, number)
        let permissions = try FileManager.default.attributesOfItem(atPath: paths.appActivityJSONL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testCachedReaderHandlesPartialRecordsAndExternalReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let now = Date()
        let log = AppActivityLog(paths: paths, retention: .init(now: { now }))
        let original = AppLogEvent(timestamp: now, kind: .accountSaved)
        try log.append(original)
        XCTAssertEqual(try log.loadEvents(), [original])
        let next = AppLogEvent(timestamp: now.addingTimeInterval(1), kind: .accountRenamed, accountAlias: "示例账号")
        var data = try JSONEncoder().encode(next)
        data.append(0x0a)
        let half = data.count / 2
        let handle = try FileHandle(forWritingTo: paths.appActivityJSONL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data.prefix(half))
        XCTAssertEqual(try log.loadEvents(), [original])
        try handle.write(contentsOf: data.dropFirst(half))
        XCTAssertEqual(try log.loadEvents(), [original, next])

        let replacement = AppLogEvent(timestamp: now.addingTimeInterval(2), kind: .accountDeleted)
        // Valid legacy JSONL may omit the trailing newline.
        try JSONEncoder().encode(replacement).write(to: paths.appActivityJSONL, options: .atomic)
        XCTAssertEqual(try log.loadEvents(), [replacement])
        let appended = AppLogEvent(timestamp: now.addingTimeInterval(3), kind: .accountSaved)
        try log.append(appended)
        XCTAssertEqual(try log.loadEvents(), [replacement, appended])
    }

    func testCacheSurvivesRotationAndPrunesExpiredEventsOnAppend() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        var now = Date()
        let log = AppActivityLog(paths: paths, retention: .init(maximumAge: 60, maximumBytes: 300, now: { now }))
        for index in 0..<20 {
            let event = AppLogEvent(timestamp: now.addingTimeInterval(Double(index)), kind: .accountSaved)
            try log.append(event)
            XCTAssertEqual(try log.loadEvents().last, event)
        }
        let reloaded = AppActivityLog(paths: paths, retention: .init(maximumAge: 60, maximumBytes: 300, now: { now }))
        XCTAssertEqual(try log.loadEvents(), try reloaded.loadEvents())
        now = now.addingTimeInterval(100)
        try log.append(AppLogEvent(timestamp: now.addingTimeInterval(-200), kind: .accountSaved))
        XCTAssertTrue(try log.loadEvents().isEmpty)
    }

    func testReaderPreservesHistoryRetainedByAWriterWithADifferentClock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let historicalNow = Date(timeIntervalSince1970: 1_778_000_000)
        let writer = AppActivityLog(paths: paths, retention: .init(now: { historicalNow }))
        let event = AppLogEvent(timestamp: historicalNow, kind: .accountSaved)
        try writer.append(event)
        XCTAssertEqual(try AppActivityLog(paths: paths).loadEvents(), [event])
    }

    func testConcurrentAppendAndReadPreserveEveryEvent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let now = Date()
        let log = AppActivityLog(paths: paths, retention: .init(now: { now }))
        DispatchQueue.concurrentPerform(iterations: 16) { index in
            try? log.append(AppLogEvent(timestamp: now.addingTimeInterval(Double(index)), kind: .accountSaved, accountAlias: "Example \(index)"))
            _ = try? log.loadEvents()
        }
        let events = try log.loadEvents()
        XCTAssertEqual(events.count, 16)
        XCTAssertEqual(Set(events.compactMap(\.accountAlias)).count, 16)
        XCTAssertEqual(try AppActivityLog(paths: paths, retention: .init(now: { now })).loadEvents(), events)
    }
}
