import Foundation

public enum AccountSwitchResult: Equatable, Sendable {
    case success(target: CodixxAccount)
    case rolledBack
}

public struct AccountSwitcher {
    public let paths: CodixxPaths
    private let metadataStore: AccountMetadataStore
    private let vault: AuthSnapshotVault
    private let backupManager: SwitchBackupManager
    private let auditLog: SwitchAuditLog
    private let now: () -> Date
    private let fingerprintGenerator: (AuthSnapshot) throws -> String
    private let writer: AtomicFileWriter

    public init(
        paths: CodixxPaths = CodixxPaths(),
        metadataStore: AccountMetadataStore,
        vault: AuthSnapshotVault,
        backupManager: SwitchBackupManager,
        auditLog: SwitchAuditLog,
        now: @escaping () -> Date = Date.init,
        fingerprintGenerator: @escaping (AuthSnapshot) throws -> String = AccountFingerprint.generate(from:),
        writer: AtomicFileWriter = AtomicFileWriter()
    ) {
        self.paths = paths
        self.metadataStore = metadataStore
        self.vault = vault
        self.backupManager = backupManager
        self.auditLog = auditLog
        self.now = now
        self.fingerprintGenerator = fingerprintGenerator
        self.writer = writer
    }

    public func switchToAccount(_ targetId: UUID, trigger: SwitchTrigger) throws -> AccountSwitchResult {
        try FileLock(url: paths.codexHome.appendingPathComponent("auth.json.lock")).withExclusiveLock {
            try performSwitch(targetId, trigger: trigger)
        }
    }

    private func performSwitch(_ targetId: UUID, trigger: SwitchTrigger) throws -> AccountSwitchResult {
        var metadata = try metadataStore.load()
        guard let targetIndex = metadata.accounts.firstIndex(where: { $0.id == targetId }) else {
            throw AccountStoreError.snapshotNotFound(targetId.uuidString)
        }
        let target = metadata.accounts[targetIndex]
        let source = currentAccount(in: metadata)
        let backupURL = try backupManager.backupCurrentAuth(alias: source?.alias ?? "unknown")
        let targetSnapshot = try vault.load(fingerprint: target.fingerprint)

        do {
            try writer.write(targetSnapshot.jsonData, to: paths.authJSON)
        } catch {
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .failedDuringWrite,
                error: error,
                backupURL: backupURL
            ))
            throw error
        }

        let writtenSnapshot = try AuthSnapshot(jsonData: Data(contentsOf: paths.authJSON))
        let writtenFingerprint = try fingerprintGenerator(writtenSnapshot)
        guard writtenFingerprint == target.fingerprint else {
            try auditLog.append(event(
                trigger: trigger,
                source: source,
                target: target,
                result: .failedValidation,
                error: nil,
                backupURL: backupURL
            ))
            do {
                try backupManager.restoreBackup(at: backupURL)
                try auditLog.append(event(
                    trigger: .recovery,
                    source: target,
                    target: source,
                    result: .rolledBack,
                    error: nil,
                    backupURL: backupURL
                ))
                return .rolledBack
            } catch {
                try auditLog.append(event(
                    trigger: .recovery,
                    source: target,
                    target: source,
                    result: .rollbackFailed,
                    error: error,
                    backupURL: backupURL
                ))
                throw error
            }
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

    private func currentAccount(in metadata: AccountMetadataList) -> CodixxAccount? {
        guard let data = try? Data(contentsOf: paths.authJSON),
              let snapshot = try? AuthSnapshot(jsonData: data),
              let fingerprint = try? AccountFingerprint.generate(from: snapshot)
        else {
            return nil
        }
        return metadata.accounts.first { $0.fingerprint == fingerprint }
    }

    private func event(
        trigger: SwitchTrigger,
        source: CodixxAccount?,
        target: CodixxAccount?,
        result: SwitchAuditResult,
        error: Error?,
        backupURL: URL
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
            backupPath: backupURL.path
        )
    }
}
