import Foundation

public enum ProtectedPathChange: Equatable, Sendable {
    case removed(String)
    case typeChanged(String)
    case sharpFileShrink(String)
    case sharpDirectoryEntryDrop(String)
}

public struct ProtectedPathSnapshot: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case file(size: UInt64)
            case directory(entryCount: Int)
            case missing
        }

        public var path: String
        public var kind: Kind

        public init(path: String, kind: Kind) {
            self.path = path
            self.kind = kind
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public static func capture(
        paths: CodixxPaths,
        fileManager: FileManager = .default
    ) throws -> ProtectedPathSnapshot {
        let sqliteURLs = ((try? fileManager.contentsOfDirectory(atPath: paths.codexHome.path)) ?? [])
            .filter { name in
                (name.hasPrefix("state_") && name.hasSuffix(".sqlite"))
                    || (name.hasPrefix("logs_") && name.hasSuffix(".sqlite"))
            }
            .map { paths.codexHome.appendingPathComponent($0) }

        let protectedURLs = [
            paths.codexHome.appendingPathComponent("sessions", isDirectory: true),
            paths.codexHome.appendingPathComponent("archived_sessions", isDirectory: true),
            paths.codexHome.appendingPathComponent("session_index.jsonl")
        ] + sqliteURLs

        let entries = try protectedURLs.map { url in
            try Entry(path: url.path, kind: kind(for: url, fileManager: fileManager))
        }
        return ProtectedPathSnapshot(entries: entries)
    }

    public func abnormalChanges(comparedTo after: ProtectedPathSnapshot) -> [ProtectedPathChange] {
        let afterByPath = Dictionary(uniqueKeysWithValues: after.entries.map { ($0.path, $0.kind) })
        return entries.compactMap { before in
            guard let afterKind = afterByPath[before.path] else {
                return .removed(before.path)
            }
            switch (before.kind, afterKind) {
            case (.missing, _):
                return nil
            case (_, .missing):
                return .removed(before.path)
            case (.file(let beforeSize), .file(let afterSize)):
                return afterSize < beforeSize / 2 ? .sharpFileShrink(before.path) : nil
            case (.directory(let beforeCount), .directory(let afterCount)):
                return afterCount < beforeCount / 2 ? .sharpDirectoryEntryDrop(before.path) : nil
            default:
                return .typeChanged(before.path)
            }
        }
    }

    private static func kind(for url: URL, fileManager: FileManager) throws -> Entry.Kind {
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            let count = (try? fileManager.contentsOfDirectory(atPath: url.path).count) ?? 0
            return .directory(entryCount: count)
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        return .file(size: size)
    }
}
