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

    func testLockedRetryCountAllowsInitialAttemptPlusRetries() {
        XCTAssertEqual(ThreadUsageReader.totalAttemptCount(lockedRetryCount: 3), 4)
        XCTAssertEqual(ThreadUsageReader.totalAttemptCount(lockedRetryCount: 0), 1)
        XCTAssertEqual(ThreadUsageReader.totalAttemptCount(lockedRetryCount: -1), 1)
    }

    func testReadsFractionalSecondISO8601Timestamps() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        try createDatabase(
            at: databaseURL,
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'fractional',
                    'Fractional Time',
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    42,
                    '2026-05-06T03:20:00.123Z',
                    '2026-05-06T03:30:00.456Z',
                    '/tmp/fractional.jsonl'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-06T03:35:00Z"))

        let snapshot = reader.readSnapshot(now: now)

        XCTAssertFalse(snapshot.isDegraded)
        XCTAssertEqual(snapshot.threads.first?.id, "fractional")
        XCTAssertEqual(snapshot.activeThread?.id, "fractional")
    }

    func testReadsUnixSecondIntegerTimestamps() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        try createDatabase(
            at: databaseURL,
            timestampColumnType: "INTEGER",
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'integer-time',
                    'Integer Time',
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    42,
                    1772881214,
                    1773255277,
                    '/tmp/integer.jsonl'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readSnapshot(now: Date(timeIntervalSince1970: 1_773_255_300))

        XCTAssertFalse(snapshot.isDegraded)
        XCTAssertEqual(snapshot.threads.first?.createdAt, Date(timeIntervalSince1970: 1_772_881_214))
        XCTAssertEqual(snapshot.threads.first?.updatedAt, Date(timeIntervalSince1970: 1_773_255_277))
        XCTAssertEqual(snapshot.activeThread?.id, "integer-time")
    }

    func testReadsDailyAndHourlyTokenUsageFromRolloutEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        let rolloutURL = directory.appendingPathComponent("rollout.jsonl")
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 12)))
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)

        try writeTokenUsageEvents(
            [
                (yesterday.addingTimeInterval(3_600), 1_000),
                (today.addingTimeInterval(600), 1_500),
                (today.addingTimeInterval(3_600), 1_800)
            ],
            to: rolloutURL
        )
        try createDatabase(
            at: databaseURL,
            timestampColumnType: "INTEGER",
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'usage',
                    'Usage',
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    1800,
                    \(Int(yesterday.timeIntervalSince1970)),
                    \(Int(today.addingTimeInterval(3_600).timeIntervalSince1970)),
                    '\(rolloutURL.path)'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readSnapshot(now: now)

        XCTAssertEqual(snapshot.dailyTokenUsage.first { calendar.isDate($0.start, inSameDayAs: yesterday) }?.tokens, 1_000)
        XCTAssertEqual(snapshot.dailyTokenUsage.first { calendar.isDate($0.start, inSameDayAs: today) }?.tokens, 800)
        XCTAssertEqual(snapshot.hourlyTokenUsage.first { $0.start == calendar.dateInterval(of: .hour, for: today.addingTimeInterval(600))?.start }?.tokens, 500)
        XCTAssertEqual(snapshot.hourlyTokenUsage.first { $0.start == calendar.dateInterval(of: .hour, for: today.addingTimeInterval(3_600))?.start }?.tokens, 300)
    }

    func testNullRequiredColumnsReturnDegradedSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        try createDatabase(
            at: databaseURL,
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'bad',
                    NULL,
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    42,
                    '2026-05-06T03:20:00Z',
                    '2026-05-06T03:30:00Z',
                    '/tmp/bad.jsonl'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readSnapshot(now: Date(timeIntervalSince1970: 0))

        XCTAssertTrue(snapshot.isDegraded)
        XCTAssertEqual(snapshot.totalTokens, 0)
    }

    func testNonIntegerTokenValuesReturnDegradedSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        try createDatabase(
            at: databaseURL,
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'bad-tokens',
                    'Bad Tokens',
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    'not-a-number',
                    '2026-05-06T03:20:00Z',
                    '2026-05-06T03:30:00Z',
                    '/tmp/bad-tokens.jsonl'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readSnapshot(now: Date(timeIntervalSince1970: 0))

        XCTAssertTrue(snapshot.isDegraded)
        XCTAssertEqual(snapshot.totalTokens, 0)
    }

    func testFutureUpdatedThreadIsNotActive() throws {
        let futureThread = ThreadUsage(
            id: "future",
            title: "Future",
            model: "gpt-5",
            reasoningEffort: "medium",
            tokensUsed: 100,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            rolloutPath: "/tmp/future.jsonl"
        )

        let snapshot = UsageAggregator.snapshot(
            threads: [futureThread],
            now: Date(timeIntervalSince1970: 100),
            activeWindow: 600
        )

        XCTAssertNil(snapshot.activeThread)
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

    private func createDatabase(at url: URL, timestampColumnType: String = "TEXT", inserts: [String]) throws {
        let createSQL = """
        CREATE TABLE threads(
            id TEXT PRIMARY KEY,
            title TEXT,
            source TEXT,
            model_provider TEXT,
            model TEXT,
            reasoning_effort TEXT,
            tokens_used INTEGER,
            created_at \(timestampColumnType),
            updated_at \(timestampColumnType),
            rollout_path TEXT
        );
        """
        for sql in [createSQL] + inserts {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = [url.path, sql]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }
    }

    private func writeTokenUsageEvents(_ events: [(Date, Int)], to url: URL) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = events.map { date, totalTokens in
            """
            {"timestamp":"\(formatter.string(from: date))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\(totalTokens)}}}}
            """
        }
        try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
    }
}
