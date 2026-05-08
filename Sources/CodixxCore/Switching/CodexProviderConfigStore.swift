import Foundation

public struct CodexProviderConfigBackup: Equatable, Sendable {
    public var existed: Bool
    public var data: Data?

    public init(existed: Bool, data: Data?) {
        self.existed = existed
        self.data = data
    }
}

public struct CodexProviderConfigStore {
    public let paths: CodixxPaths
    private let fileManager: FileManager

    public init(paths: CodixxPaths = CodixxPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func backupConfig() throws -> CodexProviderConfigBackup {
        guard fileManager.fileExists(atPath: paths.configTOML.path) else {
            return CodexProviderConfigBackup(existed: false, data: nil)
        }
        return CodexProviderConfigBackup(
            existed: true,
            data: try Data(contentsOf: paths.configTOML)
        )
    }

    public func restoreConfig(from backup: CodexProviderConfigBackup) throws {
        if backup.existed, let data = backup.data {
            try fileManager.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
            try data.write(to: paths.configTOML, options: .atomic)
        } else if fileManager.fileExists(atPath: paths.configTOML.path) {
            try fileManager.removeItem(at: paths.configTOML)
        }
    }

    public func writeAPIProvider(
        providerID: String,
        providerName: String,
        baseURL: URL,
        defaultModel: String?
    ) throws {
        try fileManager.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        let existing = (try? String(contentsOf: paths.configTOML, encoding: .utf8)) ?? ""
        let withoutManagedBlock = removeManagedBlock(from: existing)
        let withRootKeys = upsertRootKeys(
            in: withoutManagedBlock,
            keys: [
                "model": defaultModel ?? "gpt-5",
                "model_provider": providerID
            ]
        )
        let managedBlock = """
        # BEGIN CODIXX API PROVIDER
        [model_providers.\(providerID)]
        name = "\(escapeTOMLString(providerName))"
        base_url = "\(escapeTOMLString(baseURL.absoluteString))"
        wire_api = "responses"
        # END CODIXX API PROVIDER
        """

        let config = withRootKeys.trimmingCharacters(in: .newlines)
            + "\n\n"
            + managedBlock
            + "\n"
        try config.write(to: paths.configTOML, atomically: true, encoding: .utf8)
    }

    public func clearManagedAPIProvider() throws {
        guard fileManager.fileExists(atPath: paths.configTOML.path) else { return }
        let existing = try String(contentsOf: paths.configTOML, encoding: .utf8)
        let withoutManagedBlock = removeManagedBlock(from: existing)
        let withoutManagedRootProvider = removeManagedRootModelProvider(from: withoutManagedBlock)
        try withoutManagedRootProvider
            .trimmingCharacters(in: .newlines)
            .appending("\n")
            .write(to: paths.configTOML, atomically: true, encoding: .utf8)
    }

    private func removeManagedBlock(from text: String) -> String {
        guard let start = text.range(of: "# BEGIN CODIXX API PROVIDER"),
              let end = text.range(of: "# END CODIXX API PROVIDER", range: start.upperBound..<text.endIndex)
        else {
            return text
        }

        var updated = text
        updated.removeSubrange(start.lowerBound..<end.upperBound)
        return updated
    }

    private func removeManagedRootModelProvider(from text: String) -> String {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let firstTableIndex = lines.firstIndex { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("[")
        } ?? lines.endIndex
        let rootLines = Array(lines[..<firstTableIndex]).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("model_provider =") else { return true }
            return !trimmed.contains("\"codixx-")
        }
        return (rootLines + Array(lines[firstTableIndex...])).joined(separator: "\n")
    }

    private func upsertRootKeys(in text: String, keys: [String: String]) -> String {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let firstTableIndex = lines.firstIndex { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("[")
        } ?? lines.endIndex
        var rootLines = Array(lines[..<firstTableIndex])
        let remainingLines = Array(lines[firstTableIndex...])

        rootLines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return keys.keys.contains { key in
                trimmed.hasPrefix("\(key) =")
            }
        }
        while rootLines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            rootLines.removeLast()
        }

        let insertedKeys = keys
            .sorted { $0.key < $1.key }
            .map { "\($0.key) = \"\(escapeTOMLString($0.value))\"" }
        let rebuiltRoot = rootLines + insertedKeys

        if remainingLines.isEmpty {
            return rebuiltRoot.joined(separator: "\n")
        }
        return (rebuiltRoot + [""] + remainingLines).joined(separator: "\n")
    }

    private func escapeTOMLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
