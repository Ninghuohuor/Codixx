import Foundation

public struct JSONFileStore<Value: Codable> {
    public var url: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        url: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONFileStore.makeEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.url = url
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    public func load() throws -> Value {
        let data = try Data(contentsOf: url)
        return try decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try encoder.encode(value)
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")

        do {
            try data.write(to: temporaryURL)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
