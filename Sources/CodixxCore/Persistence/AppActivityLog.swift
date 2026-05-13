import Foundation

public enum AppLogEventKind: String, Codable, Equatable, Sendable {
    case accountSaved
    case authImported
    case apiProviderSaved
    case apiProviderUpdated
    case accountRenamed
    case accountDeleted
    case accountEnabled
    case accountDisabled
    case accountReordered
    case codexRestarted
    case codexRestartFailed
    case refreshFailed
    case apiBalanceRefreshed
    case apiBalanceRefreshFailed
}

public struct AppLogEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var kind: AppLogEventKind
    public var accountId: UUID?
    public var accountAlias: String?
    public var secondaryAlias: String?
    public var detail: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: AppLogEventKind,
        accountId: UUID? = nil,
        accountAlias: String? = nil,
        secondaryAlias: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.accountId = accountId
        self.accountAlias = accountAlias
        self.secondaryAlias = secondaryAlias
        self.detail = detail
    }
}

public struct AppActivityLog {
    public struct Retention {
        public var maximumAge: TimeInterval
        public var maximumBytes: Int
        public var now: () -> Date

        public init(
            maximumAge: TimeInterval = 90 * 86_400,
            maximumBytes: Int = 10 * 1024 * 1024,
            now: @escaping () -> Date = Date.init
        ) {
            self.maximumAge = maximumAge
            self.maximumBytes = maximumBytes
            self.now = now
        }
    }

    public let paths: CodixxPaths
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager: FileManager
    private let retention: Retention

    public init(
        paths: CodixxPaths = CodixxPaths(),
        fileManager: FileManager = .default,
        retention: Retention = Retention()
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.retention = retention
    }

    public func append(_ event: AppLogEvent) throws {
        try paths.createApplicationSupportDirectories(fileManager: fileManager)
        try prune(existingEvents: loadEventsWithoutPruning() + [event])
    }

    public func loadEvents() throws -> [AppLogEvent] {
        try loadEventsWithoutPruning()
    }

    private func loadEventsWithoutPruning() throws -> [AppLogEvent] {
        var events: [AppLogEvent] = []
        for url in logURLsForLoading() {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else { continue }
            events.append(contentsOf: text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    try? decoder.decode(AppLogEvent.self, from: Data(line.utf8))
                }
            )
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    private func logURLsForLoading() -> [URL] {
        [3, 2, 1].map { historyURL(index: $0) } + [paths.appActivityJSONL]
    }

    private func historyURL(index: Int) -> URL {
        paths.applicationSupport.appendingPathComponent("app_activity.\(index).jsonl")
    }

    private func logURLsForWriting() -> [URL] {
        [paths.appActivityJSONL] + (1...3).map { historyURL(index: $0) }
    }

    private func deleteAllLogFiles() throws {
        for url in logURLsForWriting() {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func prune(existingEvents: [AppLogEvent]) throws {
        let cutoff = retention.now().addingTimeInterval(-retention.maximumAge)
        let retained = existingEvents
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }

        if retained.isEmpty {
            try deleteAllLogFiles()
            return
        }

        let chunks = Array(chunksWithinMaximumSize(for: retained).suffix(4))
        let chunksForURLs = Array(chunks.reversed())
        let urls = logURLsForWriting()

        for (index, url) in urls.enumerated() {
            if index < chunksForURLs.count {
                let data = try encodedData(for: chunksForURLs[index])
                try SecureFilePermissions.writeOwnerOnlyFile(data, to: url, fileManager: fileManager)
            } else if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func chunksWithinMaximumSize(for events: [AppLogEvent]) -> [[AppLogEvent]] {
        var chunks: [[AppLogEvent]] = []
        var currentChunk: [AppLogEvent] = []

        for event in events {
            let candidate = currentChunk + [event]
            if !currentChunk.isEmpty, encodedByteCount(for: candidate) > retention.maximumBytes {
                chunks.append(currentChunk)
                currentChunk = [event]
            } else {
                currentChunk = candidate
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }

    private func encodedByteCount(for events: [AppLogEvent]) -> Int {
        (try? encodedData(for: events).count) ?? Int.max
    }

    private func encodedData(for events: [AppLogEvent]) throws -> Data {
        var data = Data()
        for event in events {
            var eventData = try encoder.encode(event)
            eventData.append(0x0A)
            data.append(eventData)
        }
        return data
    }
}
