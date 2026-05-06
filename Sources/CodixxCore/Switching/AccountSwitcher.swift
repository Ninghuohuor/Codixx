import Foundation

public enum AccountSwitchResult: Equatable, Sendable {
    case success(target: CodixxAccount)
    case rolledBack
}

public enum AccountSwitchError: Error, Equatable, LocalizedError, Sendable {
    case rollbackFailed(String)
    case insufficientDiskSpace(minimumBytes: Int64)

    public var errorDescription: String? {
        switch self {
        case .rollbackFailed(let message):
            return "Rollback failed after an account switch error. \(message)"
        case .insufficientDiskSpace(let minimumBytes):
            return "Not enough free disk space to switch accounts safely. At least \(minimumBytes) bytes are required."
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

    public let paths: CodixxPaths
    private let metadataStore: AccountMetadataStore
    private let vault: AuthSnapshotVault
    private let backupManager: SwitchBackupManager
    private let auditLog: SwitchAuditLog
    private let now: () -> Date
    private let fingerprintGenerator: (AuthSnapshot) throws -> String
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

        let backupURL: URL
        do {
            backupURL = try backupManager.backupCurrentAuth(alias: source?.alias ?? "unknown")
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
            try restoreAfterFailure(trigger: .recovery, source: target, target: source, backupURL: backupURL)
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
            try restoreAfterFailure(trigger: .recovery, source: target, target: source, backupURL: backupURL)
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
            try restoreAfterFailure(trigger: .recovery, source: target, target: source, backupURL: backupURL)
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
