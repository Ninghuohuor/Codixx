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

public final class AppActivityLog: @unchecked Sendable {
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
    private let cacheLock = NSLock()
    private var cachedFiles: [String: CachedFile] = [:]
    private var cachedEvents: [AppLogEvent] = []
    private var lastPrunedAt: Date?
    private var oldestEventAt: Date?

    private struct FileInfo: Equatable {
        var number: UInt64
        var size: UInt64
        var modifiedAt: Date?
    }

    private struct CachedFile {
        var info: FileInfo
        var events: [AppLogEvent]
        var tail: Data
        var pendingLine: Data
        var pendingEventID: UUID?
    }

    // Counters make the incremental-read contract verifiable without timing tests.
    private(set) var bytesRead: UInt64 = 0
    private(set) var decodedEventCount = 0

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
        let lockURL = paths.applicationSupport.appendingPathComponent("app_activity.jsonl.lock")
        try FileLock(url: lockURL).withExclusiveLock {
            cacheLock.lock()
            defer { cacheLock.unlock() }
            let timestamp = retention.now()
            var data = try encoder.encode(event)
            data.append(0x0a)
            let currentSize = fileInfo(for: paths.appActivityJSONL)?.size ?? 0
            let cutoff = timestamp.addingTimeInterval(-retention.maximumAge)
            let needsMaintenance = (lastPrunedAt.map { timestamp.timeIntervalSince($0) >= 3_600 } ?? true)
                || (oldestEventAt.map { $0 < cutoff } ?? false)
            if needsMaintenance || (currentSize > 0 && currentSize + UInt64(data.count) > UInt64(max(1, retention.maximumBytes))) {
                try prune(existingEvents: loadEventsWithoutPruning() + [event])
                lastPrunedAt = timestamp
                cachedFiles.removeAll()
                cachedEvents.removeAll()
                return
            }
            guard event.timestamp >= cutoff else { return }
            if fileManager.fileExists(atPath: paths.appActivityJSONL.path) {
                try fileManager.setAttributes([.posixPermissions: SecureFilePermissions.ownerOnlyFile], ofItemAtPath: paths.appActivityJSONL.path)
                let handle = try FileHandle(forUpdating: paths.appActivityJSONL)
                defer { try? handle.close() }
                let end = try handle.seekToEnd()
                if end > 0 {
                    try handle.seek(toOffset: end - 1)
                    let lastByte = try handle.read(upToCount: 1)
                    try handle.seekToEnd()
                    if lastByte != Data([0x0a]) { try handle.write(contentsOf: Data([0x0a])) }
                }
                try handle.write(contentsOf: data)
            } else {
                try SecureFilePermissions.writeOwnerOnlyFile(data, to: paths.appActivityJSONL, fileManager: fileManager)
            }
            oldestEventAt = oldestEventAt.map { min($0, event.timestamp) } ?? event.timestamp
        }
    }

    public func loadEvents() throws -> [AppLogEvent] {
        guard fileManager.fileExists(atPath: paths.applicationSupport.path) else { return [] }
        let lockURL = paths.applicationSupport.appendingPathComponent("app_activity.jsonl.lock")
        return try FileLock(url: lockURL).withExclusiveLock {
            cacheLock.lock()
            defer { cacheLock.unlock() }
            // Readers preserve the writer's retained history, even if their
            // clocks or retention settings differ. Expiry is enforced on append.
            return try loadEventsWithoutPruning()
        }
    }

    private func loadEventsWithoutPruning() throws -> [AppLogEvent] {
        var changed = false
        for url in logURLsForLoading() {
            guard let info = fileInfo(for: url) else {
                if cachedFiles.removeValue(forKey: url.path) != nil { changed = true }
                continue
            }
            let cached = cachedFiles[url.path]
            if cached?.info == info { continue }
            cachedFiles[url.path] = try readFile(url, info: info, cached: cached)
            changed = true
        }
        if changed {
            cachedEvents = cachedFiles.values.flatMap(\.events).sorted { $0.timestamp < $1.timestamp }
            oldestEventAt = cachedEvents.first?.timestamp
        }
        return cachedEvents
    }

    private func fileInfo(for url: URL) -> FileInfo? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let number = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return FileInfo(number: number.uint64Value, size: size.uint64Value, modifiedAt: attributes[.modificationDate] as? Date)
    }

    private func readFile(_ url: URL, info: FileInfo, cached: CachedFile?) throws -> CachedFile {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var events: [AppLogEvent] = []
        var data = Data()
        if let cached, info.number == cached.info.number, info.size > cached.info.size {
            // Check a small boundary before trusting an append. Truncation,
            // replacement, and rewrites invalidate the previous checkpoint.
            try handle.seek(toOffset: cached.info.size - UInt64(cached.tail.count))
            let suffix = try handle.readToEnd() ?? Data()
            bytesRead += UInt64(suffix.count)
            if suffix.starts(with: cached.tail) {
                events = cached.events
                if events.last?.id == cached.pendingEventID, cached.pendingEventID != nil { events.removeLast() }
                data = cached.pendingLine
                data.append(suffix.dropFirst(cached.tail.count))
            } else {
                try handle.seek(toOffset: 0)
                data = try handle.readToEnd() ?? Data()
                bytesRead += UInt64(data.count)
            }
        } else {
            data = try handle.readToEnd() ?? Data()
            bytesRead += UInt64(data.count)
        }
        var pendingLine = Data()
        var pendingEventID: UUID?
        let lines = data.split(separator: 0x0a, omittingEmptySubsequences: true)
        for (index, line) in lines.enumerated() {
            let event = autoreleasepool { try? decoder.decode(AppLogEvent.self, from: Data(line)) }
            if let event {
                events.append(event)
                decodedEventCount += 1
            }
            if index == lines.count - 1 && data.last != 0x0a {
                pendingLine = Data(line)
                pendingEventID = event?.id
            }
        }
        // A pending line includes the previous suffix, so it is also a valid
        // boundary check when an append splits a UTF-8 character or JSON record.
        let tail: Data
        if data.count >= 64 || info.size <= UInt64(data.count) {
            tail = Data(data.suffix(64))
        } else {
            try handle.seek(toOffset: info.size > 64 ? info.size - 64 : 0)
            tail = try handle.readToEnd() ?? Data()
            bytesRead += UInt64(tail.count)
        }
        return CachedFile(info: info, events: events, tail: tail, pendingLine: pendingLine, pendingEventID: pendingEventID)
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
            oldestEventAt = nil
            return
        }

        let chunks = Array(try chunksWithinMaximumSize(for: retained).suffix(4))
        let chunksForURLs = Array(chunks.reversed())
        oldestEventAt = chunksForURLs.last?.first?.timestamp
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

    private func chunksWithinMaximumSize(for events: [AppLogEvent]) throws -> [[AppLogEvent]] {
        var chunks: [[AppLogEvent]] = []
        var currentChunk: [AppLogEvent] = []
        var currentBytes = 0

        for event in events {
            let eventBytes = try encoder.encode(event).count + 1 // JSONL newline
            if !currentChunk.isEmpty, currentBytes + eventBytes > retention.maximumBytes {
                chunks.append(currentChunk)
                currentChunk = [event]
                currentBytes = eventBytes
            } else {
                currentChunk.append(event)
                currentBytes += eventBytes
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
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
