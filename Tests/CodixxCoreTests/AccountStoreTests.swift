import CryptoKit
import XCTest
@testable import CodixxCore

final class AccountStoreTests: XCTestCase {
    func testFingerprintPrefersStableAccountIdThenEmailThenAccessTokenHash() throws {
        let accountIdAuth = try AuthSnapshot(jsonData: Data(#"{"account_id":"acct_123","email":"main@example.com","access_token":"secret"}"#.utf8))
        let emailAuth = try AuthSnapshot(jsonData: Data(#"{"email":"main@example.com","access_token":"secret"}"#.utf8))
        let tokenAuth = try AuthSnapshot(jsonData: Data(#"{"access_token":"secret-token"}"#.utf8))

        XCTAssertEqual(try AccountFingerprint.generate(from: accountIdAuth), "account:acct_123")
        XCTAssertEqual(try AccountFingerprint.generate(from: emailAuth), "email:main@example.com")
        XCTAssertEqual(try AccountFingerprint.generate(from: tokenAuth), "token:\(sha256Prefix16("secret-token"))")
    }

    func testFingerprintReadsNestedCodexTokensObject() throws {
        let accountIdAuth = try AuthSnapshot(jsonData: Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"acct_nested","access_token":"secret"}}"#.utf8))
        let tokenAuth = try AuthSnapshot(jsonData: Data(#"{"auth_mode":"chatgpt","tokens":{"access_token":"nested-token"}}"#.utf8))

        XCTAssertEqual(try AccountFingerprint.generate(from: accountIdAuth), "account:acct_nested")
        XCTAssertEqual(try AccountFingerprint.generate(from: tokenAuth), "token:\(sha256Prefix16("nested-token"))")
    }

    func testSaveCurrentAuthStoresSnapshotInVaultAndMetadataWithoutRawAuth() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let authData = Data(#"{"account_id":"acct_main","access_token":"secret"}"#.utf8)
        try authData.write(to: paths.authJSON)
        let vault = InMemoryAuthSnapshotVault()
        let accountStore = AccountStore(
            paths: paths,
            metadataStore: AccountMetadataStore(paths: paths),
            vault: vault,
            now: { Date(timeIntervalSince1970: 100) },
            idGenerator: { UUID(uuidString: "11111111-1111-1111-1111-111111111111")! }
        )

        let account = try accountStore.saveCurrentAuth(alias: "Main")
        let metadata = try AccountMetadataStore(paths: paths).load()
        let metadataData = try Data(contentsOf: paths.accountsJSON)

        XCTAssertEqual(account.alias, "Main")
        XCTAssertEqual(account.fingerprint, "account:acct_main")
        XCTAssertEqual(account.quota.accountId, account.id.uuidString)
        XCTAssertEqual(metadata.accounts, [account])
        XCTAssertEqual(vault.snapshotDataByFingerprint[account.fingerprint], authData)
        XCTAssertFalse(String(decoding: metadataData, as: UTF8.self).contains("secret"))
    }

    func testSaveCurrentAuthRejectsDuplicateFingerprint() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try Data(#"{"account_id":"acct_main","access_token":"secret"}"#.utf8).write(to: paths.authJSON)
        let store = AccountStore(
            paths: paths,
            metadataStore: AccountMetadataStore(paths: paths),
            vault: InMemoryAuthSnapshotVault(),
            now: { Date(timeIntervalSince1970: 100) },
            idGenerator: { UUID() }
        )

        _ = try store.saveCurrentAuth(alias: "Main")

        XCTAssertThrowsError(try store.saveCurrentAuth(alias: "Duplicate")) { error in
            XCTAssertEqual(error as? AccountStoreError, .duplicateFingerprint("account:acct_main"))
        }
    }

    func testRenameAccountUpdatesAliasAndQuotaAlias() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try Data(#"{"account_id":"acct_main","access_token":"secret"}"#.utf8).write(to: paths.authJSON)
        let store = AccountStore(
            paths: paths,
            metadataStore: AccountMetadataStore(paths: paths),
            vault: InMemoryAuthSnapshotVault(),
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: { UUID(uuidString: "11111111-1111-1111-1111-111111111111")! }
        )
        let account = try store.saveCurrentAuth(alias: "Main")

        let renamed = try store.renameAccount(account.id, alias: "Work")
        let metadata = try AccountMetadataStore(paths: paths).load()

        XCTAssertEqual(renamed.alias, "Work")
        XCTAssertEqual(renamed.quota.alias, "Work")
        XCTAssertEqual(renamed.updatedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(metadata.accounts.first?.alias, "Work")
        XCTAssertEqual(metadata.accounts.first?.quota.alias, "Work")
    }

    func testDeleteAccountRemovesMetadataAndSnapshot() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try Data(#"{"account_id":"acct_main","access_token":"secret"}"#.utf8).write(to: paths.authJSON)
        let vault = InMemoryAuthSnapshotVault()
        let store = AccountStore(
            paths: paths,
            metadataStore: AccountMetadataStore(paths: paths),
            vault: vault,
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: { UUID(uuidString: "11111111-1111-1111-1111-111111111111")! }
        )
        let account = try store.saveCurrentAuth(alias: "Main")

        try store.deleteAccount(account.id)
        let metadata = try AccountMetadataStore(paths: paths).load()

        XCTAssertEqual(metadata.accounts, [])
        XCTAssertNil(vault.snapshotDataByFingerprint[account.fingerprint])
    }

    private func makeTempHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func sha256Prefix16(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
            .description
    }
}

private final class InMemoryAuthSnapshotVault: AuthSnapshotVault {
    var snapshotDataByFingerprint: [String: Data] = [:]

    func save(snapshot: AuthSnapshot, fingerprint: String) throws {
        snapshotDataByFingerprint[fingerprint] = snapshot.jsonData
    }

    func load(fingerprint: String) throws -> AuthSnapshot {
        guard let data = snapshotDataByFingerprint[fingerprint] else {
            throw AccountStoreError.snapshotNotFound(fingerprint)
        }
        return try AuthSnapshot(jsonData: data)
    }

    func delete(fingerprint: String) throws {
        snapshotDataByFingerprint.removeValue(forKey: fingerprint)
    }
}
