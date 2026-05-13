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
        XCTAssertEqual(snapshot.threads.first?.cwd, "")
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
                    '/tmp/project',
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
        XCTAssertEqual(snapshot.threads.first?.cwd, "/tmp/project")
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
                    '/tmp/project',
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
                    '\(directory.path)',
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

    func testThreadTotalsUseEffectiveTokensWhenRolloutContainsCachedInput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        let rolloutURL = directory.appendingPathComponent("rollout.jsonl")
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-07T12:00:00Z"))

        try writeDetailedTokenUsageEvents(
            [
                (now.addingTimeInterval(-600), 346_537_771, 315_228_160, 492_495)
            ],
            to: rolloutURL
        )
        try createDatabase(
            at: databaseURL,
            timestampColumnType: "INTEGER",
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'cached-heavy',
                    'Cached Heavy',
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    347030266,
                    '\(directory.path)',
                    \(Int(now.addingTimeInterval(-3_600).timeIntervalSince1970)),
                    \(Int(now.addingTimeInterval(-600).timeIntervalSince1970)),
                    '\(rolloutURL.path)'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readSnapshot(now: now)

        XCTAssertEqual(snapshot.threads.first?.tokensUsed, 31_802_106)
        XCTAssertEqual(snapshot.totalTokens, 31_802_106)
    }

    func testActivitySnapshotUsesEffectiveTokensWhenRolloutContainsCachedInput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        let rolloutURL = directory.appendingPathComponent("rollout.jsonl")
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-07T12:00:00Z"))

        try writeDetailedTokenUsageEvents(
            [
                (now.addingTimeInterval(-600), 10_000, 8_000, 750)
            ],
            to: rolloutURL
        )
        try createDatabase(
            at: databaseURL,
            timestampColumnType: "INTEGER",
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'active-cached',
                    'Active Cached',
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    10750,
                    '\(directory.path)',
                    \(Int(now.addingTimeInterval(-3_600).timeIntervalSince1970)),
                    \(Int(now.addingTimeInterval(-600).timeIntervalSince1970)),
                    '\(rolloutURL.path)'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readActivitySnapshot(now: now)

        XCTAssertEqual(snapshot.threads.first?.tokensUsed, 2_750)
        XCTAssertEqual(snapshot.totalTokens, 2_750)

        let lightweightSnapshot = reader.readActivitySnapshot(now: now, includeEffectiveTokenCounts: false)

        XCTAssertEqual(lightweightSnapshot.threads.first?.tokensUsed, 10_750)
        XCTAssertEqual(lightweightSnapshot.totalTokens, 10_750)
    }

    func testReadsCurrentAndPreviousMonthTokenUsageFromRolloutEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        let rolloutURL = directory.appendingPathComponent("rollout.jsonl")
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12)))
        let currentMonth = try XCTUnwrap(calendar.dateInterval(of: .month, for: now)?.start)
        let previousMonth = try XCTUnwrap(calendar.date(byAdding: .month, value: -1, to: currentMonth))

        try writeTokenUsageEvents(
            [
                (previousMonth.addingTimeInterval(86_400), 1_000),
                (previousMonth.addingTimeInterval(2 * 86_400), 1_500),
                (currentMonth.addingTimeInterval(3_600), 2_000),
                (currentMonth.addingTimeInterval(2 * 3_600), 2_700)
            ],
            to: rolloutURL
        )
        try createDatabase(
            at: databaseURL,
            timestampColumnType: "INTEGER",
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'monthly-usage',
                    'Monthly Usage',
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    2700,
                    '\(directory.path)',
                    \(Int(previousMonth.timeIntervalSince1970)),
                    \(Int(currentMonth.addingTimeInterval(2 * 3_600).timeIntervalSince1970)),
                    '\(rolloutURL.path)'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readSnapshot(now: now)

        XCTAssertEqual(snapshot.monthlyTokenUsage.first { $0.start == previousMonth }?.tokens, 1_500)
        XCTAssertEqual(snapshot.monthlyTokenUsage.first { $0.start == currentMonth }?.tokens, 1_200)
    }

    func testMonthlyUsageFallsBackToThreadTokensWhenRolloutHasNoTokenEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        let rolloutURL = directory.appendingPathComponent("rollout.jsonl")
        try "".write(to: rolloutURL, atomically: true, encoding: .utf8)
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12)))
        let today = calendar.startOfDay(for: now)
        let currentMonth = try XCTUnwrap(calendar.dateInterval(of: .month, for: now)?.start)

        try createDatabase(
            at: databaseURL,
            timestampColumnType: "INTEGER",
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'monthly-fallback',
                    'Monthly Fallback',
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    9000,
                    '\(directory.path)',
                    \(Int(today.addingTimeInterval(600).timeIntervalSince1970)),
                    \(Int(today.addingTimeInterval(1_200).timeIntervalSince1970)),
                    '\(rolloutURL.path)'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readSnapshot(now: now)

        XCTAssertEqual(snapshot.monthlyTokenUsage.first { $0.start == currentMonth }?.tokens, 9_000)
        XCTAssertEqual(snapshot.dailyTokenUsage.first { calendar.isDate($0.start, inSameDayAs: today) }?.tokens, 0)
    }

    func testMonthlyUsageFallsBackForHistoricalThreadsWithoutEventsInInterval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        let rolloutURL = directory.appendingPathComponent("rollout.jsonl")
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12)))
        let previousMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        let previousMonthThreadStart = previousMonth.addingTimeInterval(2 * 86_400)
        let previousMonthThreadEnd = previousMonth.addingTimeInterval(3 * 86_400)

        try writeTokenUsageEvents(
            [
                (previousMonthThreadStart.addingTimeInterval(600), 100)
            ],
            to: rolloutURL
        )
        try createDatabase(
            at: databaseURL,
            timestampColumnType: "INTEGER",
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'historical-monthly',
                    'Historical Monthly',
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    9000,
                    '\(directory.path)',
                    \(Int(previousMonthThreadStart.timeIntervalSince1970)),
                    \(Int(previousMonthThreadEnd.timeIntervalSince1970)),
                    '\(rolloutURL.path)'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readSnapshot(now: now)

        XCTAssertEqual(snapshot.monthlyTokenUsage.first { $0.start == previousMonth }?.tokens, 100)
    }

    func testTrendCachePersistsParsedTokenEventsAcrossReaders() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        let rolloutURL = directory.appendingPathComponent("rollout.jsonl")
        let paths = CodixxPaths(home: directory)
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12)))
        let today = calendar.startOfDay(for: now)

        try writeTokenUsageEvents(
            [
                (today.addingTimeInterval(600), 1_000),
                (today.addingTimeInterval(1_200), 1_500)
            ],
            to: rolloutURL
        )
        try createDatabase(
            at: databaseURL,
            timestampColumnType: "INTEGER",
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'cached-events',
                    'Cached Events',
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    1500,
                    '\(directory.path)',
                    \(Int(today.timeIntervalSince1970)),
                    \(Int(today.addingTimeInterval(1_200).timeIntervalSince1970)),
                    '\(rolloutURL.path)'
                );
                """
            ]
        )

        let firstReader = ThreadUsageReader(
            databaseURL: databaseURL,
            trendCacheStore: TrendCacheStore(paths: paths)
        )
        _ = firstReader.readSnapshot(now: now)

        let cacheState = try TrendCacheStore(paths: paths).load()
        XCTAssertEqual(cacheState.entriesByPath[rolloutURL.resolvingSymlinksInPath().path]?.events.count, 2)

        let secondReader = ThreadUsageReader(
            databaseURL: databaseURL,
            trendCacheStore: TrendCacheStore(paths: paths)
        )
        let secondSnapshot = secondReader.readSnapshot(now: now)

        XCTAssertEqual(secondSnapshot.dailyTokenUsage.first { calendar.isDate($0.start, inSameDayAs: today) }?.tokens, 1_500)
    }

    func testReadsAccountUsageSummariesFromAccountWindows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        let rolloutURL = directory.appendingPathComponent("rollout.jsonl")
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12)))
        let today = calendar.startOfDay(for: now)
        let accountA = UUID()
        let accountB = UUID()

        try writeTokenUsageEvents(
            [
                (today.addingTimeInterval(600), 1_000),
                (today.addingTimeInterval(1_200), 1_500),
                (today.addingTimeInterval(1_800), 2_200)
            ],
            to: rolloutURL
        )
        try createDatabase(
            at: databaseURL,
            timestampColumnType: "INTEGER",
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'account-usage',
                    'Account Usage',
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    2200,
                    '\(directory.path)',
                    \(Int(today.timeIntervalSince1970)),
                    \(Int(today.addingTimeInterval(1_800).timeIntervalSince1970)),
                    '\(rolloutURL.path)'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readSnapshot(
            now: now,
            accountWindows: [
                AccountUsageWindow(accountId: accountA, start: today, end: today.addingTimeInterval(1_500)),
                AccountUsageWindow(accountId: accountB, start: today.addingTimeInterval(1_500), end: nil)
            ]
        )

        XCTAssertEqual(snapshot.accountUsageSummaries.first { $0.accountId == accountA }?.totalTokens, 1_500)
        XCTAssertEqual(snapshot.accountUsageSummaries.first { $0.accountId == accountB }?.totalTokens, 700)
        XCTAssertEqual(snapshot.accountUsageSummaries.first { $0.accountId == accountA }?.threadCount, 1)
        XCTAssertEqual(snapshot.accountUsageSummaries.first { $0.accountId == accountB }?.threadCount, 1)
    }

    func testDailyUsageDoesNotAttributeHistoricalSessionTotalToTodayWithoutBaselineEvent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        let rolloutURL = directory.appendingPathComponent("rollout.jsonl")
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 0, minute: 20)))
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)

        try writeTokenUsageEvents(
            [
                (today.addingTimeInterval(300), 4_000_000),
                (today.addingTimeInterval(900), 4_050_000)
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
                    4050000,
                    '\(directory.path)',
                    \(Int(yesterday.addingTimeInterval(3_600).timeIntervalSince1970)),
                    \(Int(today.addingTimeInterval(900).timeIntervalSince1970)),
                    '\(rolloutURL.path)'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readSnapshot(now: now)

        XCTAssertEqual(snapshot.dailyTokenUsage.first { calendar.isDate($0.start, inSameDayAs: today) }?.tokens, 50_000)
        XCTAssertEqual(snapshot.hourlyTokenUsage.first { $0.start == calendar.dateInterval(of: .hour, for: today.addingTimeInterval(300))?.start }?.tokens, 50_000)
    }

    func testDailyUsageExcludesCachedInputTokensWhenDetailedTotalsExist() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("state_5.sqlite")
        let rolloutURL = directory.appendingPathComponent("rollout.jsonl")
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 1)))
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)

        try writeDetailedTokenUsageEvents(
            [
                (yesterday.addingTimeInterval(23 * 3_600), 1_000_000, 800_000, 20_000),
                (today.addingTimeInterval(600), 1_600_000, 1_300_000, 25_000),
                (today.addingTimeInterval(1_200), 2_400_000, 2_000_000, 30_000)
            ],
            to: rolloutURL
        )
        try createDatabase(
            at: databaseURL,
            timestampColumnType: "INTEGER",
            inserts: [
                """
                INSERT INTO threads VALUES(
                    'cached-usage',
                    'Cached Usage',
                    'codex',
                    'openai',
                    'gpt-5',
                    'medium',
                    2430000,
                    '\(directory.path)',
                    \(Int(yesterday.timeIntervalSince1970)),
                    \(Int(today.addingTimeInterval(1_200).timeIntervalSince1970)),
                    '\(rolloutURL.path)'
                );
                """
            ]
        )
        let reader = ThreadUsageReader(databaseURL: databaseURL)

        let snapshot = reader.readSnapshot(now: now)

        XCTAssertEqual(snapshot.dailyTokenUsage.first { calendar.isDate($0.start, inSameDayAs: today) }?.tokens, 210_000)
        XCTAssertEqual(snapshot.hourlyTokenUsage.first { $0.start == calendar.dateInterval(of: .hour, for: today.addingTimeInterval(600))?.start }?.tokens, 210_000)
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
                    '/tmp/project',
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
                    '/tmp/project',
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
            cwd: "/tmp/project",
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
            cwd TEXT,
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

    private func writeDetailedTokenUsageEvents(_ events: [(Date, Int, Int, Int)], to url: URL) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = events.map { date, inputTokens, cachedInputTokens, outputTokens in
            let totalTokens = inputTokens + outputTokens
            return """
            {"timestamp":"\(formatter.string(from: date))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(inputTokens),"cached_input_tokens":\(cachedInputTokens),"output_tokens":\(outputTokens),"total_tokens":\(totalTokens)}}}}
            """
        }
        try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
    }
}
