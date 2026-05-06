import Foundation

public protocol AtomicAuthFileWriting {
    func write(_ data: Data, to url: URL, fileManager: FileManager) throws
}

public enum SecureFilePermissions {
    public static let ownerOnlyFile = 0o600
    public static let ownerOnlyDirectory = 0o700

    public static func secureDirectory(_ url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: ownerOnlyDirectory], ofItemAtPath: url.path)
    }

    public static func writeOwnerOnlyFile(_ data: Data, to url: URL, fileManager: FileManager = .default) throws {
        try secureDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        guard fileManager.createFile(
            atPath: url.path,
            contents: data,
            attributes: [.posixPermissions: ownerOnlyFile]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try fileManager.setAttributes([.posixPermissions: ownerOnlyFile], ofItemAtPath: url.path)
    }
}

public struct AtomicFileWriter: AtomicAuthFileWriting, Sendable {
    public init() {}

    public func write(_ data: Data, to url: URL, fileManager: FileManager = .default) throws {
        let directory = url.deletingLastPathComponent()
        try SecureFilePermissions.secureDirectory(directory, fileManager: fileManager)
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")

        do {
            try SecureFilePermissions.writeOwnerOnlyFile(data, to: temporaryURL, fileManager: fileManager)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
            try fileManager.setAttributes([.posixPermissions: SecureFilePermissions.ownerOnlyFile], ofItemAtPath: url.path)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
