import Foundation
import SQLite3

public struct ThreadUsageReader: Sendable {
    public var databaseURL: URL
    public var lockedRetryCount: Int
    public var lockedRetryDelay: TimeInterval
    public var trendCacheStore: TrendCacheStore?

    public init(
        databaseURL: URL,
        lockedRetryCount: Int = 3,
        lockedRetryDelay: TimeInterval = 1,
        trendCacheStore: TrendCacheStore? = nil
    ) {
        self.databaseURL = databaseURL
        self.lockedRetryCount = lockedRetryCount
        self.lockedRetryDelay = lockedRetryDelay
        self.trendCacheStore = trendCacheStore
    }

    public func readSnapshot(now: Date, accountWindows: [AccountUsageWindow] = []) -> ThreadUsageSnapshot {
        do {
            let rawThreads = try readThreadsWithRetries()
            let dailyIntervals = dailyIntervals(now: now)
            let hourlyIntervals = hourlyIntervals(now: now)
            let monthlyIntervals = monthlyIntervals(now: now)
            let intervalGroups = [dailyIntervals, hourlyIntervals, monthlyIntervals]
            var trendCache = loadTrendCache()
            let threads = threadsWithEffectiveTokenCounts(rawThreads, trendCache: &trendCache)
            let tokenEventsByThreadId = tokenEventsByThreadId(
                for: threads,
                dailyIntervals: dailyIntervals,
                monthlyIntervals: monthlyIntervals,
                trendCache: &trendCache
            )
            saveTrendCache(trendCache)
            let tokenUsage = tokenUsageBuckets(
                for: threads,
                intervalGroups: intervalGroups,
                fallbackIntervalGroupIndexes: [2],
                tokenEventsByThreadId: tokenEventsByThreadId
            )
            return UsageAggregator.snapshot(
                threads: threads,
                now: now,
                dailyTokenUsage: tokenUsage.indices.contains(0) ? tokenUsage[0] : [],
                hourlyTokenUsage: tokenUsage.indices.contains(1) ? tokenUsage[1] : [],
                monthlyTokenUsage: tokenUsage.indices.contains(2) ? tokenUsage[2] : [],
                accountUsageSummaries: accountUsageSummaries(
                    for: threads,
                    accountWindows: accountWindows,
                    dailyIntervals: dailyIntervals,
                    monthlyIntervals: monthlyIntervals,
                    tokenEventsByThreadId: tokenEventsByThreadId
                )
            )
        } catch {
            return .degraded(error.localizedDescription)
        }
    }

    private func threadsWithEffectiveTokenCounts(
        _ threads: [ThreadUsage],
        trendCache: inout TrendCacheState
    ) -> [ThreadUsage] {
        threads.map { thread in
            let events = readTokenEvents(from: URL(fileURLWithPath: thread.rolloutPath), trendCache: &trendCache)
            guard let effectiveTokens = events.map(\.totalTokens).max() else {
                return thread
            }
            var updatedThread = thread
            updatedThread.tokensUsed = effectiveTokens
            return updatedThread
        }
    }

    public func readActivitySnapshot(now: Date) -> ThreadUsageSnapshot {
        do {
            var trendCache = loadTrendCache()
            let threads = threadsWithEffectiveTokenCounts(try readThreadsWithRetries(), trendCache: &trendCache)
            saveTrendCache(trendCache)
            return UsageAggregator.snapshot(
                threads: threads,
                now: now
            )
        } catch {
            return .degraded(error.localizedDescription)
        }
    }

    public static func totalAttemptCount(lockedRetryCount: Int) -> Int {
        max(0, lockedRetryCount) + 1
    }

