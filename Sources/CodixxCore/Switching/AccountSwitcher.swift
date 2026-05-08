import Foundation

public enum AccountSwitchResult: Equatable, Sendable {
    case success(target: CodixxAccount)
    case rolledBack
}

public enum AccountSwitchError: Error, Equatable, LocalizedError, Sendable {
    case rollbackFailed(String)
    case insufficientDiskSpace(minimumBytes: Int64)
    case expiredAuthSnapshot(alias: String)
    case couldNotRefreshSourceSnapshot(String)
    case protectedPathChanged(String)

    public var errorDescription: String? {
        switch self {
        case .rollbackFailed(let message):
            return "Rollback failed after an account switch error. \(message)"
        case .insufficientDiskSpace(let minimumBytes):
            return "Not enough free disk space to switch accounts safely. At least \(minimumBytes) bytes are required."
        case .expiredAuthSnapshot(let alias):
            return "Saved auth for \(alias) is expired. Log out and sign in to this account in Codex, then save the account again in Codixx."
        case .couldNotRefreshSourceSnapshot(let message):
            return "Could not refresh the current account snapshot before switching. \(message)"
        case .protectedPathChanged(let message):
            return "Codex history files changed unexpectedly during account switching. \(message)"
        }
    }
}

public protocol DiskSpaceChecking: Sendable {
    func hasAvailableSpace(at url: URL, minimumBytes: Int64) -> Bool
}

public struct FileManagerDiskSpaceChecker: DiskSpaceChecking {
    public init() {}

    public func hasAvailableSpace(at url: URL, minimumBytes: Int64) -> Bool {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        guard let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage
        else {
            return true
        }
        return available >= minimumBytes
    }
}

public struct AccountSwitcher {
    public static let minimumFreeDiskSpaceBytes: Int64 = 50 * 1024 * 1024
    private static let minimumTargetAccessTokenLifetime: TimeInterval = 60

    public let paths: CodixxPaths
    private let metadataStore: AccountMetadataStore
    private let vault: AuthSnapshotVault
    private let backupManager: SwitchBackupManager
    private let auditLog: SwitchAuditLog
    private let now: () -> Date
    private let fingerprintGenerator: (AuthSnapshot) throws -> String
    private let apiKeyVault: APIKeyVault
    private let providerConfigStore: CodexProviderConfigStore
    private let writer: AtomicAuthFileWriting
    private let diskSpaceChecker: DiskSpaceChecking

    public init(
        paths: CodixxPaths = CodixxPaths(),
        metadataStore: AccountMetadataStore,
        vault: AuthSnapshotVault,
        backupManager: SwitchBackupManager,
        auditLog: SwitchAuditLog,
        now: @escaping () -> Date = Date.init,
        fingerprintGenerator: @escaping (AuthSnapshot) throws -> String = AccountFingerprint.generate(from:),
        apiKeyVault: APIKeyVault = KeychainAPIKeyVault(),
        providerConfigStore: CodexProviderConfigStore? = nil,
        writer: AtomicAuthFileWriting = AtomicFileWriter(),
        diskSpaceChecker: DiskSpaceChecking = FileManagerDiskSpaceChecker()
    ) {
        self.paths = paths
        self.metadataStore = metadataStore
        self.vault = vault
        self.backupManager = backupManager
        self.auditLog = auditLog
        self.now = now
        self.fingerprintGenerator = fingerprintGenerator
        self.apiKeyVault = apiKeyVault
        self.providerConfigStore = providerConfigStore ?? CodexProviderConfigStore(paths: paths)
        self.writer = writer
        self.diskSpaceChecker = diskSpaceChecker
    }

    public func switchToAccount(_ targetId: UUID, trigger: SwitchTrigger) throws -> AccountSwitchResult {
        try FileLock(url: paths.codexHome.appendingPathComponent("auth.json.lock")).withExclusiveLock {
            try performSwitch(targetId, trigger: trigger)
        }
    }

