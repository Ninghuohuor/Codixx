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
    public let paths: CodixxPaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(paths: CodixxPaths = CodixxPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func append(_ event: SwitchAuditEvent) throws {
        try fileManager.createDirectory(at: paths.applicationSupport, withIntermediateDirectories: true)
        var data = try encoder.encode(event)
        data.append(0x0A)
        if fileManager.fileExists(atPath: paths.switchAuditJSONL.path) {
            let handle = try FileHandle(forWritingTo: paths.switchAuditJSONL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: paths.switchAuditJSONL)
        }
    }

    public func loadEvents() throws -> [SwitchAuditEvent] {
        guard fileManager.fileExists(atPath: paths.switchAuditJSONL.path) else { return [] }
        let data = try Data(contentsOf: paths.switchAuditJSONL)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? decoder.decode(SwitchAuditEvent.self, from: Data(line.utf8))
            }
    }
}
