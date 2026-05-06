import Foundation

public struct AccountMetadataList: Codable, Equatable, Sendable {
    public var accounts: [CodixxAccount]

    public init(accounts: [CodixxAccount] = []) {
        self.accounts = accounts
    }
}

public struct AccountMetadataStore {
    public var paths: CodixxPaths

    private let fileManager: FileManager
    private let fileStore: JSONFileStore<AccountMetadataList>

    public init(paths: CodixxPaths = CodixxPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.fileStore = JSONFileStore(url: paths.accountsJSON, fileManager: fileManager)
    }

    public func load() throws -> AccountMetadataList {
        guard fileManager.fileExists(atPath: paths.accountsJSON.path) else {
            return AccountMetadataList()
        }

        return try fileStore.load()
    }

    public func save(_ list: AccountMetadataList) throws {
        try paths.createApplicationSupportDirectories(fileManager: fileManager)
        try fileStore.save(list)
    }
}
