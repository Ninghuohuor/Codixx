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
            return UsageAggregator.snapshot(threads: threads, now: now)
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
        let createdAtText = try requiredTextColumn(statement, index: 5, name: "created_at")
        let updatedAtText = try requiredTextColumn(statement, index: 6, name: "updated_at")
        guard
            let createdAt = parseISO8601Date(createdAtText),
            let updatedAt = parseISO8601Date(updatedAtText)
        else {
            throw ThreadUsageReaderError.incompatibleSchema("Invalid ISO8601 timestamp in threads table")
        }
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
