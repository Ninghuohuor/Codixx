import Foundation

public enum AccountStoreError: Error, Equatable, LocalizedError {
    case authFileNotFound(String)
    case duplicateFingerprint(String)
    case invalidAuthSnapshot
    case missingFingerprintSource
    case snapshotNotFound(String)
    case keychainError(String)
    case accountNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .authFileNotFound(let path):
            return "Codex auth file was not found at \(path)"
        case .duplicateFingerprint(let fingerprint):
            return "An account with fingerprint \(fingerprint) already exists"
        case .invalidAuthSnapshot:
            return "Codex auth snapshot is not valid JSON object data"
        case .missingFingerprintSource:
            return "Codex auth snapshot does not contain account_id, email, or access_token"
        case .snapshotNotFound(let fingerprint):
            return "No auth snapshot exists for fingerprint \(fingerprint)"
        case .keychainError(let message):
            return "Keychain operation failed. \(message)"
        case .accountNotFound(let id):
            return "No account exists with id \(id.uuidString)"
        }
    }
}

public protocol AuthSnapshotVault {
    func save(snapshot: AuthSnapshot, fingerprint: String) throws
    func load(fingerprint: String) throws -> AuthSnapshot
    func delete(fingerprint: String) throws
}

public struct AccountStore {
    public let paths: CodixxPaths
    public let metadataStore: AccountMetadataStore
    private let vault: AuthSnapshotVault
    private let apiKeyVault: APIKeyVault
    private let quotaHistoryStore: AccountQuotaHistoryStore
    private let now: () -> Date
    private let idGenerator: () -> UUID

    public init(
        paths: CodixxPaths = CodixxPaths(),
        metadataStore: AccountMetadataStore? = nil,
        vault: AuthSnapshotVault,
        apiKeyVault: APIKeyVault = KeychainAPIKeyVault(),
        quotaHistoryStore: AccountQuotaHistoryStore? = nil,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.paths = paths
        self.metadataStore = metadataStore ?? AccountMetadataStore(paths: paths)
        self.vault = vault
        self.apiKeyVault = apiKeyVault
        self.quotaHistoryStore = quotaHistoryStore ?? AccountQuotaHistoryStore(paths: paths)
        self.now = now
        self.idGenerator = idGenerator
    }

    public func saveCurrentAuth(alias: String) throws -> CodixxAccount {
        guard FileManager.default.fileExists(atPath: paths.authJSON.path) else {
            throw AccountStoreError.authFileNotFound(paths.authJSON.path)
        }

        let snapshot = try AuthSnapshot(jsonData: Data(contentsOf: paths.authJSON))
        return try save(snapshot: snapshot, alias: alias)
    }

    public func importAuthSnapshot(from url: URL, alias: String) throws -> CodixxAccount {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AccountStoreError.authFileNotFound(url.path)
        }

