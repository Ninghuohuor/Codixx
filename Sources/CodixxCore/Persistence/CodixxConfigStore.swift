import Foundation

public enum CodixxLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chinese:
            return "中文"
        }
    }
}

public enum APISwitchThreadSyncScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case visibleDesktopThreads
    case allThreads

    public var id: String { rawValue }
}

public struct CodixxConfig: Codable, Equatable, Sendable {
    public var codexDirectoryPath: String
    public var autoSwitchEnabled: Bool
    public var primaryThresholdPercent: Double
    public var secondaryThresholdPercent: Double
    public var notificationsEnabled: Bool
    public var detailedSwitchLoggingEnabled: Bool
    public var quotaRefreshIntervalSeconds: TimeInterval
    public var usageRefreshIntervalSeconds: TimeInterval
    public var language: CodixxLanguage
    public var postSwitchAction: PostSwitchAction
    public var apiSwitchThreadSyncScope: APISwitchThreadSyncScope

    public init(
        codexDirectoryPath: String,
        autoSwitchEnabled: Bool = true,
        primaryThresholdPercent: Double = 93,
        secondaryThresholdPercent: Double = 90,
        notificationsEnabled: Bool = true,
        detailedSwitchLoggingEnabled: Bool = true,
        quotaRefreshIntervalSeconds: TimeInterval = 60,
        usageRefreshIntervalSeconds: TimeInterval = 300,
        language: CodixxLanguage = .english,
        postSwitchAction: PostSwitchAction = .notifyRestartRecommended,
        apiSwitchThreadSyncScope: APISwitchThreadSyncScope = .visibleDesktopThreads
    ) {
        self.codexDirectoryPath = codexDirectoryPath
        self.autoSwitchEnabled = autoSwitchEnabled
        self.primaryThresholdPercent = primaryThresholdPercent
        self.secondaryThresholdPercent = secondaryThresholdPercent
        self.notificationsEnabled = notificationsEnabled
        self.detailedSwitchLoggingEnabled = detailedSwitchLoggingEnabled
        self.quotaRefreshIntervalSeconds = quotaRefreshIntervalSeconds
        self.usageRefreshIntervalSeconds = usageRefreshIntervalSeconds
        self.language = language
        self.postSwitchAction = postSwitchAction
        self.apiSwitchThreadSyncScope = apiSwitchThreadSyncScope
    }

    public static func `default`(paths: CodixxPaths = CodixxPaths()) -> CodixxConfig {
        CodixxConfig(codexDirectoryPath: paths.codexHome.path)
    }

    private enum CodingKeys: String, CodingKey {
        case codexDirectoryPath
        case autoSwitchEnabled
        case primaryThresholdPercent
        case secondaryThresholdPercent
        case notificationsEnabled
        case detailedSwitchLoggingEnabled
        case quotaRefreshIntervalSeconds
        case usageRefreshIntervalSeconds
        case language
        case postSwitchAction
        case apiSwitchThreadSyncScope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.codexDirectoryPath = try container.decode(String.self, forKey: .codexDirectoryPath)
        self.autoSwitchEnabled = try container.decode(Bool.self, forKey: .autoSwitchEnabled)
        self.primaryThresholdPercent = try container.decode(Double.self, forKey: .primaryThresholdPercent)
        self.secondaryThresholdPercent = try container.decodeIfPresent(Double.self, forKey: .secondaryThresholdPercent) ?? 90
        self.notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        self.detailedSwitchLoggingEnabled = try container.decode(Bool.self, forKey: .detailedSwitchLoggingEnabled)
        self.quotaRefreshIntervalSeconds = try container.decode(TimeInterval.self, forKey: .quotaRefreshIntervalSeconds)
        self.usageRefreshIntervalSeconds = try container.decode(TimeInterval.self, forKey: .usageRefreshIntervalSeconds)
        self.language = try container.decodeIfPresent(CodixxLanguage.self, forKey: .language) ?? .english
        self.postSwitchAction = try container.decodeIfPresent(PostSwitchAction.self, forKey: .postSwitchAction) ?? .notifyRestartRecommended
        self.apiSwitchThreadSyncScope = try container.decodeIfPresent(APISwitchThreadSyncScope.self, forKey: .apiSwitchThreadSyncScope) ?? .visibleDesktopThreads
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
