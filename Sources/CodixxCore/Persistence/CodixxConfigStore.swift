import Foundation

public struct CodixxConfig: Codable, Equatable, Sendable {
    public var codexDirectoryPath: String
    public var autoSwitchEnabled: Bool
    public var primaryThresholdPercent: Double
    public var notificationsEnabled: Bool
    public var detailedSwitchLoggingEnabled: Bool
    public var quotaRefreshIntervalSeconds: TimeInterval
    public var usageRefreshIntervalSeconds: TimeInterval

    public init(
        codexDirectoryPath: String,
        autoSwitchEnabled: Bool = true,
        primaryThresholdPercent: Double = 93,
        notificationsEnabled: Bool = true,
        detailedSwitchLoggingEnabled: Bool = true,
        quotaRefreshIntervalSeconds: TimeInterval = 60,
        usageRefreshIntervalSeconds: TimeInterval = 300
    ) {
        self.codexDirectoryPath = codexDirectoryPath
        self.autoSwitchEnabled = autoSwitchEnabled
        self.primaryThresholdPercent = primaryThresholdPercent
        self.notificationsEnabled = notificationsEnabled
        self.detailedSwitchLoggingEnabled = detailedSwitchLoggingEnabled
        self.quotaRefreshIntervalSeconds = quotaRefreshIntervalSeconds
        self.usageRefreshIntervalSeconds = usageRefreshIntervalSeconds
    }

    public static func `default`(paths: CodixxPaths = CodixxPaths()) -> CodixxConfig {
        CodixxConfig(codexDirectoryPath: paths.codexHome.path)
    }
}

public struct CodixxConfigStore {
    public let paths: CodixxPaths

    private let fileManager: FileManager
    private let fileStore: JSONFileStore<CodixxConfig>

    public init(paths: CodixxPaths = CodixxPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.fileStore = JSONFileStore(url: paths.configJSON, fileManager: fileManager)
    }

    public func load() throws -> CodixxConfig {
        guard fileManager.fileExists(atPath: paths.configJSON.path) else {
            return .default(paths: paths)
        }

        return try fileStore.load()
    }

    public func save(_ config: CodixxConfig) throws {
        try paths.createApplicationSupportDirectories(fileManager: fileManager)
        try fileStore.save(config)
    }
}
