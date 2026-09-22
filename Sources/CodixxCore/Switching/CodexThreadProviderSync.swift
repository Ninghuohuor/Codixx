import Foundation
import SQLite3

public protocol CodexThreadProviderSyncing: Sendable {
    @discardableResult
    func syncProvider(from sourceProvider: String, to targetProvider: String, scope: APISwitchThreadSyncScope) throws -> Int
}

public struct NoopCodexThreadProviderSync: CodexThreadProviderSyncing {
    public init() {}

    public func syncProvider(from sourceProvider: String, to targetProvider: String, scope: APISwitchThreadSyncScope) throws -> Int {
        0
    }
}

public struct SQLiteCodexThreadProviderSync: CodexThreadProviderSyncing {
    public let paths: CodixxPaths

    public init(paths: CodixxPaths = CodixxPaths()) {
        self.paths = paths
    }

    public func syncProvider(
        from sourceProvider: String,
        to targetProvider: String,
        scope: APISwitchThreadSyncScope = .visibleDesktopThreads
    ) throws -> Int {
        guard sourceProvider != targetProvider else { return 0 }
        let fileManager = FileManager.default
        let databaseURL = paths.latestStateDatabaseURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: databaseURL.path) else { return 0 }

        let database = try openDatabase(databaseURL)
        defer { sqlite3_close(database) }
        try exec("PRAGMA busy_timeout = 2000", database: database)
        let columns = try columns(database: database)
        guard columns.contains("model_provider") else { return 0 }
        let visibleThreadFilter = threadFilter(for: scope, columns: columns)

        let matchingRows = try countRows(
            provider: sourceProvider,
            visibleThreadFilter: visibleThreadFilter,
            database: database
        )
        guard matchingRows > 0 else { return 0 }
        try backup(databaseURL: databaseURL, database: database)

        do {
            try exec("BEGIN IMMEDIATE", database: database)
            let changedRows = try updateRows(
                from: sourceProvider,
                to: targetProvider,
                visibleThreadFilter: visibleThreadFilter,
                database: database
            )
            try exec("COMMIT", database: database)
            return changedRows
        } catch {
            try? exec("ROLLBACK", database: database)
            throw error
        }
    }

    private func threadFilter(for scope: APISwitchThreadSyncScope, columns: Set<String>) -> String {
        guard scope == .visibleDesktopThreads, columns.contains("source") else { return "" }
        return " AND source = 'vscode'"
    }

    private func openDatabase(_ databaseURL: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            let message = database.map(errorMessage) ?? "Unable to open Codex state database"
            if let database {
                sqlite3_close(database)
            }
            throw CodexThreadProviderSyncError.sqlite(message)
        }
        return database
    }

    private func columns(database: OpaquePointer) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(threads)", database: database)
        defer { sqlite3_finalize(statement) }

        var columns: Set<String> = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                guard let columnName = sqlite3_column_text(statement, 1) else { continue }
                columns.insert(String(cString: columnName))
            } else if stepResult == SQLITE_DONE {
                return columns
            } else {
                throw CodexThreadProviderSyncError.sqlite(errorMessage(database))
            }
        }
    }

    private func countRows(provider: String, visibleThreadFilter: String, database: OpaquePointer) throws -> Int {
        let statement = try prepare(
            "SELECT COUNT(*) FROM threads WHERE model_provider = ?\(visibleThreadFilter)",
            database: database
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, provider, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw CodexThreadProviderSyncError.sqlite(errorMessage(database))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func updateRows(
        from sourceProvider: String,
        to targetProvider: String,
        visibleThreadFilter: String,
        database: OpaquePointer
    ) throws -> Int {
        let statement = try prepare(
            "UPDATE threads SET model_provider = ? WHERE model_provider = ?\(visibleThreadFilter)",
            database: database
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, targetProvider, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, sourceProvider, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CodexThreadProviderSyncError.sqlite(errorMessage(database))
        }
        return Int(sqlite3_changes(database))
    }

    private func backup(databaseURL: URL, database: OpaquePointer) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.backups, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = paths.backups.appendingPathComponent(
            "\(databaseURL.lastPathComponent).provider-sync-\(stamp).sqlite"
        )
        try exec("VACUUM INTO '\(escapeSQLiteString(backupURL.path))'", database: database)
    }

    private func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw CodexThreadProviderSyncError.sqlite(errorMessage(database))
        }
        return statement
    }

    private func exec(_ sql: String, database: OpaquePointer) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &error)
        guard result == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? errorMessage(database)
            if let error {
                sqlite3_free(error)
            }
            throw CodexThreadProviderSyncError.sqlite(message)
        }
    }

    private func errorMessage(_ database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }

    private func escapeSQLiteString(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}

public enum CodexThreadProviderSyncError: Error, Equatable, LocalizedError {
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message):
            return "Could not synchronize Codex thread providers. \(message)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
