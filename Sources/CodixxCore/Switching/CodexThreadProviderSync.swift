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
        let rolloutPaths = try rolloutPaths(
            provider: sourceProvider,
            visibleThreadFilter: visibleThreadFilter,
            columns: columns,
            database: database
        )
        try backup(databaseURL: databaseURL, database: database)
        let sessionMetadataChanges = try syncSessionMetadata(
            rolloutPaths: rolloutPaths,
            from: sourceProvider,
            to: targetProvider
        )

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
            try? restoreSessionMetadata(sessionMetadataChanges)
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

    private func rolloutPaths(
        provider: String,
        visibleThreadFilter: String,
        columns: Set<String>,
        database: OpaquePointer
    ) throws -> [URL] {
        guard columns.contains("rollout_path") else { return [] }
        let statement = try prepare(
            "SELECT DISTINCT rollout_path FROM threads WHERE model_provider = ?\(visibleThreadFilter) AND rollout_path IS NOT NULL AND rollout_path != ''",
            database: database
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, provider, -1, SQLITE_TRANSIENT)

        var urls: [URL] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                guard let path = sqlite3_column_text(statement, 0) else { continue }
                urls.append(URL(fileURLWithPath: String(cString: path)))
            } else if stepResult == SQLITE_DONE {
                return urls
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

    private func syncSessionMetadata(
        rolloutPaths: [URL],
        from sourceProvider: String,
        to targetProvider: String
    ) throws -> [SessionMetadataChange] {
        let fileManager = FileManager.default
        var changes: [SessionMetadataChange] = []
        for rolloutPath in rolloutPaths where fileManager.fileExists(atPath: rolloutPath.path) {
            let text = try String(contentsOf: rolloutPath, encoding: .utf8)
            guard let newline = text.firstIndex(of: "\n") else { continue }
            let firstLine = String(text[..<newline])
            let rest = String(text[newline...])
            guard let updatedFirstLine = try updatedSessionMetaLine(firstLine, from: sourceProvider, to: targetProvider) else {
                continue
            }
            try backupSessionFile(rolloutPath)
            try (updatedFirstLine + rest).write(to: rolloutPath, atomically: true, encoding: .utf8)
            changes.append(SessionMetadataChange(url: rolloutPath, originalText: text))
        }
        return changes
    }

    private func restoreSessionMetadata(_ changes: [SessionMetadataChange]) throws {
        for change in changes.reversed() {
            try change.originalText.write(to: change.url, atomically: true, encoding: .utf8)
        }
    }

    private func updatedSessionMetaLine(_ line: String, from sourceProvider: String, to targetProvider: String) throws -> String? {
        guard let data = line.data(using: .utf8),
              var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "session_meta",
              var payload = object["payload"] as? [String: Any],
              payload["model_provider"] as? String == sourceProvider
        else {
            return nil
        }

        payload["model_provider"] = targetProvider
        object["payload"] = payload
        let updatedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let updatedLine = String(data: updatedData, encoding: .utf8) else {
            throw CodexThreadProviderSyncError.sessionMetadata("Could not encode session metadata")
        }
        return updatedLine
    }

    private func backupSessionFile(_ rolloutPath: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.backups, withIntermediateDirectories: true)
        let existingPrefix = "\(rolloutPath.lastPathComponent).provider-sync-"
        let existingBackups = (try? fileManager.contentsOfDirectory(atPath: paths.backups.path)) ?? []
        guard !existingBackups.contains(where: { $0.hasPrefix(existingPrefix) }) else {
            return
        }

        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = paths.backups.appendingPathComponent(
            "\(rolloutPath.lastPathComponent).provider-sync-\(stamp).bak"
        )
        try fileManager.copyItem(at: rolloutPath, to: backupURL)
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

private struct SessionMetadataChange {
    var url: URL
    var originalText: String
}

public enum CodexThreadProviderSyncError: Error, Equatable, LocalizedError {
    case sqlite(String)
    case sessionMetadata(String)

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message):
            return "Could not synchronize Codex thread providers. \(message)"
        case .sessionMetadata(let message):
            return "Could not synchronize Codex session metadata. \(message)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
