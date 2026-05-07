import Foundation

public struct ParseCursorState: Codable, Equatable, Sendable {
    public var offsetsByPath: [String: Int64]
    public var archivedSessionsDirectoryModifiedAt: Date?
    public var archivedSessionPaths: [String]

    public init(
        offsetsByPath: [String: Int64] = [:],
        archivedSessionsDirectoryModifiedAt: Date? = nil,
        archivedSessionPaths: [String] = []
    ) {
        self.offsetsByPath = offsetsByPath
        self.archivedSessionsDirectoryModifiedAt = archivedSessionsDirectoryModifiedAt
        self.archivedSessionPaths = archivedSessionPaths
    }

    enum CodingKeys: String, CodingKey {
        case offsetsByPath
        case archivedSessionsDirectoryModifiedAt
        case archivedSessionPaths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.offsetsByPath = try container.decodeIfPresent([String: Int64].self, forKey: .offsetsByPath) ?? [:]
        self.archivedSessionsDirectoryModifiedAt = try container.decodeIfPresent(Date.self, forKey: .archivedSessionsDirectoryModifiedAt)
        self.archivedSessionPaths = try container.decodeIfPresent([String].self, forKey: .archivedSessionPaths) ?? []
    }

    public func offset(for url: URL) -> Int64 {
        offsetsByPath[Self.key(for: url)] ?? 0
    }

    public mutating func setOffset(_ offset: Int64, for url: URL) {
        offsetsByPath[Self.key(for: url)] = offset
    }

    public mutating func pruneKeepingOnly(_ urls: [URL]) {
        let retainedKeys = Set(urls.map(Self.key(for:)))
        offsetsByPath = offsetsByPath.filter { retainedKeys.contains($0.key) }
        archivedSessionPaths = archivedSessionPaths.filter { retainedKeys.contains($0) }
    }

    public func canUseCachedArchivedSessions(directoryModifiedAt: Date?) -> Bool {
        guard let directoryModifiedAt,
              let archivedSessionsDirectoryModifiedAt,
              !archivedSessionPaths.isEmpty
        else {
            return false
        }
        return archivedSessionsDirectoryModifiedAt == directoryModifiedAt
    }

    public func cachedArchivedSessionURLs() -> [URL] {
        archivedSessionPaths.map { URL(fileURLWithPath: $0) }
    }

    public mutating func recordArchivedSessions(_ urls: [URL], directoryModifiedAt: Date?) {
        archivedSessionsDirectoryModifiedAt = directoryModifiedAt
        archivedSessionPaths = urls.map(Self.key(for:)).sorted()
    }

    private static func key(for url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }
}

public struct ParseCursorStore {
    public let paths: CodixxPaths

    private let fileManager: FileManager
    private let fileStore: JSONFileStore<ParseCursorState>

    public init(paths: CodixxPaths = CodixxPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.fileStore = JSONFileStore(url: paths.parseCursorsJSON, fileManager: fileManager)
    }

    public func load() throws -> ParseCursorState {
        guard fileManager.fileExists(atPath: paths.parseCursorsJSON.path) else {
            return ParseCursorState()
        }
        return try fileStore.load()
    }

    public func save(_ state: ParseCursorState) throws {
        try paths.createApplicationSupportDirectories(fileManager: fileManager)
        try fileStore.save(state)
    }
}