    private func readThreadsWithRetries() throws -> [ThreadUsage] {
        let attempts = Self.totalAttemptCount(lockedRetryCount: lockedRetryCount)
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try readThreads()
            } catch ThreadUsageReaderError.locked(let message) {
                lastError = ThreadUsageReaderError.locked(message)
                if attempt < attempts {
                    Thread.sleep(forTimeInterval: lockedRetryDelay)
                }
            }
        }

        throw lastError ?? ThreadUsageReaderError.locked("SQLite database is locked")
    }

    private func readThreads() throws -> [ThreadUsage] {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        let columns = try validateSchema(database)
        let cwdSelection = columns.contains("cwd") ? "cwd" : "'' AS cwd"

        let sql = """
        SELECT id, title, model, reasoning_effort, tokens_used, \(cwdSelection), created_at, updated_at, rollout_path
        FROM threads
        ORDER BY updated_at DESC
        """
        let statement = try prepare(database, sql: sql)
        defer { sqlite3_finalize(statement) }

        var threads: [ThreadUsage] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                threads.append(try makeThread(from: statement))
            } else if stepResult == SQLITE_DONE {
                return threads
            } else if isLocked(stepResult) {
                throw ThreadUsageReaderError.locked(errorMessage(database))
            } else {
                throw ThreadUsageReaderError.sqlite(errorMessage(database))
            }
        }
    }

    private func openDatabase() throws -> OpaquePointer {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &database, flags, nil)
        guard result == SQLITE_OK, let openedDatabase = database else {
            let message = database.map(errorMessage) ?? "Unable to open SQLite database"
            if let database {
                sqlite3_close(database)
            }
            if isLocked(result) {
                throw ThreadUsageReaderError.locked(message)
            }
            throw ThreadUsageReaderError.sqlite(message)
        }

        return openedDatabase
    }

    private func validateSchema(_ database: OpaquePointer) throws -> Set<String> {
        let statement = try prepare(database, sql: "PRAGMA table_info(threads)")
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                columns.insert(textColumn(statement, index: 1))
            } else if stepResult == SQLITE_DONE {
                break
            } else if isLocked(stepResult) {
                throw ThreadUsageReaderError.locked(errorMessage(database))
            } else {
                throw ThreadUsageReaderError.sqlite(errorMessage(database))
            }
        }

        let requiredColumns: Set<String> = [
            "id",
            "title",
            "model",
            "reasoning_effort",
            "tokens_used",
            "created_at",
            "updated_at",
            "rollout_path"
        ]
        let missing = requiredColumns.subtracting(columns).sorted()
        if !missing.isEmpty {
            throw ThreadUsageReaderError.incompatibleSchema("Missing threads columns: \(missing.joined(separator: ", "))")
        }

        return columns
    }

    private func prepare(_ database: OpaquePointer, sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let preparedStatement = statement else {
            if isLocked(result) {
                throw ThreadUsageReaderError.locked(errorMessage(database))
            }
            throw ThreadUsageReaderError.sqlite(errorMessage(database))
        }

        return preparedStatement
    }

    private func makeThread(from statement: OpaquePointer) throws -> ThreadUsage {
        let createdAt = try requiredTimestampColumn(statement, index: 6, name: "created_at")
        let updatedAt = try requiredTimestampColumn(statement, index: 7, name: "updated_at")
        let tokenType = sqlite3_column_type(statement, 4)
        guard tokenType == SQLITE_INTEGER else {
            throw ThreadUsageReaderError.incompatibleSchema("Invalid tokens_used value in threads table")
        }

        return ThreadUsage(
            id: try requiredTextColumn(statement, index: 0, name: "id"),
            title: try requiredTextColumn(statement, index: 1, name: "title"),
            model: try requiredTextColumn(statement, index: 2, name: "model"),
            reasoningEffort: try requiredTextColumn(statement, index: 3, name: "reasoning_effort"),
            tokensUsed: Int(sqlite3_column_int64(statement, 4)),
            cwd: try requiredTextColumn(statement, index: 5, name: "cwd"),
            createdAt: createdAt,
            updatedAt: updatedAt,
            rolloutPath: try requiredTextColumn(statement, index: 8, name: "rollout_path")
        )
    }

    private func textColumn(_ statement: OpaquePointer, index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: text)
    }

    private func requiredTimestampColumn(_ statement: OpaquePointer, index: Int32, name: String) throws -> Date {
        let columnType = sqlite3_column_type(statement, index)
        switch columnType {
        case SQLITE_INTEGER:
            let value = sqlite3_column_int64(statement, index)
            let seconds = value > 10_000_000_000 ? TimeInterval(value) / 1_000 : TimeInterval(value)
            return Date(timeIntervalSince1970: seconds)
        case SQLITE_TEXT:
            let text = try requiredTextColumn(statement, index: index, name: name)
            guard let date = parseISO8601Date(text) else {
                throw ThreadUsageReaderError.incompatibleSchema("Invalid timestamp in \(name) column")
            }
            return date
        case SQLITE_NULL:
            throw ThreadUsageReaderError.incompatibleSchema("Missing \(name) value in threads table")
        default:
            throw ThreadUsageReaderError.incompatibleSchema("Invalid \(name) timestamp type in threads table")
        }
    }

    private func requiredTextColumn(_ statement: OpaquePointer, index: Int32, name: String) throws -> String {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            throw ThreadUsageReaderError.incompatibleSchema("Missing \(name) value in threads table")
        }
        guard let text = sqlite3_column_text(statement, index) else {
            throw ThreadUsageReaderError.incompatibleSchema("Invalid \(name) value in threads table")
        }
        return String(cString: text)
    }

    private func parseISO8601Date(_ text: String) -> Date? {
        let wholeSecondFormatter = ISO8601DateFormatter()
        wholeSecondFormatter.formatOptions = [.withInternetDateTime]
        if let date = wholeSecondFormatter.date(from: text) {
            return date
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: text)
    }

    private func dailyIntervals(now: Date) -> [DateInterval] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today.addingTimeInterval(-6 * 86_400)
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start.addingTimeInterval(TimeInterval(offset * 86_400))
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            return DateInterval(start: day, end: nextDay)
        }
    }

    private func hourlyIntervals(now: Date) -> [DateInterval] {
        let calendar = Calendar.current
        let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let start = calendar.date(byAdding: .hour, value: -23, to: currentHour) ?? currentHour.addingTimeInterval(-23 * 3_600)
        return (0..<24).map { offset in
            let hour = calendar.date(byAdding: .hour, value: offset, to: start) ?? start.addingTimeInterval(TimeInterval(offset * 3_600))
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: hour) ?? hour.addingTimeInterval(3_600)
            return DateInterval(start: hour, end: nextHour)
        }
    }

    private func monthlyIntervals(now: Date) -> [DateInterval] {
        let calendar = Calendar.current
        let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth.addingTimeInterval(-31 * 86_400)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth.addingTimeInterval(31 * 86_400)
        return [
            DateInterval(start: previousMonth, end: currentMonth),
            DateInterval(start: currentMonth, end: nextMonth)
        ]
    }

    private func tokenUsageBuckets(for threads: [ThreadUsage], intervals: [DateInterval]) -> [TokenUsageBucket] {
        tokenUsageBuckets(for: threads, intervalGroups: [intervals]).first ?? []
    }

    private func tokenUsageBuckets(
        for threads: [ThreadUsage],
        intervalGroups: [[DateInterval]],
        fallbackIntervalGroupIndexes: Set<Int> = [],
        tokenEventsByThreadId: [String: [TokenUsageEvent]]? = nil
    ) -> [[TokenUsageBucket]] {
        let firstIntervalStart = intervalGroups.flatMap { $0 }.map(\.start).min()
        var totalsByGroup = intervalGroups.map { intervals in
            Dictionary(uniqueKeysWithValues: intervals.map { ($0.start, 0) })
        }
        guard let firstIntervalStart else {
            return intervalGroups.map { _ in [] }
        }

        for thread in threads where thread.updatedAt >= firstIntervalStart {
            let events: [TokenUsageEvent]
            if let tokenEventsByThreadId {
                events = tokenEventsByThreadId[thread.id] ?? []
            } else {
                events = readTokenEvents(from: URL(fileURLWithPath: thread.rolloutPath))
            }

            for groupIndex in intervalGroups.indices {
                for interval in intervalGroups[groupIndex] {
                    let eventsInInterval = events
                        .filter { $0.timestamp >= interval.start && $0.timestamp < interval.end }
                    if eventsInInterval.isEmpty {
                        if fallbackIntervalGroupIndexes.contains(groupIndex),
                           thread.tokensUsed > 0,
                           interval.contains(thread.updatedAt) {
                            totalsByGroup[groupIndex][interval.start, default: 0] += thread.tokensUsed
                        }
                        continue
                    }
                    let maxInInterval = eventsInInterval
                        .map(\.totalTokens)
                        .max() ?? 0

                    let baseline: Int
                    if let previousEvent = events.last(where: { $0.timestamp < interval.start }) {
                        baseline = previousEvent.totalTokens
                    } else if thread.createdAt >= interval.start {
                        baseline = 0
                    } else {
                        baseline = eventsInInterval.first?.totalTokens ?? maxInInterval
                    }
                    totalsByGroup[groupIndex][interval.start, default: 0] += max(0, maxInInterval - baseline)
                }
            }
        }

        return intervalGroups.enumerated().map { groupIndex, intervals in
            intervals.map { TokenUsageBucket(start: $0.start, tokens: totalsByGroup[groupIndex][$0.start] ?? 0) }
        }
    }

    private func accountUsageSummaries(
        for threads: [ThreadUsage],
        accountWindows: [AccountUsageWindow],
        dailyIntervals: [DateInterval],
        monthlyIntervals: [DateInterval],
        tokenEventsByThreadId: [String: [TokenUsageEvent]]? = nil
    ) -> [AccountUsageSummary] {
        let accountIds = Array(Set(accountWindows.map(\.accountId))).sorted { $0.uuidString < $1.uuidString }
        guard !accountIds.isEmpty else { return [] }

        var totalTokensByAccount = Dictionary(uniqueKeysWithValues: accountIds.map { ($0, 0) })
        var threadIdsByAccount = Dictionary(uniqueKeysWithValues: accountIds.map { ($0, Set<String>()) })
        var dailyTotalsByAccount = Dictionary(uniqueKeysWithValues: accountIds.map { accountId in
            (accountId, Dictionary(uniqueKeysWithValues: dailyIntervals.map { ($0.start, 0) }))
        })
        var monthlyTotalsByAccount = Dictionary(uniqueKeysWithValues: accountIds.map { accountId in
            (accountId, Dictionary(uniqueKeysWithValues: monthlyIntervals.map { ($0.start, 0) }))
        })

        for thread in threads {
            let events: [TokenUsageEvent]
            if let tokenEventsByThreadId {
                events = tokenEventsByThreadId[thread.id] ?? []
            } else {
                events = readTokenEvents(from: URL(fileURLWithPath: thread.rolloutPath))
            }
            guard !events.isEmpty else {
                guard thread.tokensUsed > 0,
                      let accountWindow = accountWindow(for: thread.updatedAt, in: accountWindows)
                else {
                    continue
                }
                let accountId = accountWindow.accountId
                totalTokensByAccount[accountId, default: 0] += thread.tokensUsed
                threadIdsByAccount[accountId, default: []].insert(thread.id)
                if let interval = monthlyIntervals.first(where: { $0.contains(thread.updatedAt) }) {
                    monthlyTotalsByAccount[accountId]?[interval.start, default: 0] += thread.tokensUsed
                }
                continue
            }

            var previousTotal: Int?
            for event in events {
                guard let accountWindow = accountWindow(for: event.timestamp, in: accountWindows) else {
                    previousTotal = event.totalTokens
                    continue
                }
                let accountId = accountWindow.accountId
                let baseline: Int
                if let previousTotal {
                    baseline = previousTotal
                } else if thread.createdAt >= accountWindow.start {
                    baseline = 0
                } else {
                    baseline = event.totalTokens
                }
                previousTotal = event.totalTokens
                let delta = max(0, event.totalTokens - baseline)
                guard delta > 0 else { continue }

                totalTokensByAccount[accountId, default: 0] += delta
                threadIdsByAccount[accountId, default: []].insert(thread.id)
                if let interval = dailyIntervals.first(where: { $0.contains(event.timestamp) }) {
                    dailyTotalsByAccount[accountId]?[interval.start, default: 0] += delta
                }
                if let interval = monthlyIntervals.first(where: { $0.contains(event.timestamp) }) {
                    monthlyTotalsByAccount[accountId]?[interval.start, default: 0] += delta
                }
            }
        }

        return accountIds.map { accountId in
            AccountUsageSummary(
                accountId: accountId,
                totalTokens: totalTokensByAccount[accountId] ?? 0,
                threadCount: threadIdsByAccount[accountId]?.count ?? 0,
                dailyTokenUsage: dailyIntervals.map {
                    TokenUsageBucket(start: $0.start, tokens: dailyTotalsByAccount[accountId]?[$0.start] ?? 0)
                },
                monthlyTokenUsage: monthlyIntervals.map {
                    TokenUsageBucket(start: $0.start, tokens: monthlyTotalsByAccount[accountId]?[$0.start] ?? 0)
                }
            )
        }
    }

    private func tokenEventsByThreadId(
        for threads: [ThreadUsage],
        dailyIntervals: [DateInterval],
        monthlyIntervals: [DateInterval],
        trendCache: inout TrendCacheState
    ) -> [String: [TokenUsageEvent]] {
        var eventsByThreadId: [String: [TokenUsageEvent]] = [:]
        for thread in threads where shouldReadTokenEvents(
            for: thread,
            dailyIntervals: dailyIntervals,
            monthlyIntervals: monthlyIntervals
        ) {
            eventsByThreadId[thread.id] = readTokenEvents(
                from: URL(fileURLWithPath: thread.rolloutPath),
                trendCache: &trendCache
            )
        }
        return eventsByThreadId
    }

    private func shouldReadTokenEvents(
        for thread: ThreadUsage,
        dailyIntervals: [DateInterval],
        monthlyIntervals: [DateInterval]
    ) -> Bool {
        if let dailyStart = dailyIntervals.map(\.start).min(), thread.updatedAt >= dailyStart {
            return true
        }

        let monthlyBoundaries = monthlyIntervals.map(\.start).dropFirst()
        if monthlyBoundaries.contains(where: { boundary in
            thread.createdAt < boundary && thread.updatedAt >= boundary
        }) {
            return true
        }

        if let monthlyStart = monthlyIntervals.map(\.start).min(), thread.updatedAt >= monthlyStart {
            return true
        }

        return false
    }

    private func accountWindow(for date: Date, in accountWindows: [AccountUsageWindow]) -> AccountUsageWindow? {
        accountWindows.first { $0.contains(date) }
    }

    private static let maxTokenEventFileSize: UInt64 = 50_000_000

    private func readTokenEvents(from url: URL, trendCache: inout TrendCacheState) -> [TokenUsageEvent] {
        guard let fileInfo = tokenEventFileInfo(for: url) else { return [] }
        let cacheKey = Self.cacheKey(for: url)

        if let cached = trendCache.entriesByPath[cacheKey],
           cached.fileSize == fileInfo.fileSize,
           cached.modifiedAt == fileInfo.modifiedAt
        {
            return cached.events.map(TokenUsageEvent.init)
        }

        guard fileInfo.fileSize <= Self.maxTokenEventFileSize,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            trendCache.entriesByPath[cacheKey] = TrendCacheEntry(
                fileSize: fileInfo.fileSize,
                modifiedAt: fileInfo.modifiedAt,
                events: []
            )
            return []
        }

        var events = text.split(separator: "\n").compactMap { line in
            parseTokenUsageEvent(String(line))
        }
        events.sort { $0.timestamp < $1.timestamp }
        trendCache.entriesByPath[cacheKey] = TrendCacheEntry(
            fileSize: fileInfo.fileSize,
            modifiedAt: fileInfo.modifiedAt,
            events: events.map(CachedTokenUsageEvent.init)
        )
        return events
    }

    private func readTokenEvents(from url: URL) -> [TokenUsageEvent] {
        var trendCache = TrendCacheState()
        return readTokenEvents(from: url, trendCache: &trendCache)
    }

    private func loadTrendCache() -> TrendCacheState {
        (try? trendCacheStore?.load()) ?? TrendCacheState()
    }

    private func saveTrendCache(_ state: TrendCacheState) {
        try? trendCacheStore?.save(state)
    }

    private func tokenEventFileInfo(for url: URL) -> (fileSize: UInt64, modifiedAt: Date?)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? UInt64
        else { return nil }
        return (fileSize, attrs[.modificationDate] as? Date)
    }

    private static func cacheKey(for url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    private func parseTokenUsageEvent(_ line: String) -> TokenUsageEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "event_msg",
              let timestampText = object["timestamp"] as? String,
              let timestamp = parseISO8601Date(timestampText),
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let totalTokenUsage = info["total_token_usage"] as? [String: Any],
              let totalTokens = integerValue(totalTokenUsage["total_tokens"])
        else {
            return nil
        }

        let effectiveTokens = effectiveTokenCount(from: totalTokenUsage) ?? totalTokens
        return TokenUsageEvent(timestamp: timestamp, totalTokens: effectiveTokens)
    }

    private func effectiveTokenCount(from totalTokenUsage: [String: Any]) -> Int? {
        guard let inputTokens = integerValue(totalTokenUsage["input_tokens"]),
              let outputTokens = integerValue(totalTokenUsage["output_tokens"])
        else {
            return nil
        }

        let cachedInputTokens = integerValue(totalTokenUsage["cached_input_tokens"]) ?? 0
        return max(0, inputTokens - cachedInputTokens) + outputTokens
    }

    private func integerValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let int64 as Int64:
            return Int(int64)
        case let double as Double where double.rounded() == double:
            return Int(double)
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }

    private func errorMessage(_ database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }

    private func isLocked(_ code: Int32) -> Bool {
        code == SQLITE_BUSY || code == SQLITE_LOCKED
    }

}

private struct TokenUsageEvent {
    var timestamp: Date
    var totalTokens: Int

    init(timestamp: Date, totalTokens: Int) {
        self.timestamp = timestamp
        self.totalTokens = totalTokens
    }

    init(_ cached: CachedTokenUsageEvent) {
        self.timestamp = cached.timestamp
        self.totalTokens = cached.totalTokens
    }
}

private extension CachedTokenUsageEvent {
    init(_ event: TokenUsageEvent) {
        self.init(timestamp: event.timestamp, totalTokens: event.totalTokens)
    }
}

private enum ThreadUsageReaderError: LocalizedError {
    case incompatibleSchema(String)
    case locked(String)
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .incompatibleSchema(let message):
            return "Incompatible Codex usage database schema. \(message)"
        case .locked(let message):
            return "Codex usage database is locked. \(message)"
        case .sqlite(let message):
            return "Unable to read Codex usage database. \(message)"
        }
    }
}
