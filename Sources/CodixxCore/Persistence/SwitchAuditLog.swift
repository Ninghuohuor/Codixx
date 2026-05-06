import Foundation

public enum SwitchTrigger: String, Codable, Equatable, Sendable {
    case manual
    case autoPrimaryThreshold
    case recovery
}

public enum SwitchAuditResult: String, Codable, Equatable, Sendable {
    case success
    case skippedNoCandidate
    case failedBeforeWrite
    case failedDuringWrite
    case failedValidation
    case rolledBack
    case rollbackFailed
}

public struct SwitchAuditEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var trigger: SwitchTrigger
    public var sourceAccountId: UUID?
    public var sourceAlias: String?
    public var targetAccountId: UUID?
    public var targetAlias: String?
    public var sourcePrimaryUsedPercent: Double?
    public var sourceSecondaryUsedPercent: Double?
    public var threshold: Double?
    public var result: SwitchAuditResult
    public var errorSummary: String?
    public var backupPath: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        trigger: SwitchTrigger,
        sourceAccountId: UUID?,
        sourceAlias: String?,
        targetAccountId: UUID?,
        targetAlias: String?,
        sourcePrimaryUsedPercent: Double?,
        sourceSecondaryUsedPercent: Double?,
        threshold: Double?,
        result: SwitchAuditResult,
        errorSummary: String?,
        backupPath: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.trigger = trigger
        self.sourceAccountId = sourceAccountId
        self.sourceAlias = sourceAlias
        self.targetAccountId = targetAccountId
        self.targetAlias = targetAlias
        self.sourcePrimaryUsedPercent = sourcePrimaryUsedPercent
        self.sourceSecondaryUsedPercent = sourceSecondaryUsedPercent
        self.threshold = threshold
        self.result = result
        self.errorSummary = errorSummary
        self.backupPath = backupPath
    }
}

public struct SwitchAuditLog {
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
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
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
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func append(_ event: SwitchAuditEvent) throws {
        try paths.createApplicationSupportDirectories(fileManager: fileManager)
        try prune(existingEvents: loadEventsWithoutPruning() + [event])
    }

    public func loadEvents() throws -> [SwitchAuditEvent] {
        try prune(existingEvents: loadEventsWithoutPruning())
        return try loadEventsWithoutPruning()
    }

    private func loadEventsWithoutPruning() throws -> [SwitchAuditEvent] {
        var events: [SwitchAuditEvent] = []
        for url in logURLsForLoading() {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else { continue }
            events.append(contentsOf: text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    try? decoder.decode(SwitchAuditEvent.self, from: Data(line.utf8))
                }
            )
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    private func logURLsForLoading() -> [URL] {
        [3, 2, 1].map { historyURL(index: $0) } + [paths.switchAuditJSONL]
    }

    private func historyURL(index: Int) -> URL {
        paths.applicationSupport.appendingPathComponent("switch_audit.\(index).jsonl")
    }

    private func logURLsForWriting() -> [URL] {
        [paths.switchAuditJSONL] + (1...3).map { historyURL(index: $0) }
    }

    private func deleteAllLogFiles() throws {
        for url in logURLsForWriting() {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func prune(existingEvents: [SwitchAuditEvent]) throws {
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

    private func chunksWithinMaximumSize(for events: [SwitchAuditEvent]) -> [[SwitchAuditEvent]] {
        var chunks: [[SwitchAuditEvent]] = []
        var currentChunk: [SwitchAuditEvent] = []

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

    private func encodedByteCount(for events: [SwitchAuditEvent]) -> Int {
        (try? encodedData(for: events).count) ?? Int.max
    }

    private func encodedData(for events: [SwitchAuditEvent]) throws -> Data {
        var data = Data()
        for event in events {
            var eventData = try encoder.encode(event)
            eventData.append(0x0A)
            data.append(eventData)
        }
        return data
    }
}
