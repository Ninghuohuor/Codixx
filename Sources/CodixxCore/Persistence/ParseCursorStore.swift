import Foundation

public struct ParseCursorState: Codable, Equatable, Sendable {
    public var offsetsByPath: [String: Int64]

    public init(offsetsByPath: [String: Int64] = [:]) {
        self.offsetsByPath = offsetsByPath
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
