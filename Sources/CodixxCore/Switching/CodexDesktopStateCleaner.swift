import Foundation

public protocol CodexDesktopStateCleaning: AnyObject {
    var isCodexDesktopRunning: Bool { get }

    func clearState() throws
}

public final class NoopCodexDesktopStateCleaner: CodexDesktopStateCleaning {
    public var isCodexDesktopRunning: Bool { false }

    public init() {}

    public func clearState() throws {}
}

public final class FileSystemCodexDesktopStateCleaner: CodexDesktopStateCleaning {
    private let paths: CodixxPaths
    private let fileManager: FileManager
    private let isRunningCheck: () -> Bool

    public var isCodexDesktopRunning: Bool {
        isRunningCheck()
    }

    public init(
        paths: CodixxPaths = CodixxPaths(),
        fileManager: FileManager = .default,
        isRunning: @escaping () -> Bool = { false }
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.isRunningCheck = isRunning
    }

    public func clearState() throws {
        for relativePath in Self.volatileRelativePaths {
            let url = paths.codexDesktopApplicationSupport.appendingPathComponent(relativePath, isDirectory: true)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.removeItem(at: url)
        }
    }

    private static let volatileRelativePaths = [
        "Session Storage",
        "Cookies",
        "Cookies-journal",
        "Cache",
        "Code Cache",
        "GPUCache",
        "DawnGraphiteCache",
        "DawnWebGPUCache",
        "blob_storage",
        "shared_proto_db",
        "Partitions",
        "DIPS",
        "DIPS-wal",
        "Network Persistent State",
        "TransportSecurity",
        "Trust Tokens",
        "Trust Tokens-journal"
    ]
}
