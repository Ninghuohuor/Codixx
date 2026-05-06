import XCTest
@testable import CodixxCore

final class ThreadUsageReaderTests: XCTestCase {
    func testReadsThreadUsageSnapshotFromFixtureDatabase() throws {
        let databaseURL = fixtureDatabaseURL()
        let reader = ThreadUsageReader(databaseURL: databaseURL)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-06T03:35:00Z"))

        let snapshot = reader.readSnapshot(now: now)

        XCTAssertFalse(snapshot.isDegraded)
        XCTAssertNil(snapshot.errorSummary)
        XCTAssertEqual(snapshot.threads.map(\.id), ["t2", "t1"])
        XCTAssertEqual(snapshot.totalTokens, 4_600)
        XCTAssertEqual(snapshot.activeThread?.id, "t2")
        XCTAssertEqual(snapshot.threads.first?.title, "Build Menu")
        XCTAssertEqual(snapshot.threads.first?.model, "gpt-5")
        XCTAssertEqual(snapshot.threads.first?.reasoningEffort, "high")
        XCTAssertEqual(snapshot.threads.first?.tokensUsed, 3_400)
        XCTAssertEqual(snapshot.threads.first?.rolloutPath, "/tmp/t2.jsonl")
    }

    func testActiveThreadIsNilWhenNewestThreadIsOlderThanTenMinutes() throws {
        let databaseURL = fixtureDatabaseURL()
        let reader = ThreadUsageReader(databaseURL: databaseURL)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-06T03:41:00Z"))

        let snapshot = reader.readSnapshot(now: now)

        XCTAssertEqual(snapshot.threads.map(\.id), ["t2", "t1"])
        XCTAssertEqual(snapshot.activeThread?.id, nil)
    }

    func testIncompatibleSchemaReturnsDegradedSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        try createIncompatibleDatabase(at: databaseURL)
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readSnapshot(now: Date(timeIntervalSince1970: 0))

        XCTAssertTrue(snapshot.isDegraded)
        XCTAssertEqual(snapshot.threads, [])
        XCTAssertEqual(snapshot.totalTokens, 0)
        XCTAssertNil(snapshot.activeThread)
        XCTAssertNotNil(snapshot.errorSummary)
    }

    private func fixtureDatabaseURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/codex-home/state_5.sqlite")
    }

    private func createIncompatibleDatabase(at url: URL) throws {
        let sql = "CREATE TABLE threads(id TEXT PRIMARY KEY, updated_at TEXT);"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
