import Foundation

public struct SwitchBackupManager {
    public let paths: CodixxPaths
    private let now: () -> Date
    private let fileManager: FileManager

    public init(
        paths: CodixxPaths = CodixxPaths(),
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.now = now
        self.fileManager = fileManager
    }

    public func backupCurrentAuth(alias: String) throws -> URL {
        try fileManager.createDirectory(at: paths.backups, withIntermediateDirectories: true)
        let data = try Data(contentsOf: paths.authJSON)
        let filename = "auth-backup-\(Self.timestamp(now()))-\(alias)-\(UUID().uuidString).json"
        let url = paths.backups.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }

    public func restoreBackup(at backupURL: URL) throws {
        let data = try Data(contentsOf: backupURL)
        try AtomicFileWriter().write(data, to: paths.authJSON, fileManager: fileManager)
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter()
            .string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}
