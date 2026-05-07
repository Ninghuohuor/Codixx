import Foundation

public struct CachedTokenUsageEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var totalTokens: Int

    public init(timestamp: Date, totalTokens: Int) {
        self.timestamp = timestamp
        self.totalTokens = totalTokens
    }
}

public struct TrendCacheEntry: Codable, Equatable, Sendable {
    public var fileSize: UInt64
    public var modifiedAt: Date?
    public var events: [CachedTokenUsageEvent]

    public init(fileSize: UInt64, modifiedAt: Date?, events: [CachedTokenUsageEvent]) {
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.events = events
    }
}

public struct TrendCacheState: Codable, Equatable, Sendable {
    public var entriesByPath: [String: TrendCacheEntry]

    public init(entriesByPath: [String: TrendCacheEntry] = [:]) {
        self.entriesByPath = entriesByPath
    }
}

public struct TrendCacheStore: @unchecked Sendable {
    public let paths: CodixxPaths

    private let fileManager: FileManager
    private let fileStore: JSONFileStore<TrendCacheState>

    public init(paths: CodixxPaths = CodixxPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.fileStore = JSONFileStore(url: paths.trendCacheJSON, fileManager: fileManager)
    }

    public func load() throws -> TrendCacheState {
        guard fileManager.fileExists(atPath: paths.trendCacheJSON.path) else {
            return TrendCacheState()
        }
        return try fileStore.load()
    }

    public func save(_ state: TrendCacheState) throws {
        try paths.createApplicationSupportDirectories(fileManager: fileManager)
        try fileStore.save(state)
    }
}
