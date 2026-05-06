import Foundation

public struct CodixxPaths: Sendable {
    public var home: URL
    public var codexHome: URL
    public var authJSON: URL
    public var applicationSupport: URL
    public var backups: URL
    public var logs: URL
    public var configJSON: URL
    public var accountsJSON: URL
    public var parseCursorsJSON: URL
    public var switchAuditJSONL: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        self.codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        self.authJSON = codexHome.appendingPathComponent("auth.json")
        self.applicationSupport = home.appendingPathComponent("Library/Application Support/Codixx", isDirectory: true)
        self.backups = applicationSupport.appendingPathComponent("backups", isDirectory: true)
        self.logs = applicationSupport.appendingPathComponent("logs", isDirectory: true)
        self.configJSON = applicationSupport.appendingPathComponent("config.json")
        self.accountsJSON = applicationSupport.appendingPathComponent("accounts.json")
        self.parseCursorsJSON = applicationSupport.appendingPathComponent("parse_cursors.json")
        self.switchAuditJSONL = applicationSupport.appendingPathComponent("switch_audit.jsonl")
    }

    public func createApplicationSupportDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backups, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logs, withIntermediateDirectories: true)
    }
}