    private func performSwitch(_ targetId: UUID, trigger: SwitchTrigger) throws -> AccountSwitchResult {
        var metadata = try metadataStore.load()
        guard let targetIndex = metadata.accounts.firstIndex(where: { $0.id == targetId }) else {
            try auditLog.append(event(
                trigger: trigger,
                source: currentAccount(in: metadata),
                target: nil,
                result: .failedBeforeWrite,
                error: AccountStoreError.snapshotNotFound(targetId.uuidString),
                backupURL: nil
            ))
            throw AccountStoreError.snapshotNotFound(targetId.uuidString)
        }
        let target = metadata.accounts[targetIndex]
        let source = currentAccount(in: metadata)
        try refreshSourceSnapshotIfCurrentAuthMatches(source)

        guard diskSpaceChecker.hasAvailableSpace(
            at: paths.applicationSupport,
            minimumBytes: Self.minimumFreeDiskSpaceBytes
        ) else {
            let error = AccountSwitchError.insufficientDiskSpace(minimumBytes: Self.minimumFreeDiskSpaceBytes)
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .failedBeforeWrite,
                error: error,
                backupURL: nil
            ))
            throw error
        }

        if target.isAPIProvider {
            return try performAPIProviderSwitch(
                target: target,
                source: source,
                trigger: trigger,
                metadata: &metadata,
                targetIndex: targetIndex
            )
        }

        let backupURL: URL?
        do {
            backupURL = try backupCurrentAuthIfPresent(alias: source?.alias ?? "unknown")
        } catch {
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .failedBeforeWrite,
                error: error,
                backupURL: nil
            ))
            throw error
        }
        let targetSnapshot: AuthSnapshot
        do {
            targetSnapshot = try vault.load(fingerprint: target.fingerprint)
        } catch {
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .failedBeforeWrite,
                error: error,
                backupURL: backupURL
            ))
            throw error
        }
        if let accessTokenExpiresAt = targetSnapshot.accessTokenExpiresAt,
           accessTokenExpiresAt <= now().addingTimeInterval(Self.minimumTargetAccessTokenLifetime)
        {
            let error = AccountSwitchError.expiredAuthSnapshot(alias: target.alias)
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .failedBeforeWrite,
                error: error,
                backupURL: backupURL
            ))
            throw error
        }

        do {
            try writer.write(targetSnapshot.jsonData, to: paths.authJSON, fileManager: .default)
        } catch {
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .failedDuringWrite,
                error: error,
                backupURL: backupURL
            ))
            try restoreAfterFailureIfPossible(
                trigger: .recovery,
                source: target,
                target: source,
                backupURL: backupURL,
                removeAuthWhenMissingBackup: true
            )
            throw error
        }

        let writtenFingerprint: String
        do {
            let writtenSnapshot = try AuthSnapshot(jsonData: Data(contentsOf: paths.authJSON))
            writtenFingerprint = try fingerprintGenerator(writtenSnapshot)
        } catch {
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .failedValidation,
                error: error,
                backupURL: backupURL
            ))
            try restoreAfterFailureIfPossible(
                trigger: .recovery,
                source: target,
                target: source,
                backupURL: backupURL,
                removeAuthWhenMissingBackup: true
            )
            return .rolledBack
        }
        guard writtenFingerprint == target.fingerprint else {
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .failedValidation,
                error: nil,
                backupURL: backupURL
            ))
            try restoreAfterFailureIfPossible(
                trigger: .recovery,
                source: target,
                target: source,
                backupURL: backupURL,
                removeAuthWhenMissingBackup: true
            )
            return .rolledBack
        }

        metadata.accounts[targetIndex].lastUsedAt = now()
        metadata.accounts[targetIndex].updatedAt = now()
        try metadataStore.save(metadata)
        try auditLog.append(event(
            trigger: trigger,
            source: source,
            target: target,
            result: .success,
            error: nil,
            backupURL: backupURL
        ))
        return .success(target: metadata.accounts[targetIndex])
    }

    private func performAPIProviderSwitch(
        target: CodixxAccount,
        source: CodixxAccount?,
        trigger: SwitchTrigger,
        metadata: inout AccountMetadataList,
        targetIndex: Int
    ) throws -> AccountSwitchResult {
        guard let apiProvider = target.apiProvider else {
            let error = AccountStoreError.snapshotNotFound(target.fingerprint)
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .failedBeforeWrite,
                error: error,
                backupURL: nil
            ))
            throw error
        }

        let protectedBefore = try ProtectedPathSnapshot.capture(paths: paths)
        let authBackupURL: URL?
        do {
            authBackupURL = try backupCurrentAuthIfPresent(alias: source?.alias ?? "unknown")
        } catch {
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .failedBeforeWrite,
                error: error,
                backupURL: nil
            ))
            throw error
        }
        let configBackup = try providerConfigStore.backupConfig()

        do {
            let apiKey = try apiKeyVault.load(fingerprint: apiProvider.keyFingerprint)
            let apiSnapshot = try AuthSnapshot.apiKey(apiKey)
            try writer.write(apiSnapshot.jsonData, to: paths.authJSON, fileManager: .default)
            try providerConfigStore.writeAPIProvider(
                providerID: providerID(for: target),
                providerName: apiProvider.providerName,
                baseURL: apiProvider.baseURL,
                defaultModel: apiProvider.defaultModel
            )

            let protectedAfter = try ProtectedPathSnapshot.capture(paths: paths)
            let changes = protectedBefore.abnormalChanges(comparedTo: protectedAfter)
            guard changes.isEmpty else {
                throw AccountSwitchError.protectedPathChanged(changes.map { String(describing: $0) }.joined(separator: ", "))
            }

            metadata.accounts[targetIndex].lastUsedAt = now()
            metadata.accounts[targetIndex].updatedAt = now()
            try metadataStore.save(metadata)
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .success,
                error: nil,
                backupURL: authBackupURL
            ))
            return .success(target: metadata.accounts[targetIndex])
        } catch {
            try? providerConfigStore.restoreConfig(from: configBackup)
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .failedDuringWrite,
                error: error,
                backupURL: authBackupURL
            ))
            try restoreAfterFailureIfPossible(
                trigger: .recovery,
                source: target,
                target: source,
                backupURL: authBackupURL,
                removeAuthWhenMissingBackup: true
            )
            throw error
        }
    }

    private func providerID(for account: CodixxAccount) -> String {
        "codixx-\(account.id.uuidString.lowercased())"
    }

    private func backupCurrentAuthIfPresent(alias: String) throws -> URL? {
        guard FileManager.default.fileExists(atPath: paths.authJSON.path) else {
            return nil
        }
        return try backupManager.backupCurrentAuth(alias: alias)
    }

    private func refreshSourceSnapshotIfCurrentAuthMatches(_ source: CodixxAccount?) throws {
        guard let source,
              source.isChatGPT,
              let authData = try? Data(contentsOf: paths.authJSON),
              let snapshot = try? AuthSnapshot(jsonData: authData),
              (try? fingerprintGenerator(snapshot)) == source.fingerprint
        else {
            return
        }

        do {
            try vault.save(snapshot: snapshot, fingerprint: source.fingerprint)
        } catch {
            throw AccountSwitchError.couldNotRefreshSourceSnapshot(error.localizedDescription)
        }
    }

    private func restoreAfterFailure(
        trigger: SwitchTrigger,
        source: CodixxAccount?,
        target: CodixxAccount?,
        backupURL: URL
    ) throws {
        do {
            try backupManager.restoreBackup(at: backupURL)
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .rolledBack,
                error: nil,
                backupURL: backupURL
            ))
        } catch {
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .rollbackFailed,
                error: error,
                backupURL: backupURL
            ))
            throw AccountSwitchError.rollbackFailed(error.localizedDescription)
        }
    }

    private func restoreAfterFailureIfPossible(
        trigger: SwitchTrigger,
        source: CodixxAccount?,
        target: CodixxAccount?,
        backupURL: URL?,
        removeAuthWhenMissingBackup: Bool = false
    ) throws {
        guard let backupURL else {
            if removeAuthWhenMissingBackup {
                try? FileManager.default.removeItem(at: paths.authJSON)
            }
            return
        }
        try restoreAfterFailure(trigger: trigger, source: source, target: target, backupURL: backupURL)
    }

    private func currentAccount(in metadata: AccountMetadataList) -> CodixxAccount? {
        guard let data = try? Data(contentsOf: paths.authJSON),
              let snapshot = try? AuthSnapshot(jsonData: data),
              let fingerprint = try? AccountFingerprint.generate(from: snapshot)
        else {
            return nil
        }
        return metadata.accounts.first { account in
            account.fingerprint == fingerprint || account.apiProvider?.keyFingerprint == fingerprint
        }
    }

    private func event(
        trigger: SwitchTrigger,
        source: CodixxAccount?,
        target: CodixxAccount?,
        result: SwitchAuditResult,
        error: Error?,
        backupURL: URL?
    ) -> SwitchAuditEvent {
        SwitchAuditEvent(
            timestamp: now(),
            trigger: trigger,
            sourceAccountId: source?.id,
            sourceAlias: source?.alias,
            targetAccountId: target?.id,
            targetAlias: target?.alias,
            sourcePrimaryUsedPercent: source?.quota.primaryUsedPercent,
            sourceSecondaryUsedPercent: source?.quota.secondaryUsedPercent,
            threshold: nil,
            result: result,
            errorSummary: error.map { String(describing: $0) },
            backupPath: backupURL?.path
        )
    }
}
