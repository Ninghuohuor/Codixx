import Foundation
import SQLite3

/// Codex 当前登录凭据的健康状况。
public enum CodexAuthHealth: Equatable, Sendable {
    /// 没有 `auth.json`，或者当前不是 ChatGPT 凭据 —— 本检查不适用。
    case notChatGPT
    /// ChatGPT 凭据在本地，且没有发现被服务端作废的证据。
    case healthy
    /// ChatGPT 凭据还在本地，但服务端已经作废了它。
    ///
    /// 这是最容易被误判的状态：`codex login status` 只检查本地文件是否存在，
    /// 会照常说 "Logged in using ChatGPT"，而 Codex 的每一次请求都在 401。
    /// 桌面端因此拉不到账号态数据，界面看起来像"没登录"或"历史没了"。
    case credentialRevoked(since: Date)
}

/// 判断 `auth.json` 里的 ChatGPT 凭据是否已被服务端作废。
///
/// 唯一的可靠证据在 Codex 自己的日志里（`~/.codex/logs_*.sqlite`）：
///
/// ```
/// codex_login::auth::manager
///   Failed to refresh token: 401 ... code: refresh_token_invalidated
/// codex_models_manager::manager
///   401 Unauthorized ... auth error code: token_revoked
/// ```
///
/// 时间下界取 `max(auth.json 修改时间, now - 24h)`：
/// 用户重新登录会重写 `auth.json`，比它更早的错误说明已被新的登录覆盖，
/// 于是本检查会自动恢复正常，不需要额外的"已读"状态。
public struct CodexAuthHealthInspector {
    /// 只看最近这么久的日志 —— 更早的错误不该继续报警。
    public static let maximumLogLookback: TimeInterval = 24 * 60 * 60

    public let paths: CodixxPaths
    private let fileManager: FileManager
    private let now: () -> Date

    public init(
        paths: CodixxPaths = CodixxPaths(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.now = now
    }

    public func inspect() -> CodexAuthHealth {
        guard let credential = try? Data(contentsOf: paths.authJSON),
              let snapshot = try? AuthSnapshot(jsonData: credential),
              snapshot.stringValue(for: "auth_mode") == "chatgpt"
        else {
            return .notChatGPT
        }

        let authWrittenAt = (try? fileManager.attributesOfItem(atPath: paths.authJSON.path))?[.modificationDate] as? Date
        let earliest = max(
            authWrittenAt ?? .distantPast,
            now().addingTimeInterval(-Self.maximumLogLookback)
        )

        guard let revokedAt = latestRevocationDate(since: earliest) else {
            return .healthy
        }
        return .credentialRevoked(since: revokedAt)
    }

    /// 查日志里最近一条"凭据被作废"的错误时间。
    ///
    /// 任何异常（库不存在、表结构变了、被锁住）都返回 `nil` —— 探测失败时
    /// 宁可不说，也不要误报。
    private func latestRevocationDate(since earliest: Date) -> Date? {
        let databaseURL = paths.latestLogsDatabaseURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: databaseURL.path) else { return nil }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }

        // `ORDER BY id DESC LIMIT 1` 让 SQLite 从 rowid 末端往回扫、命中即停，
        // 不会把整个日志表读一遍。
        let sql = """
        SELECT ts FROM logs
        WHERE level = 'ERROR'
          AND ts > ?
          AND (feedback_log_body LIKE '%token_revoked%' OR feedback_log_body LIKE '%refresh_token_invalidated%')
        ORDER BY id DESC
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, earliest.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
    }
}