        let snapshot = try AuthSnapshot(jsonData: Data(contentsOf: url))
        return try save(snapshot: snapshot, alias: alias)
    }

    private func save(snapshot: AuthSnapshot, alias: String) throws -> CodixxAccount {
        let fingerprint = try AccountFingerprint.generate(from: snapshot)
        var metadata = try metadataStore.load()
        let timestamp = now()
        let profile = AuthProfileReader.profile(from: snapshot)

        if let existingIndex = metadata.accounts.firstIndex(where: { $0.fingerprint == fingerprint }) {
            try vault.save(snapshot: snapshot, fingerprint: fingerprint)
            metadata.accounts[existingIndex].updatedAt = timestamp
            metadata.accounts[existingIndex].lastUsedAt = timestamp
            metadata.accounts[existingIndex].membershipExpiresAt = profile?.membershipExpiresAt ?? metadata.accounts[existingIndex].membershipExpiresAt
            metadata.accounts[existingIndex].quota.planType = profile?.planType ?? metadata.accounts[existingIndex].quota.planType
            try metadataStore.save(metadata)
            return metadata.accounts[existingIndex]
        }

        let id = idGenerator()
        var quota = AccountQuotaState.unknown(accountId: id.uuidString, alias: alias)
        let restoredHistory = try quotaHistoryStore.record(for: fingerprint)
        if var historicalQuota = restoredHistory?.quota {
            historicalQuota.accountId = id.uuidString
            historicalQuota.alias = alias
            quota = historicalQuota
        }
        quota.planType = profile?.planType ?? quota.planType
        let account = CodixxAccount(
            id: id,
            alias: alias,
            fingerprint: fingerprint,
            createdAt: timestamp,
            updatedAt: timestamp,
            lastUsedAt: timestamp,
            membershipExpiresAt: profile?.membershipExpiresAt ?? restoredHistory?.membershipExpiresAt,
            quota: quota,
            isEnabled: true,
            priority: metadata.accounts.count
        )

        try vault.save(snapshot: snapshot, fingerprint: fingerprint)
        metadata.accounts.append(account)
        try metadataStore.save(metadata)
        return account
    }

    public func saveAPIProvider(
        alias: String,
        providerName: String,
        baseURL: URL,
        apiKey: String,
        defaultModel: String?
    ) throws -> CodixxAccount {
        let timestamp = now()
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedAlias = trimmedAlias.isEmpty ? providerName : trimmedAlias
        let keyFingerprint = APIKeyFingerprint.generate(apiKey: apiKey)
        let accountFingerprint = "api-provider:\(keyFingerprint)"
        var metadata = try metadataStore.load()

        try apiKeyVault.save(apiKey: apiKey, fingerprint: keyFingerprint)

        if let index = metadata.accounts.firstIndex(where: { $0.fingerprint == accountFingerprint }) {
            metadata.accounts[index].alias = savedAlias
            metadata.accounts[index].updatedAt = timestamp
            metadata.accounts[index].lastUsedAt = timestamp
            metadata.accounts[index].apiProvider = APIProviderAccount(
                providerName: providerName,
                baseURL: baseURL,
                defaultModel: defaultModel,
                keyFingerprint: keyFingerprint
            )
            metadata.accounts[index].quota.alias = savedAlias
            try metadataStore.save(metadata)
            return metadata.accounts[index]
        }

        let id = idGenerator()
        let account = CodixxAccount(
            id: id,
            alias: savedAlias,
            fingerprint: accountFingerprint,
            credentialKind: .apiProvider,
            apiProvider: APIProviderAccount(
                providerName: providerName,
                baseURL: baseURL,
                defaultModel: defaultModel,
                keyFingerprint: keyFingerprint
            ),
            createdAt: timestamp,
            updatedAt: timestamp,
            lastUsedAt: timestamp,
            quota: .unknown(accountId: id.uuidString, alias: savedAlias),
            isEnabled: true,
            priority: metadata.accounts.count
        )
        metadata.accounts.append(account)
        try metadataStore.save(metadata)
        return account
    }

    public func renameAccount(_ id: UUID, alias: String) throws -> CodixxAccount {
        var metadata = try metadataStore.load()
        guard let index = metadata.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountStoreError.accountNotFound(id)
        }

        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        metadata.accounts[index].alias = trimmedAlias.isEmpty ? metadata.accounts[index].alias : trimmedAlias
        metadata.accounts[index].quota.alias = metadata.accounts[index].alias
        metadata.accounts[index].updatedAt = now()
        try metadataStore.save(metadata)
        return metadata.accounts[index]
    }

    public func updateAPIProvider(
        _ id: UUID,
        alias: String,
        baseURL: URL,
        apiKey: String?,
        defaultModel: String?,
        balanceQuery: APIBalanceQueryConfig? = nil
    ) throws -> CodixxAccount {
        var metadata = try metadataStore.load()
        guard let index = metadata.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountStoreError.accountNotFound(id)
        }
        guard let existingProvider = metadata.accounts[index].apiProvider else {
            throw AccountStoreError.snapshotNotFound(id.uuidString)
        }

        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedAlias = trimmedAlias.isEmpty ? metadata.accounts[index].alias : trimmedAlias
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keyFingerprint: String
        if trimmedKey.isEmpty {
            keyFingerprint = existingProvider.keyFingerprint
        } else {
            keyFingerprint = APIKeyFingerprint.generate(apiKey: trimmedKey)
            try apiKeyVault.save(apiKey: trimmedKey, fingerprint: keyFingerprint)
            if keyFingerprint != existingProvider.keyFingerprint {
                try apiKeyVault.delete(fingerprint: existingProvider.keyFingerprint)
            }
        }

        metadata.accounts[index].alias = savedAlias
        metadata.accounts[index].fingerprint = "api-provider:\(keyFingerprint)"
        metadata.accounts[index].updatedAt = now()
        metadata.accounts[index].apiProvider = APIProviderAccount(
            providerName: savedAlias,
            baseURL: baseURL,
            defaultModel: defaultModel,
            keyFingerprint: keyFingerprint,
            balanceQuery: balanceQuery ?? existingProvider.balanceQuery
        )
        metadata.accounts[index].quota.alias = savedAlias
        try metadataStore.save(metadata)
        return metadata.accounts[index]
    }

    public func updateAPIBalanceQuery(_ id: UUID, balanceQuery: APIBalanceQueryConfig) throws -> CodixxAccount {
        var metadata = try metadataStore.load()
        guard let index = metadata.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountStoreError.accountNotFound(id)
        }
        guard var provider = metadata.accounts[index].apiProvider else {
            throw AccountStoreError.snapshotNotFound(id.uuidString)
        }

        provider.balanceQuery = balanceQuery
        metadata.accounts[index].apiProvider = provider
        metadata.accounts[index].updatedAt = now()
        try metadataStore.save(metadata)
        return metadata.accounts[index]
    }

    public func deleteAccount(_ id: UUID) throws {
        var metadata = try metadataStore.load()
        guard let index = metadata.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountStoreError.accountNotFound(id)
        }

        let account = metadata.accounts.remove(at: index)
        try quotaHistoryStore.record(account, timestamp: now())
        if let apiProvider = account.apiProvider {
            try apiKeyVault.delete(fingerprint: apiProvider.keyFingerprint)
        } else {
            try vault.delete(fingerprint: account.fingerprint)
        }
        try metadataStore.save(metadata)
    }
}
