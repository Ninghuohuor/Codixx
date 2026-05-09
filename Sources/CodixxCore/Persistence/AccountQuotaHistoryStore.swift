import Foundation

public struct AccountQuotaHistoryList: Codable, Equatable, Sendable {
    public var records: [String: AccountQuotaHistoryRecord]

    public init(records: [String: AccountQuotaHistoryRecord] = [:]) {
        self.records = records
    }
}

public struct AccountQuotaHistoryRecord: Codable, Equatable, Sendable {
    public var quota: AccountQuotaState
    public var membershipExpiresAt: Date?
    public var updatedAt: Date

    public init(quota: AccountQuotaState, membershipExpiresAt: Date?, updatedAt: Date) {
        self.quota = quota
        self.membershipExpiresAt = membershipExpiresAt
        self.updatedAt = updatedAt
    }
}

public struct AccountQuotaHistoryStore {
    public let paths: CodixxPaths

    private let fileManager: FileManager
    private let fileStore: JSONFileStore<AccountQuotaHistoryList>

    public init(paths: CodixxPaths = CodixxPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.fileStore = JSONFileStore(url: paths.accountQuotaHistoryJSON, fileManager: fileManager)
    }

    public func load() throws -> AccountQuotaHistoryList {
        guard fileManager.fileExists(atPath: paths.accountQuotaHistoryJSON.path) else {
            return AccountQuotaHistoryList()
        }
        return try fileStore.load()
    }

    public func save(_ list: AccountQuotaHistoryList) throws {
        try paths.createApplicationSupportDirectories(fileManager: fileManager)
        try fileStore.save(list)
    }

    public func record(_ account: CodixxAccount, timestamp: Date) throws {
        var list = try load()
        list.records[account.fingerprint] = AccountQuotaHistoryRecord(
            quota: account.quota,
            membershipExpiresAt: account.membershipExpiresAt,
            updatedAt: timestamp
        )
        try save(list)
    }

    public func record(for fingerprint: String) throws -> AccountQuotaHistoryRecord? {
        try load().records[fingerprint]
    }
}
