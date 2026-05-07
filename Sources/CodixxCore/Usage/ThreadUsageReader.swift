import Foundation
import SQLite3

public struct ThreadUsageReader: Sendable {
    public var databaseURL: URL
    public var lockedRetryCount: Int
    public var lockedRetryDelay: TimeInterval

    public init(
        databaseURL: URL,
        lockedRetryCount: Int = 3,
        lockedRetryDelay: TimeInterval = 1
    ) {
        self.databaseURL = databaseURL
        self.lockedRetryCount = lockedRetryCount
        self.lockedRetryDelay = lockedRetryDelay
    }

    public func readSnapshot(now: Date) -> ThreadUsageSnapshot {
        do {
            let threads = try readThreadsWithRetries()
            return UsageAggregator.snapshot(
                threads: threads,
                now: now,
                dailyTokenUsage: tokenUsageBuckets(
                    for: threads,
                    intervals: dailyIntervals(now: now)
                ),
                hourlyTokenUsage: tokenUsageBuckets(
                    for: threads,
                    intervals: hourlyIntervals(now: now)
                )
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

        try validateSchema(database)

        let sql = """
        SELECT id, title, model, reasoning_effort, tokens_used, created_at, updated_at, rollout_path
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

    private func validateSchema(_ database: OpaquePointer) throws {
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
        let createdAt = try requiredTimestampColumn(statement, index: 5, name: "created_at")
        let updatedAt = try requiredTimestampColumn(statement, index: 6, name: "updated_at")
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
            createdAt: createdAt,
            updatedAt: updatedAt,
            rolloutPath: try requiredTextColumn(statement, index: 7, name: "rollout_path")
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

    private func tokenUsageBuckets(for threads: [ThreadUsage], intervals: [DateInterval]) -> [TokenUsageBucket] {
        guard let firstInterval = intervals.first else { return [] }
        var totals = Dictionary(uniqueKeysWithValues: intervals.map { ($0.start, 0) })

        for thread in threads where thread.updatedAt >= firstInterval.start {
            let events = readTokenEvents(from: URL(fileURLWithPath: thread.rolloutPath))
            guard !events.isEmpty else { continue }

            for interval in intervals {
                let maxInInterval = events
                    .filter { $0.timestamp >= interval.start && $0.timestamp < interval.end }
                    .map(\.totalTokens)
                    .max()
                guard let maxInInterval else { continue }

                let baseline = events.last { $0.timestamp < interval.start }?.totalTokens ?? 0
                totals[interval.start, default: 0] += max(0, maxInInterval - baseline)
            }
        }

        return intervals.map { TokenUsageBucket(start: $0.start, tokens: totals[$0.start] ?? 0) }
    }

    private func readTokenEvents(from url: URL) -> [TokenUsageEvent] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content
            .split(separator: "\n")
            .compactMap { parseTokenUsageEvent(String($0)) }
            .sorted { $0.timestamp < $1.timestamp }
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

        return TokenUsageEvent(timestamp: timestamp, totalTokens: totalTokens)
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
