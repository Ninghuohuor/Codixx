import Foundation

public struct CodixxPaths: Sendable {
    public var home: URL
    public var codexHome: URL
    public var authJSON: URL
    public var configTOML: URL
    public var applicationSupport: URL
    public var codexDesktopApplicationSupport: URL
    public var backups: URL
    public var logs: URL
    public var configJSON: URL
    public var accountsJSON: URL
    public var accountQuotaHistoryJSON: URL
    public var parseCursorsJSON: URL
    public var trendCacheJSON: URL
    public var switchAuditJSONL: URL
    public var appActivityJSONL: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        self.codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        self.authJSON = codexHome.appendingPathComponent("auth.json")
        self.configTOML = codexHome.appendingPathComponent("config.toml")
        self.applicationSupport = home.appendingPathComponent("Library/Application Support/Codixx", isDirectory: true)
        self.codexDesktopApplicationSupport = home.appendingPathComponent("Library/Application Support/Codex", isDirectory: true)
        self.backups = applicationSupport.appendingPathComponent("backups", isDirectory: true)
        self.logs = applicationSupport.appendingPathComponent("logs", isDirectory: true)
        self.configJSON = applicationSupport.appendingPathComponent("config.json")
        self.accountsJSON = applicationSupport.appendingPathComponent("accounts.json")
        self.accountQuotaHistoryJSON = applicationSupport.appendingPathComponent("account_quota_history.json")
        self.parseCursorsJSON = applicationSupport.appendingPathComponent("parse_cursors.json")
        self.trendCacheJSON = applicationSupport.appendingPathComponent("trend_cache.json")
        self.switchAuditJSONL = applicationSupport.appendingPathComponent("switch_audit.jsonl")
        self.appActivityJSONL = applicationSupport.appendingPathComponent("app_activity.jsonl")
    }

    public func createApplicationSupportDirectories(fileManager: FileManager = .default) throws {
        try SecureFilePermissions.secureDirectory(applicationSupport, fileManager: fileManager)
        try SecureFilePermissions.secureDirectory(backups, fileManager: fileManager)
        try SecureFilePermissions.secureDirectory(logs, fileManager: fileManager)
    }

    public func latestStateDatabaseURL(fileManager: FileManager = .default) -> URL {
        latestVersionedDatabaseURL(
            prefix: "state_",
            fallbackName: "state_5.sqlite",
            fileManager: fileManager
        )
    }

    /// Codex 的运行日志库（`logs_*.sqlite`）。
    ///
    /// `CodexAuthHealthInspector` 用它判断 `auth.json` 里的凭据是否已被服务端作废
    /// —— 这种状态下 `codex login status` 仍会报"已登录"，只有日志能说明真相。
    public func latestLogsDatabaseURL(fileManager: FileManager = .default) -> URL {
        latestVersionedDatabaseURL(
            prefix: "logs_",
            fallbackName: "logs_2.sqlite",
            fileManager: fileManager
        )
    }

    private func latestVersionedDatabaseURL(
        prefix: String,
        fallbackName: String,
        fileManager: FileManager
    ) -> URL {
        let fallback = codexHome.appendingPathComponent(fallbackName)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: codexHome,
            includingPropertiesForKeys: nil
        ) else {
            return fallback
        }

        return entries
            .compactMap { url -> (version: Int, url: URL)? in
                let name = url.lastPathComponent
                guard name.hasPrefix(prefix), name.hasSuffix(".sqlite") else { return nil }
                let versionText = name
                    .dropFirst(prefix.count)
                    .dropLast(".sqlite".count)
                guard let version = Int(versionText) else { return nil }
                return (version, url)
            }
            .max { $0.version < $1.version }?
            .url ?? fallback
    }
}
