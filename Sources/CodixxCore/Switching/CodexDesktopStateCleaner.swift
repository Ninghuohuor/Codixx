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

    // Account switching replaces auth.json after Codex exits. Keep browser
    // session, cookies, and network state: they may contain UI preferences and
    // are not disposable rendering caches.
    private static let volatileRelativePaths = [
        "Cache",
        "Code Cache",
        "GPUCache",
        "DawnGraphiteCache",
        "DawnWebGPUCache"
    ]
}
