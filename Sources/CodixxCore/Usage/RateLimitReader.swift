import Foundation

public struct RateLimitObservation: Codable, Equatable, Sendable {
    public var primaryUsedPercent: Double
    public var primaryWindowMinutes: Int
    public var primaryResetsAt: Date
    public var secondaryUsedPercent: Double
    public var secondaryWindowMinutes: Int
    public var secondaryResetsAt: Date
    public var observedAt: Date
    public var sourceFile: String

    public init(
        primaryUsedPercent: Double,
        primaryWindowMinutes: Int,
        primaryResetsAt: Date,
        secondaryUsedPercent: Double,
        secondaryWindowMinutes: Int,
        secondaryResetsAt: Date,
        observedAt: Date,
        sourceFile: String
    ) {
        self.primaryUsedPercent = primaryUsedPercent
        self.primaryWindowMinutes = primaryWindowMinutes
        self.primaryResetsAt = primaryResetsAt
        self.secondaryUsedPercent = secondaryUsedPercent
        self.secondaryWindowMinutes = secondaryWindowMinutes
        self.secondaryResetsAt = secondaryResetsAt
        self.observedAt = observedAt
        self.sourceFile = sourceFile
    }

    public func accountQuotaState(accountId: String, alias: String, now: Date) -> AccountQuotaState {
        AccountQuotaState(
            accountId: accountId,
            alias: alias,
            primaryUsedPercent: primaryUsedPercent,
            primaryWindowMinutes: primaryWindowMinutes,
            primaryResetsAt: primaryResetsAt,
            secondaryUsedPercent: secondaryUsedPercent,
            secondaryWindowMinutes: secondaryWindowMinutes,
            secondaryResetsAt: secondaryResetsAt,
            lastObservedAt: observedAt,
            confidence: QuotaConfidence.observed(at: observedAt, now: now)
        )
    }
}

public struct RateLimitReader {
    public let paths: CodixxPaths
    public let cursorStore: ParseCursorStore

    private let maxReadBytesPerFile: Int64
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    public init(
        paths: CodixxPaths = CodixxPaths(),
        cursorStore: ParseCursorStore? = nil,
        fileManager: FileManager = .default,
        maxReadBytesPerFile: Int64 = 2 * 1_024 * 1_024
    ) {
        self.paths = paths
        self.cursorStore = cursorStore ?? ParseCursorStore(paths: paths, fileManager: fileManager)
        self.fileManager = fileManager
        self.maxReadBytesPerFile = maxReadBytesPerFile
        self.decoder = JSONDecoder()
    }

    public func readNewObservations() throws -> [RateLimitObservation] {
        var cursorState = try cursorStore.load()
        var observations: [RateLimitObservation] = []

        for file in try jsonlFiles() {
            let storedOffset = max(0, cursorState.offset(for: file))
            let fileSize = try sizeOfFile(at: file)
            let previousOffset = storedOffset > fileSize ? 0 : storedOffset
            guard previousOffset < fileSize else { continue }
            let readOffset = Self.readOffset(previousOffset: previousOffset, fileSize: fileSize, maxReadBytes: maxReadBytesPerFile)
            let byteCount = min(fileSize - readOffset, maxReadBytesPerFile)

            let readResult = try Self.readCompleteObservations(
                from: file,
                offset: readOffset,
                byteCount: byteCount
            )
            observations.append(contentsOf: readResult.observations)
            cursorState.setOffset(readOffset + readResult.consumedByteCount, for: file)
        }

        try cursorStore.save(cursorState)
        return observations.sorted {
            if $0.observedAt == $1.observedAt {
                return $0.sourceFile < $1.sourceFile
            }
            return $0.observedAt < $1.observedAt
        }
    }

    public static func readObservations(from file: URL, offset: Int64, byteCount: Int64) throws -> [RateLimitObservation] {
        try readCompleteObservations(from: file, offset: offset, byteCount: byteCount).observations
    }

    private static func readCompleteObservations(
        from file: URL,
        offset: Int64,
        byteCount: Int64
    ) throws -> (observations: [RateLimitObservation], consumedByteCount: Int64) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: Int(byteCount)) ?? Data()
        guard !data.isEmpty else {
            return ([], 0)
        }
        guard let lastNewlineIndex = data.lastIndex(of: 0x0A) else {
            return ([], 0)
        }
        let consumedByteCount = data.distance(from: data.startIndex, to: data.index(after: lastNewlineIndex))
        let completeData = data.prefix(consumedByteCount)
        guard let completeContent = String(data: completeData, encoding: .utf8) else {
            return ([], 0)
        }

        let observations = completeContent
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in parseLine(String(line), sourceFile: file.resolvingSymlinksInPath().path) }
        return (observations, Int64(consumedByteCount))
    }

    private static func parseLine(_ line: String, sourceFile: String) -> RateLimitObservation? {
        let decoder = JSONDecoder()
        guard line.contains(#""rate_limits""#),
              let data = line.data(using: .utf8),
              let event = try? decoder.decode(RateLimitEvent.self, from: data),
              let rateLimits = event.rateLimits
        else {
            return nil
        }

        return RateLimitObservation(
            primaryUsedPercent: rateLimits.primary.usedPercent,
            primaryWindowMinutes: rateLimits.primary.windowMinutes,
            primaryResetsAt: Date(timeIntervalSince1970: TimeInterval(rateLimits.primary.resetsAt)),
            secondaryUsedPercent: rateLimits.secondary.usedPercent,
            secondaryWindowMinutes: rateLimits.secondary.windowMinutes,
            secondaryResetsAt: Date(timeIntervalSince1970: TimeInterval(rateLimits.secondary.resetsAt)),
            observedAt: parseISO8601Date(event.timestamp) ?? Date(timeIntervalSince1970: 0),
            sourceFile: sourceFile
        )
    }

    private func jsonlFiles() throws -> [URL] {
        let sessions = paths.codexHome.appendingPathComponent("sessions", isDirectory: true)
        let archivedSessions = paths.codexHome.appendingPathComponent("archived_sessions", isDirectory: true)
        var files: [URL] = []

        files.append(contentsOf: try recursiveJSONLFiles(in: sessions))
        files.append(contentsOf: try directJSONLFiles(in: archivedSessions))

        return files.sorted { $0.path < $1.path }
    }

    private func recursiveJSONLFiles(in directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: resourceKeys)
            return values.isRegularFile == true && url.pathExtension == "jsonl" ? url : nil
        }
    }

    private func directJSONLFiles(in directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true && url.pathExtension == "jsonl"
            }
    }

    private func sizeOfFile(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? Int64((attributes[.size] as? Int) ?? 0)
    }

    private static func readOffset(previousOffset: Int64, fileSize: Int64, maxReadBytes: Int64) -> Int64 {
        guard previousOffset == 0, fileSize > maxReadBytes else {
            return previousOffset
        }
        return max(0, fileSize - maxReadBytes)
    }

    private static func parseISO8601Date(_ text: String?) -> Date? {
        guard let text else { return nil }

        let wholeSecondFormatter = ISO8601DateFormatter()
        wholeSecondFormatter.formatOptions = [.withInternetDateTime]
        if let date = wholeSecondFormatter.date(from: text) {
            return date
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: text)
    }
}

private struct RateLimitEvent: Decodable {
    var timestamp: String?
    var rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case rateLimits = "rate_limits"
    }
}

private struct RateLimits: Decodable {
    var primary: RateLimitWindow
    var secondary: RateLimitWindow
}

private struct RateLimitWindow: Decodable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Int64

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}
