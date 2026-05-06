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
        try paths.createApplicationSupportDirectories(fileManager: fileManager)
        let data = try Data(contentsOf: paths.authJSON)
        let filename = "auth-backup-\(Self.timestamp(now()))-\(Self.safeFilename(alias))-\(UUID().uuidString).json"
        let url = paths.backups.appendingPathComponent(filename)
        try SecureFilePermissions.writeOwnerOnlyFile(data, to: url, fileManager: fileManager)
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

    private static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ."))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "account" : sanitized
    }
}
