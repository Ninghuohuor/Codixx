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
    private let now: () -> Date
    private let idGenerator: () -> UUID

    public init(
        paths: CodixxPaths = CodixxPaths(),
        metadataStore: AccountMetadataStore? = nil,
        vault: AuthSnapshotVault,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.paths = paths
        self.metadataStore = metadataStore ?? AccountMetadataStore(paths: paths)
        self.vault = vault
        self.now = now
        self.idGenerator = idGenerator
    }

    public func saveCurrentAuth(alias: String) throws -> CodixxAccount {
        guard FileManager.default.fileExists(atPath: paths.authJSON.path) else {
            throw AccountStoreError.authFileNotFound(paths.authJSON.path)
        }

        let snapshot = try AuthSnapshot(jsonData: Data(contentsOf: paths.authJSON))
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
        quota.planType = profile?.planType
        let account = CodixxAccount(
            id: id,
            alias: alias,
            fingerprint: fingerprint,
            createdAt: timestamp,
            updatedAt: timestamp,
            lastUsedAt: timestamp,
            membershipExpiresAt: profile?.membershipExpiresAt,
            quota: quota,
            isEnabled: true,
            priority: metadata.accounts.count
        )

        try vault.save(snapshot: snapshot, fingerprint: fingerprint)
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

    public func deleteAccount(_ id: UUID) throws {
        var metadata = try metadataStore.load()
        guard let index = metadata.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountStoreError.accountNotFound(id)
        }

        let account = metadata.accounts.remove(at: index)
        try vault.delete(fingerprint: account.fingerprint)
        try metadataStore.save(metadata)
    }
}
