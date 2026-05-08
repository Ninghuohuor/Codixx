import XCTest
@testable import CodixxCore

final class AccountSwitcherTests: XCTestCase {
    func testFileLockBlocksNestedExclusiveLock() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        let lock = FileLock(url: fixture.paths.codexHome.appendingPathComponent("auth.json.lock"), timeoutSeconds: 0)

        try lock.withExclusiveLock {
            XCTAssertThrowsError(try lock.withExclusiveLock {})
        }
    }

    func testManualSwitchBacksUpWritesValidatesAuditsAndUpdatesMetadata() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        let switcher = fixture.switcher()

        let result = try switcher.switchToAccount(fixture.target.id, trigger: .manual)

        let writtenAuth = try Data(contentsOf: fixture.paths.authJSON)
        let backupFiles = try FileManager.default.contentsOfDirectory(atPath: fixture.paths.backups.path)
        let metadata = try fixture.metadataStore.load()
        let auditEvents = try fixture.auditLog.loadEvents()

        guard case .success(let switchedAccount) = result else {
            XCTFail("Expected successful switch")
            return
        }
        XCTAssertEqual(switchedAccount.id, fixture.target.id)
        XCTAssertEqual(switchedAccount.alias, fixture.target.alias)
        XCTAssertEqual(switchedAccount.lastUsedAt, fixture.now)
        XCTAssertEqual(writtenAuth, fixture.targetAuth.jsonData)
        XCTAssertEqual(backupFiles.count, 1)
        XCTAssertEqual(metadata.accounts.first(where: { $0.id == fixture.target.id })?.lastUsedAt, fixture.now)
        XCTAssertEqual(auditEvents.map(\.result), [.success])
        XCTAssertEqual(auditEvents.first?.sourceAlias, "Main")
        XCTAssertEqual(auditEvents.first?.targetAlias, "Backup")
    }

    func testSwitchToAPIProviderWritesAPIAuthAndProviderConfigWithoutTouchingHistory() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        let apiKeyVault = InMemorySwitchAPIKeyVault()
        let apiAccountId = UUID()
        let apiKeyFingerprint = APIKeyFingerprint.generate(apiKey: "sk-test-123")
        try apiKeyVault.save(apiKey: "sk-test-123", fingerprint: apiKeyFingerprint)
        let apiAccount = CodixxAccount(
            id: apiAccountId,
            alias: "Relay",
            fingerprint: "api-provider:\(apiKeyFingerprint)",
            credentialKind: .apiProvider,
            apiProvider: APIProviderAccount(
                providerName: "Relay",
                baseURL: URL(string: "https://relay.example.com/v1")!,
                defaultModel: "gpt-5",
                keyFingerprint: apiKeyFingerprint
            ),
            createdAt: fixture.now,
            updatedAt: fixture.now,
            lastUsedAt: nil,
            quota: .unknown(accountId: apiAccountId.uuidString, alias: "Relay"),
            isEnabled: true,
            priority: 2
        )
        var metadata = try fixture.metadataStore.load()
        metadata.accounts.append(apiAccount)
        try fixture.metadataStore.save(metadata)
        try FileManager.default.createDirectory(
            at: fixture.paths.codexHome.appendingPathComponent("sessions", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data(repeating: 1, count: 100).write(to: fixture.paths.codexHome.appendingPathComponent("state_5.sqlite"))

        let switcher = fixture.switcher(apiKeyVault: apiKeyVault)

        _ = try switcher.switchToAccount(apiAccountId, trigger: .manual)

        let written = try AuthSnapshot(jsonData: Data(contentsOf: fixture.paths.authJSON))
        XCTAssertEqual(written.stringValue(for: "auth_mode"), "apikey")
        XCTAssertEqual(written.stringValue(for: "OPENAI_API_KEY"), "sk-test-123")
        let config = try String(contentsOf: fixture.paths.configTOML)
        XCTAssertTrue(config.contains("base_url = \"https://relay.example.com/v1\""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.paths.codexHome.appendingPathComponent("sessions", isDirectory: true).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.paths.codexHome.appendingPathComponent("state_5.sqlite").path))
    }

    func testSwitchRefreshesSourceSnapshotBeforeWritingTarget() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        let updatedSourceAuth = try AuthSnapshot(jsonData: Data(#"{"account_id":"source","access_token":"fresh-source-secret"}"#.utf8))
        try updatedSourceAuth.jsonData.write(to: fixture.paths.authJSON)
        let switcher = fixture.switcher()

        _ = try switcher.switchToAccount(fixture.target.id, trigger: .manual)

        XCTAssertEqual(fixture.vault.snapshots[fixture.source.fingerprint]?.jsonData, updatedSourceAuth.jsonData)
    }

    func testSwitchSucceedsWhenCodexIsLoggedOutAndAuthFileIsMissing() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.paths.authJSON)
        let switcher = fixture.switcher()

        let result = try switcher.switchToAccount(fixture.target.id, trigger: .manual)

        let writtenAuth = try Data(contentsOf: fixture.paths.authJSON)
        let backupFiles = try FileManager.default.contentsOfDirectory(atPath: fixture.paths.backups.path)
        let auditEvents = try fixture.auditLog.loadEvents()

        guard case .success(let switchedAccount) = result else {
            XCTFail("Expected switch to succeed from logged-out Codex state")
            return
        }
        XCTAssertEqual(switchedAccount.id, fixture.target.id)
        XCTAssertEqual(writtenAuth, fixture.targetAuth.jsonData)
        XCTAssertEqual(backupFiles, [])
        XCTAssertEqual(auditEvents.map(\.result), [.success])
        XCTAssertNil(auditEvents.first?.sourceAccountId)
        XCTAssertNil(auditEvents.first?.backupPath)
    }

    func testSwitchRejectsExpiredTargetAccessTokenBeforeWritingAuth() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        let expiredTargetAuth = try AuthSnapshot(jsonData: Data(
            """
            {"account_id":"target","access_token":"\(Self.jwt(expiration: 900))"}
            """.utf8
        ))
        try fixture.vault.save(snapshot: expiredTargetAuth, fingerprint: fixture.target.fingerprint)
        let switcher = fixture.switcher()

        XCTAssertThrowsError(try switcher.switchToAccount(fixture.target.id, trigger: .manual)) { error in
            XCTAssertEqual(error as? AccountSwitchError, .expiredAuthSnapshot(alias: "Backup"))
        }
        let writtenAuth = try Data(contentsOf: fixture.paths.authJSON)
        let auditEvents = try fixture.auditLog.loadEvents()

        XCTAssertEqual(writtenAuth, fixture.sourceAuth.jsonData)
        XCTAssertEqual(auditEvents.map(\.result), [.failedBeforeWrite])
    }

    func testSwitchWritesAuthAndBackupWithOwnerOnlyPermissions() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        let switcher = fixture.switcher()

        _ = try switcher.switchToAccount(fixture.target.id, trigger: .manual)

        let backupFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.paths.backups,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(try posixPermissions(at: fixture.paths.applicationSupport), 0o700)
        XCTAssertEqual(try posixPermissions(at: fixture.paths.backups), 0o700)
        XCTAssertEqual(try posixPermissions(at: fixture.paths.authJSON), 0o600)
        XCTAssertEqual(try posixPermissions(at: try XCTUnwrap(backupFiles.first)), 0o600)
    }

    func testValidationFailureRollsBackAndWritesAuditEvents() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        let switcher = fixture.switcher(fingerprintGenerator: { _ in "wrong-fingerprint" })

        let result = try switcher.switchToAccount(fixture.target.id, trigger: .manual)
        let writtenAuth = try Data(contentsOf: fixture.paths.authJSON)
        let auditEvents = try fixture.auditLog.loadEvents()

        XCTAssertEqual(result, .rolledBack)
        XCTAssertEqual(writtenAuth, fixture.sourceAuth.jsonData)
        XCTAssertEqual(auditEvents.map(\.result), [.failedValidation, .rolledBack])
    }

    func testValidationFailureWithoutExistingAuthReturnsToLoggedOutState() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.paths.authJSON)
        let switcher = fixture.switcher(fingerprintGenerator: { _ in "wrong-fingerprint" })

        let result = try switcher.switchToAccount(fixture.target.id, trigger: .manual)

        let auditEvents = try fixture.auditLog.loadEvents()
        XCTAssertEqual(result, .rolledBack)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.authJSON.path))
        XCTAssertEqual(auditEvents.map(\.result), [.failedValidation])
    }

    func testValidationThrowRollsBackAndWritesAuditEvents() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        let switcher = fixture.switcher(fingerprintGenerator: { _ in throw AccountStoreError.invalidAuthSnapshot })

        let result = try switcher.switchToAccount(fixture.target.id, trigger: .manual)
        let writtenAuth = try Data(contentsOf: fixture.paths.authJSON)
        let auditEvents = try fixture.auditLog.loadEvents()

        XCTAssertEqual(result, .rolledBack)
        XCTAssertEqual(writtenAuth, fixture.sourceAuth.jsonData)
        XCTAssertEqual(auditEvents.map(\.result), [.failedValidation, .rolledBack])
    }

    func testWriteFailureAttemptsRestoreAndAuditsRollback() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        let switcher = fixture.switcher(writer: FailingAtomicWriter())

        XCTAssertThrowsError(try switcher.switchToAccount(fixture.target.id, trigger: .manual))

        let writtenAuth = try Data(contentsOf: fixture.paths.authJSON)
        let auditEvents = try fixture.auditLog.loadEvents()

        XCTAssertEqual(writtenAuth, fixture.sourceAuth.jsonData)
        XCTAssertEqual(auditEvents.map(\.result), [.failedDuringWrite, .rolledBack])
    }

    func testRollbackFailureThrowsTypedErrorForProtectionMode() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        let switcher = fixture.switcher(writer: CorruptingAtomicWriter(paths: fixture.paths))

        XCTAssertThrowsError(try switcher.switchToAccount(fixture.target.id, trigger: .manual)) { error in
            guard case AccountSwitchError.rollbackFailed = error else {
                XCTFail("Expected rollbackFailed error, got \(error)")
                return
            }
        }

        let auditEvents = try fixture.auditLog.loadEvents()

        XCTAssertEqual(auditEvents.map(\.result), [.failedDuringWrite, .rollbackFailed])
    }

    func testMissingSnapshotWritesFailedBeforeWriteAudit() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        try fixture.vault.delete(fingerprint: fixture.target.fingerprint)
        let switcher = fixture.switcher()

        XCTAssertThrowsError(try switcher.switchToAccount(fixture.target.id, trigger: .manual))

        let auditEvents = try fixture.auditLog.loadEvents()

        XCTAssertEqual(auditEvents.map(\.result), [.failedBeforeWrite])
    }

    func testInsufficientDiskSpaceStopsBeforeBackupOrWrite() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        let switcher = fixture.switcher(diskSpaceChecker: FixedDiskSpaceChecker(hasEnoughSpace: false))

        XCTAssertThrowsError(try switcher.switchToAccount(fixture.target.id, trigger: .manual)) { error in
            guard case AccountSwitchError.insufficientDiskSpace = error else {
                XCTFail("Expected insufficientDiskSpace error, got \(error)")
                return
            }
        }

        let writtenAuth = try Data(contentsOf: fixture.paths.authJSON)
        let auditEvents = try fixture.auditLog.loadEvents()
        let backupFiles = try FileManager.default.contentsOfDirectory(atPath: fixture.paths.backups.path)

        XCTAssertEqual(writtenAuth, fixture.sourceAuth.jsonData)
        XCTAssertEqual(auditEvents.map(\.result), [.failedBeforeWrite])
        XCTAssertEqual(backupFiles, [])
    }

    func testBackupNamesAreUniqueWithinSameSecond() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }

        let first = try fixture.backupManager.backupCurrentAuth(alias: "Main")
        let second = try fixture.backupManager.backupCurrentAuth(alias: "Main")

        XCTAssertNotEqual(first.lastPathComponent, second.lastPathComponent)
    }

    func testBackupManagerKeepsMostRecentTwentyBackups() throws {
        let fixture = try SwitchFixture()
        defer { fixture.cleanup() }
        let base = Date(timeIntervalSince1970: 10_000)
        var currentDate = base
        let backupManager = SwitchBackupManager(paths: fixture.paths, now: { currentDate })

        for offset in 0..<25 {
            currentDate = base.addingTimeInterval(Double(offset))
            _ = try backupManager.backupCurrentAuth(alias: "Main")
        }

        let backupFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.paths.backups,
            includingPropertiesForKeys: [.creationDateKey]
        )

        XCTAssertEqual(backupFiles.count, 20)
        XCTAssertFalse(backupFiles.contains { $0.lastPathComponent.contains("1970-01-01T02-46-40Z") })
    }

    func testProtectedPathSnapshotIgnoresGrowthButRejectsRemovalAndShrink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(
            at: paths.codexHome.appendingPathComponent("sessions", isDirectory: true),
            withIntermediateDirectories: true
        )
        let stateDB = paths.codexHome.appendingPathComponent("state_5.sqlite")
        try Data(repeating: 1, count: 100).write(to: stateDB)
        let before = try ProtectedPathSnapshot.capture(paths: paths)

        try Data(repeating: 1, count: 120).write(to: stateDB)
        XCTAssertEqual(try before.abnormalChanges(comparedTo: .capture(paths: paths)), [])

        try Data(repeating: 1, count: 10).write(to: stateDB)
        XCTAssertTrue(try before.abnormalChanges(comparedTo: .capture(paths: paths)).contains(.sharpFileShrink(stateDB.path)))

        try FileManager.default.removeItem(at: stateDB)
        XCTAssertTrue(try before.abnormalChanges(comparedTo: .capture(paths: paths)).contains(.removed(stateDB.path)))
    }

    private static func jwt(expiration: Int) -> String {
        [
            base64URL(["alg": "none"]),
            base64URL(["exp": expiration]),
            "signature"
        ].joined(separator: ".")
    }

    private static func base64URL(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class SwitchFixture {
    let home: URL
    let paths: CodixxPaths
    let metadataStore: AccountMetadataStore
    let vault: InMemorySwitchVault
    let auditLog: SwitchAuditLog
    let backupManager: SwitchBackupManager
    let source: CodixxAccount
    let target: CodixxAccount
    let sourceAuth: AuthSnapshot
    let targetAuth: AuthSnapshot
    let now = Date(timeIntervalSince1970: 1_000)

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = CodixxPaths(home: home)
        metadataStore = AccountMetadataStore(paths: paths)
        vault = InMemorySwitchVault()
        let fixtureNow = now
        auditLog = SwitchAuditLog(paths: paths, retention: .init(now: { fixtureNow }))
        backupManager = SwitchBackupManager(paths: paths, now: { Date(timeIntervalSince1970: 1_000) })

        sourceAuth = try AuthSnapshot(jsonData: Data(#"{"account_id":"source","access_token":"source-secret"}"#.utf8))
        targetAuth = try AuthSnapshot(jsonData: Data(#"{"account_id":"target","access_token":"target-secret"}"#.utf8))
        source = Self.account(alias: "Main", fingerprint: "account:source", now: now)
        target = Self.account(alias: "Backup", fingerprint: "account:target", now: now)

        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try sourceAuth.jsonData.write(to: paths.authJSON)
        try metadataStore.save(AccountMetadataList(accounts: [source, target]))
        try vault.save(snapshot: sourceAuth, fingerprint: source.fingerprint)
        try vault.save(snapshot: targetAuth, fingerprint: target.fingerprint)
    }

    func switcher(
        fingerprintGenerator: @escaping (AuthSnapshot) throws -> String = AccountFingerprint.generate(from:),
        apiKeyVault: APIKeyVault = InMemorySwitchAPIKeyVault(),
        writer: AtomicAuthFileWriting = AtomicFileWriter(),
        diskSpaceChecker: DiskSpaceChecking = FileManagerDiskSpaceChecker()
    ) -> AccountSwitcher {
        AccountSwitcher(
            paths: paths,
            metadataStore: metadataStore,
            vault: vault,
            backupManager: backupManager,
            auditLog: auditLog,
            now: { self.now },
            fingerprintGenerator: fingerprintGenerator,
            apiKeyVault: apiKeyVault,
            writer: writer,
            diskSpaceChecker: diskSpaceChecker
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: home)
    }

    private static func account(alias: String, fingerprint: String, now: Date) -> CodixxAccount {
        let id = UUID()
        return CodixxAccount(
            id: id,
            alias: alias,
            fingerprint: fingerprint,
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil,
            quota: .unknown(accountId: id.uuidString, alias: alias),
            isEnabled: true,
            priority: 0
        )
    }
}

private struct FailingAtomicWriter: AtomicAuthFileWriting {
    func write(_ data: Data, to url: URL, fileManager: FileManager) throws {
        throw AccountStoreError.keychainError("forced write failure")
    }
}

private struct CorruptingAtomicWriter: AtomicAuthFileWriting {
    var paths: CodixxPaths

    func write(_ data: Data, to url: URL, fileManager: FileManager) throws {
        try Data(#"{"account_id":"corrupt","access_token":"corrupt"}"#.utf8).write(to: url)
        try fileManager.removeItem(at: paths.backups)
        throw AccountStoreError.keychainError("forced write failure")
    }
}

private struct FixedDiskSpaceChecker: DiskSpaceChecking {
    var hasEnoughSpace: Bool

    func hasAvailableSpace(at url: URL, minimumBytes: Int64) -> Bool {
        hasEnoughSpace
    }
}

private func posixPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try XCTUnwrap(attributes[.posixPermissions] as? Int) & 0o777
}

private final class InMemorySwitchVault: AuthSnapshotVault {
    var snapshots: [String: AuthSnapshot] = [:]

    func save(snapshot: AuthSnapshot, fingerprint: String) throws {
        snapshots[fingerprint] = snapshot
    }

    func load(fingerprint: String) throws -> AuthSnapshot {
        guard let snapshot = snapshots[fingerprint] else {
            throw AccountStoreError.snapshotNotFound(fingerprint)
        }
        return snapshot
    }

    func delete(fingerprint: String) throws {
        snapshots.removeValue(forKey: fingerprint)
    }
}

private final class InMemorySwitchAPIKeyVault: APIKeyVault {
    var keys: [String: String] = [:]

    func save(apiKey: String, fingerprint: String) throws {
        keys[fingerprint] = apiKey
    }

    func load(fingerprint: String) throws -> String {
        guard let key = keys[fingerprint] else {
            throw AccountStoreError.snapshotNotFound(fingerprint)
        }
        return key
    }

    func delete(fingerprint: String) throws {
        keys.removeValue(forKey: fingerprint)
    }
}
