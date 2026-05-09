import CryptoKit
import XCTest
@testable import CodixxCore

final class AccountStoreTests: XCTestCase {
    func testAuthSnapshotCanRepresentAPIKeyLogin() throws {
        let snapshot = try AuthSnapshot.apiKey("sk-test-123")

        XCTAssertEqual(snapshot.stringValue(for: "auth_mode"), "apikey")
        XCTAssertEqual(snapshot.stringValue(for: "OPENAI_API_KEY"), "sk-test-123")
        XCTAssertEqual(try AccountFingerprint.generate(from: snapshot), "api-key:\(sha256Prefix16("sk-test-123"))")
    }

    func testAPIKeyFingerprintUsesStableHash() {
        XCTAssertEqual(APIKeyFingerprint.generate(apiKey: "sk-test-123"), "api-key:\(sha256Prefix16("sk-test-123"))")
    }

    func testSaveAPIProviderStoresMetadataAndKeySeparately() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let apiKeyVault = InMemoryAPIKeyVault()
        let store = AccountStore(
            paths: paths,
            vault: InMemoryAuthSnapshotVault(),
            apiKeyVault: apiKeyVault,
            now: { Date(timeIntervalSince1970: 10) },
            idGenerator: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }
        )

        let account = try store.saveAPIProvider(
            alias: "Relay",
            providerName: "Relay",
            baseURL: URL(string: "https://relay.example.com/v1")!,
            apiKey: "sk-test-123",
            defaultModel: "gpt-5"
        )

        XCTAssertEqual(account.credentialKind, .apiProvider)
        XCTAssertEqual(account.apiProvider?.baseURL.absoluteString, "https://relay.example.com/v1")
        XCTAssertEqual(account.apiProvider?.keyFingerprint, "api-key:\(sha256Prefix16("sk-test-123"))")
        XCTAssertEqual(apiKeyVault.keys[account.apiProvider!.keyFingerprint], "sk-test-123")
        let metadata = try AccountMetadataStore(paths: paths).load()
        XCTAssertEqual(metadata.accounts.first?.apiProvider?.keyFingerprint, account.apiProvider?.keyFingerprint)
        XCTAssertFalse(String(data: try Data(contentsOf: paths.accountsJSON), encoding: .utf8)!.contains("sk-test-123"))
    }

    func testUpdateAPIProviderCanKeepExistingKeyOrReplaceIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let apiKeyVault = InMemoryAPIKeyVault()
        let store = AccountStore(
            paths: paths,
            vault: InMemoryAuthSnapshotVault(),
            apiKeyVault: apiKeyVault,
            now: { Date(timeIntervalSince1970: 10) },
            idGenerator: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }
        )
        let account = try store.saveAPIProvider(
            alias: "Relay",
            providerName: "Relay",
            baseURL: URL(string: "https://relay.example.com/v1")!,
            apiKey: "sk-old-123",
            defaultModel: "gpt-5"
        )

        let keptKey = try store.updateAPIProvider(
            account.id,
            alias: "Relay 2",
            baseURL: URL(string: "https://relay2.example.com/v1")!,
            apiKey: nil,
            defaultModel: nil,
            balanceQuery: APIBalanceQueryConfig(
                isEnabled: true,
                urlText: "https://relay2.example.com/balance",
                jsonPath: "data.balance"
            )
        )

        XCTAssertEqual(keptKey.alias, "Relay 2")
        XCTAssertEqual(keptKey.fingerprint, account.fingerprint)
        XCTAssertEqual(keptKey.apiProvider?.baseURL.absoluteString, "https://relay2.example.com/v1")
        XCTAssertEqual(keptKey.apiProvider?.defaultModel, nil)
        XCTAssertEqual(keptKey.apiProvider?.balanceQuery?.isEnabled, true)
        XCTAssertEqual(keptKey.apiProvider?.balanceQuery?.jsonPath, "data.balance")
        XCTAssertEqual(keptKey.apiProvider?.keyFingerprint, account.apiProvider?.keyFingerprint)
        XCTAssertEqual(apiKeyVault.keys[account.apiProvider!.keyFingerprint], "sk-old-123")

        let replacedKey = try store.updateAPIProvider(
            account.id,
            alias: "Relay 3",
            baseURL: URL(string: "https://relay3.example.com/v1")!,
            apiKey: "sk-new-456",
            defaultModel: "gpt-5.1"
        )

        XCTAssertEqual(replacedKey.alias, "Relay 3")
        XCTAssertEqual(replacedKey.fingerprint, "api-provider:api-key:\(sha256Prefix16("sk-new-456"))")
        XCTAssertEqual(replacedKey.apiProvider?.keyFingerprint, "api-key:\(sha256Prefix16("sk-new-456"))")
        XCTAssertNil(apiKeyVault.keys[account.apiProvider!.keyFingerprint])
        XCTAssertEqual(apiKeyVault.keys[replacedKey.apiProvider!.keyFingerprint], "sk-new-456")
    }

    func testLegacyAPIBalanceQueryConfigDefaultsRefreshFields() throws {
        let json = #"{"isEnabled":true,"urlText":"https://relay.example.com/balance","jsonPath":"data.balance"}"#

        let config = try JSONDecoder().decode(APIBalanceQueryConfig.self, from: Data(json.utf8))

        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.refreshIntervalSeconds, 900)
        XCTAssertNil(config.lastBalanceText)
        XCTAssertNil(config.lastRefreshedAt)
    }

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

    func testSaveCurrentAuthStoresLocalJWTMembershipProfile() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let authData = Data(
            """
            {
              "tokens": {
                "account_id": "acct_main",
                "id_token": "\(Self.jwt(auth: [
                    "chatgpt_plan_type": "pro",
                    "chatgpt_subscription_active_until": "2026-06-01T00:00:00Z"
                ]))"
              }
            }
            """.utf8
        )
        try authData.write(to: paths.authJSON)
        let store = AccountStore(
            paths: paths,
            metadataStore: AccountMetadataStore(paths: paths),
            vault: InMemoryAuthSnapshotVault(),
            now: { Date(timeIntervalSince1970: 100) },
            idGenerator: { UUID(uuidString: "11111111-1111-1111-1111-111111111111")! }
        )

        let account = try store.saveCurrentAuth(alias: "Main")
        let metadata = try AccountMetadataStore(paths: paths).load()

        XCTAssertEqual(account.quota.planType, "pro")
        XCTAssertEqual(account.membershipExpiresAt, ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z"))
        XCTAssertEqual(metadata.accounts.first?.quota.planType, "pro")
        XCTAssertEqual(metadata.accounts.first?.membershipExpiresAt, ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z"))
    }

    func testSaveCurrentAuthUpdatesExistingSnapshotForDuplicateFingerprint() throws {
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
            now: { Date(timeIntervalSince1970: 100) },
            idGenerator: { UUID() }
        )

        let original = try store.saveCurrentAuth(alias: "Main")
        let refreshedData = Data(#"{"account_id":"acct_main","access_token":"fresh-secret"}"#.utf8)
        try refreshedData.write(to: paths.authJSON)

        let refreshed = try store.saveCurrentAuth(alias: "Duplicate")
        let metadata = try AccountMetadataStore(paths: paths).load()

        XCTAssertEqual(refreshed.id, original.id)
        XCTAssertEqual(refreshed.alias, "Main")
        XCTAssertEqual(refreshed.updatedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(metadata.accounts.count, 1)
        XCTAssertEqual(vault.snapshotDataByFingerprint[original.fingerprint], refreshedData)
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

    func testSaveCurrentAuthRestoresQuotaHistoryAfterDeletingAndReaddingSameFingerprint() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try Data(#"{"account_id":"acct_main","access_token":"secret"}"#.utf8).write(to: paths.authJSON)
        let vault = InMemoryAuthSnapshotVault()
        let ids = [
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        ]
        var idIndex = 0
        let store = AccountStore(
            paths: paths,
            metadataStore: AccountMetadataStore(paths: paths),
            vault: vault,
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: {
                defer { idIndex += 1 }
                return ids[idIndex]
            }
        )
        var account = try store.saveCurrentAuth(alias: "Main")
        account.quota = AccountQuotaState(
            accountId: account.id.uuidString,
            alias: account.alias,
            planType: "plus",
            primaryUsedPercent: 100,
            primaryWindowMinutes: 300,
            primaryResetsAt: Date(timeIntervalSince1970: 500),
            secondaryUsedPercent: 72,
            secondaryWindowMinutes: 10_080,
            secondaryResetsAt: Date(timeIntervalSince1970: 900),
            lastObservedAt: Date(timeIntervalSince1970: 180),
            confidence: .recent
        )
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [account]))

        try store.deleteAccount(account.id)
        let readded = try store.saveCurrentAuth(alias: "Main Again")

        XCTAssertEqual(readded.id, ids[1])
        XCTAssertEqual(readded.alias, "Main Again")
        XCTAssertEqual(readded.quota.accountId, ids[1].uuidString)
        XCTAssertEqual(readded.quota.alias, "Main Again")
        XCTAssertEqual(readded.quota.planType, "plus")
        XCTAssertEqual(readded.quota.primaryUsedPercent, 100)
        XCTAssertEqual(readded.quota.primaryResetsAt, Date(timeIntervalSince1970: 500))
        XCTAssertEqual(readded.quota.secondaryUsedPercent, 72)
        XCTAssertEqual(readded.quota.secondaryResetsAt, Date(timeIntervalSince1970: 900))
        XCTAssertEqual(readded.quota.lastObservedAt, Date(timeIntervalSince1970: 180))
        XCTAssertEqual(readded.quota.confidence, .recent)
    }

    func testDeleteAPIProviderRemovesMetadataAndAPIKey() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        let apiKeyVault = InMemoryAPIKeyVault()
        let store = AccountStore(
            paths: paths,
            vault: InMemoryAuthSnapshotVault(),
            apiKeyVault: apiKeyVault,
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: { UUID(uuidString: "11111111-1111-1111-1111-111111111111")! }
        )
        let account = try store.saveAPIProvider(
            alias: "Relay",
            providerName: "Relay",
            baseURL: URL(string: "https://relay.example.com/v1")!,
            apiKey: "sk-test-123",
            defaultModel: "gpt-5"
        )

        try store.deleteAccount(account.id)
        let metadata = try AccountMetadataStore(paths: paths).load()

        XCTAssertEqual(metadata.accounts, [])
        XCTAssertNil(apiKeyVault.keys[try XCTUnwrap(account.apiProvider?.keyFingerprint)])
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

    private static func jwt(auth: [String: Any]) -> String {
        let header = ["alg": "none"]
        let payload = ["https://api.openai.com/auth": auth]
        return [
            base64URL(header),
            base64URL(payload),
            "signature"
        ].joined(separator: ".")
    }

    private static func base64URL(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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

private final class InMemoryAPIKeyVault: APIKeyVault {
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
