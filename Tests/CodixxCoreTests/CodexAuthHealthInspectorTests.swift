import XCTest
import SQLite3
@testable import CodixxCore

final class CodexAuthHealthInspectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_900_000)

    func testMissingAuthFileIsNotChatGPT() throws {
        let fixture = try InspectorFixture(now: now)

        XCTAssertEqual(fixture.inspect(), .notChatGPT)
    }

    func testAPIKeyAuthIsNotChatGPT() throws {
        let fixture = try InspectorFixture(now: now)
        try fixture.writeAuth(mode: "apikey", modifiedAt: now)

        XCTAssertEqual(fixture.inspect(), .notChatGPT)
    }

    func testChatGPTAuthWithoutLogDatabaseIsHealthy() throws {
        let fixture = try InspectorFixture(now: now)
        try fixture.writeAuth(mode: "chatgpt", modifiedAt: now)

        XCTAssertEqual(fixture.inspect(), .healthy)
    }

    func testRevokedRefreshTokenAfterLoginIsReported() throws {
        let fixture = try InspectorFixture(now: now)
        try fixture.writeAuth(mode: "chatgpt", modifiedAt: now.addingTimeInterval(-3_600))
        try fixture.writeLogs([
            (
                ts: now.addingTimeInterval(-60),
                level: "ERROR",
                body: #"Failed to refresh token: 401 Unauthorized: "code": "refresh_token_invalidated""#
            )
        ])

        XCTAssertEqual(
            fixture.inspect(),
            .credentialRevoked(since: now.addingTimeInterval(-60))
        )
    }

    func testRevokedAccessTokenAfterLoginIsReported() throws {
        let fixture = try InspectorFixture(now: now)
        try fixture.writeAuth(mode: "chatgpt", modifiedAt: now.addingTimeInterval(-600))
        try fixture.writeLogs([
            (
                ts: now.addingTimeInterval(-120),
                level: "ERROR",
                body: "401 Unauthorized: Encountered invalidated oauth token for user, auth error code: token_revoked"
            )
        ])

        XCTAssertEqual(
            fixture.inspect(),
            .credentialRevoked(since: now.addingTimeInterval(-120))
        )
    }

    /// 重新登录会重写 `auth.json`；比它更早的错误说明已经被新的登录覆盖。
    func testRevocationOlderThanAuthFileIsIgnored() throws {
        let fixture = try InspectorFixture(now: now)
        try fixture.writeAuth(mode: "chatgpt", modifiedAt: now.addingTimeInterval(-30))
        try fixture.writeLogs([
            (ts: now.addingTimeInterval(-600), level: "ERROR", body: "auth error code: token_revoked")
        ])

        XCTAssertEqual(fixture.inspect(), .healthy)
    }

    func testRevocationOlderThanLookbackWindowIsIgnored() throws {
        let fixture = try InspectorFixture(now: now)
        let longAgo = now.addingTimeInterval(-CodexAuthHealthInspector.maximumLogLookback - 3_600)
        try fixture.writeAuth(mode: "chatgpt", modifiedAt: longAgo.addingTimeInterval(-3_600))
        try fixture.writeLogs([
            (ts: longAgo, level: "ERROR", body: "auth error code: token_revoked")
        ])

        XCTAssertEqual(fixture.inspect(), .healthy)
    }

    func testNonErrorLogRowsDoNotCount() throws {
        let fixture = try InspectorFixture(now: now)
        try fixture.writeAuth(mode: "chatgpt", modifiedAt: now.addingTimeInterval(-3_600))
        try fixture.writeLogs([
            (ts: now.addingTimeInterval(-60), level: "WARN", body: "auth error code: token_revoked")
        ])

        XCTAssertEqual(fixture.inspect(), .healthy)
    }

    func testLatestLogDatabaseWins() throws {
        let fixture = try InspectorFixture(now: now)
        try fixture.writeLogs([], version: 1)
        try fixture.writeLogs([], version: 7)

        XCTAssertEqual(
            fixture.paths.latestLogsDatabaseURL().lastPathComponent,
            "logs_7.sqlite"
        )
    }
}

private final class InspectorFixture {
    let paths: CodixxPaths
    private let directory: URL
    private let inspector: CodexAuthHealthInspector

    init(now: Date) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        inspector = CodexAuthHealthInspector(paths: paths, now: { now })
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func inspect() -> CodexAuthHealth {
        inspector.inspect()
    }

    func writeAuth(mode: String, modifiedAt: Date) throws {
        let data = try JSONSerialization.data(withJSONObject: ["auth_mode": mode, "account_id": "test"])
        try data.write(to: paths.authJSON)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: paths.authJSON.path
        )
    }

    func writeLogs(_ rows: [(ts: Date, level: String, body: String)], version: Int = 2) throws {
        let url = paths.codexHome.appendingPathComponent("logs_\(version).sqlite")
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        XCTAssertEqual(openResult, SQLITE_OK)
        guard let database else { return }
        defer { sqlite3_close(database) }

        let schema = """
        CREATE TABLE logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            ts_nanos INTEGER,
            level TEXT NOT NULL,
            target TEXT,
            feedback_log_body TEXT,
            module_path TEXT,
            file TEXT,
            line INTEGER,
            thread_id TEXT,
            process_uuid TEXT,
            estimated_bytes INTEGER
        )
        """
        XCTAssertEqual(sqlite3_exec(database, schema, nil, nil, nil), SQLITE_OK)

        for row in rows {
            var statement: OpaquePointer?
            let prepareResult = sqlite3_prepare_v2(
                database,
                "INSERT INTO logs (ts, level, feedback_log_body) VALUES (?, ?, ?)",
                -1,
                &statement,
                nil
            )
            XCTAssertEqual(prepareResult, SQLITE_OK)
            guard let statement else { continue }
            sqlite3_bind_int64(statement, 1, Int64(row.ts.timeIntervalSince1970))
            sqlite3_bind_text(statement, 2, row.level, -1, sqliteTransient)
            sqlite3_bind_text(statement, 3, row.body, -1, sqliteTransient)
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            sqlite3_finalize(statement)
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
