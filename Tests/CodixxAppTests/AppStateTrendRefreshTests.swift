import XCTest
@testable import CodixxApp
import CodixxCore

@MainActor
final class AppStateTrendRefreshTests: XCTestCase {
    func testManualSwitchSuppressesImmediateAutoSwitchBounceFromDepletedTarget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        var now = Date(timeIntervalSince1970: 1_778_000_000)
        let currentAuth = try AuthSnapshot(jsonData: Data(#"{"account_id":"current","access_token":"current-secret"}"#.utf8))
        let depletedAuth = try AuthSnapshot(jsonData: Data(#"{"account_id":"depleted","access_token":"depleted-secret"}"#.utf8))
        let currentFingerprint = try AccountFingerprint.generate(from: currentAuth)
        let depletedFingerprint = try AccountFingerprint.generate(from: depletedAuth)
        let vault = InMemoryVault()
        try vault.save(snapshot: currentAuth, fingerprint: currentFingerprint)
        try vault.save(snapshot: depletedAuth, fingerprint: depletedFingerprint)
        try currentAuth.jsonData.write(to: paths.authJSON)

        let current = CodixxAccount(
            id: UUID(),
            alias: "Current",
            fingerprint: currentFingerprint,
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil,
            quota: AccountQuotaState(
                accountId: "current",
                alias: "Current",
                primaryUsedPercent: 10,
                primaryWindowMinutes: 300,
                primaryResetsAt: nil,
                secondaryUsedPercent: 10,
                secondaryWindowMinutes: 10_080,
                secondaryResetsAt: nil,
                lastObservedAt: now,
                confidence: .fresh
            ),
            isEnabled: true,
            priority: 0
        )
        let depleted = CodixxAccount(
            id: UUID(),
            alias: "Depleted",
            fingerprint: depletedFingerprint,
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil,
            quota: AccountQuotaState(
                accountId: "depleted",
                alias: "Depleted",
                primaryUsedPercent: 0,
                primaryWindowMinutes: 300,
                primaryResetsAt: nil,
                secondaryUsedPercent: 100,
                secondaryWindowMinutes: 10_080,
                secondaryResetsAt: nil,
                lastObservedAt: now,
                confidence: .fresh
            ),
            isEnabled: true,
            priority: 0
        )
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [current, depleted]))
        let codexDesktopManager = CodexDesktopManagerSpy()
        let state = AppState(
            paths: paths,
            vault: vault,
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: codexDesktopManager,
            now: { now }
        )

        state.switchToAccount(depleted)
        XCTAssertEqual(state.currentAccount?.id, depleted.id)
        XCTAssertEqual(codexDesktopManager.quitForCleanSwitchCallCount, 1)
        XCTAssertEqual(codexDesktopManager.restartCallCount, 1)
        now = now.addingTimeInterval(1)
        state.refreshQuotaNow()

        XCTAssertEqual(state.currentAccount?.id, depleted.id)
        let events = try SwitchAuditLog(paths: paths).loadEvents()
        XCTAssertEqual(events.filter { $0.result == .success }.map(\.targetAlias), ["Depleted"])
    }

    func testAppStateCanSaveAPIProviderAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let apiKeyVault = InMemoryAPIKeyVault()
        let state = AppState(
            paths: CodixxPaths(home: directory),
            vault: InMemoryVault(),
            apiKeyVault: apiKeyVault,
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy()
        )

        state.saveAPIProviderAccount(
            alias: "Relay",
            baseURLText: "https://relay.example.com/v1",
            apiKey: "sk-test-123",
            defaultModel: "gpt-5"
        )

        XCTAssertEqual(state.accounts.first?.credentialKind, .apiProvider)
        XCTAssertEqual(state.accounts.first?.alias, "Relay")
        XCTAssertEqual(state.accounts.first?.apiProvider?.providerName, "Relay")
        XCTAssertEqual(state.accounts.first?.apiProvider?.baseURL.absoluteString, "https://relay.example.com/v1")
    }

    func testAppStateRequiresAliasForAPIProviderAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(
            paths: CodixxPaths(home: directory),
            vault: InMemoryVault(),
            apiKeyVault: InMemoryAPIKeyVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy()
        )

        state.saveAPIProviderAccount(
            alias: " ",
            baseURLText: "https://relay.example.com/v1",
            apiKey: "sk-test-123",
            defaultModel: ""
        )

        XCTAssertTrue(state.accounts.isEmpty)
        XCTAssertEqual(state.errorMessage, state.strings.aliasRequired)
        XCTAssertEqual(state.accountSaveStatus, .failure(message: state.strings.aliasRequired))
    }

    func testAppStateCanUpdateAPIProviderAccountAndKeepExistingKeyWhenBlank() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let apiKeyVault = InMemoryAPIKeyVault()
        let state = AppState(
            paths: CodixxPaths(home: directory),
            vault: InMemoryVault(),
            apiKeyVault: apiKeyVault,
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy()
        )

        state.saveAPIProviderAccount(
            alias: "Relay",
            baseURLText: "https://relay.example.com/v1",
            apiKey: "sk-old-123456",
            defaultModel: "gpt-4.1"
        )
        let account = try XCTUnwrap(state.accounts.first)

        state.updateAPIProviderAccount(
            account,
            alias: "Relay 2",
            baseURLText: "https://relay2.example.com/v1",
            apiKey: "",
            defaultModel: ""
        )

        let updated = try XCTUnwrap(state.accounts.first)
        XCTAssertEqual(updated.alias, "Relay 2")
        XCTAssertEqual(updated.apiProvider?.baseURL.absoluteString, "https://relay2.example.com/v1")
        XCTAssertNil(updated.apiProvider?.defaultModel)
        XCTAssertEqual(updated.apiProvider?.keyFingerprint, account.apiProvider?.keyFingerprint)
        XCTAssertEqual(apiKeyVault.keys[account.apiProvider!.keyFingerprint], "sk-old-123456")
    }

    func testAppStateMasksAPIKeyFromVault() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let apiKeyVault = InMemoryAPIKeyVault()
        let state = AppState(
            paths: CodixxPaths(home: directory),
            vault: InMemoryVault(),
            apiKeyVault: apiKeyVault,
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy()
        )

        state.saveAPIProviderAccount(
            alias: "Relay",
            baseURLText: "https://relay.example.com/v1",
            apiKey: "sk-e1c12345678992df",
            defaultModel: ""
        )

        let account = try XCTUnwrap(state.accounts.first)
        XCTAssertEqual(state.maskedAPIKey(for: account), "sk-e1c...92df")
    }

    func testAppStateKeepsExistingAPIKeyWhenUpdateReceivesMaskedKey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let apiKeyVault = InMemoryAPIKeyVault()
        let state = AppState(
            paths: CodixxPaths(home: directory),
            vault: InMemoryVault(),
            apiKeyVault: apiKeyVault,
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy()
        )

        state.saveAPIProviderAccount(
            alias: "Relay",
            baseURLText: "https://relay.example.com/v1",
            apiKey: "sk-e1c12345678992df",
            defaultModel: ""
        )
        let account = try XCTUnwrap(state.accounts.first)

        state.updateAPIProviderAccount(
            account,
            alias: "Relay 2",
            baseURLText: "https://relay2.example.com/v1",
            apiKey: "sk-e1c...92df",
            defaultModel: "gpt-4.1"
        )

        let updated = try XCTUnwrap(state.accounts.first)
        XCTAssertEqual(updated.alias, "Relay 2")
        XCTAssertEqual(updated.apiProvider?.keyFingerprint, account.apiProvider?.keyFingerprint)
        XCTAssertEqual(apiKeyVault.keys[account.apiProvider!.keyFingerprint], "sk-e1c12345678992df")
    }

    func testRefreshingAPIBalanceStoresBalanceOnAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let apiKeyVault = InMemoryAPIKeyVault()
        let balanceTester = APIBalanceQueryTesterSpy(result: APIBalanceQueryResult(isSuccess: true, message: "Balance: 12.34", balanceText: "12.34"))
        let observedAt = Date(timeIntervalSince1970: 1_778_300_000)
        let state = AppState(
            paths: CodixxPaths(home: directory),
            vault: InMemoryVault(),
            apiKeyVault: apiKeyVault,
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            balanceQueryTester: balanceTester,
            now: { observedAt }
        )
        state.saveAPIProviderAccount(
            alias: "Relay",
            baseURLText: "https://relay.example.com/v1",
            apiKey: "sk-test-123",
            defaultModel: ""
        )
        let account = try XCTUnwrap(state.accounts.first)
        let config = APIBalanceQueryConfig(
            isEnabled: true,
            urlText: "https://relay.example.com/balance",
            jsonPath: "data.balance",
            refreshIntervalSeconds: 600
        )
        state.updateAPIProviderAccount(
            account,
            alias: account.alias,
            baseURLText: account.apiProvider!.baseURL.absoluteString,
            apiKey: "",
            defaultModel: "",
            balanceQuery: config
        )

        let result = await state.refreshAPIBalance(for: try XCTUnwrap(state.accounts.first))

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(state.accounts.first?.apiProvider?.balanceQuery?.lastBalanceText, "12.34")
        XCTAssertEqual(state.accounts.first?.apiProvider?.balanceQuery?.lastRefreshedAt, observedAt)
        XCTAssertEqual(balanceTester.callCount, 1)
    }

    func testAutomaticAPIBalanceRefreshSkipsAccountsBeforeInterval() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let apiKeyVault = InMemoryAPIKeyVault()
        let balanceTester = APIBalanceQueryTesterSpy(result: APIBalanceQueryResult(isSuccess: true, message: "Balance: 99", balanceText: "99"))
        var now = Date(timeIntervalSince1970: 1_778_300_000)
        let state = AppState(
            paths: CodixxPaths(home: directory),
            vault: InMemoryVault(),
            apiKeyVault: apiKeyVault,
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            balanceQueryTester: balanceTester,
            now: { now }
        )
        state.saveAPIProviderAccount(
            alias: "Relay",
            baseURLText: "https://relay.example.com/v1",
            apiKey: "sk-test-123",
            defaultModel: ""
        )
        let account = try XCTUnwrap(state.accounts.first)
        state.updateAPIProviderAccount(
            account,
            alias: account.alias,
            baseURLText: account.apiProvider!.baseURL.absoluteString,
            apiKey: "",
            defaultModel: "",
            balanceQuery: APIBalanceQueryConfig(
                isEnabled: true,
                urlText: "https://relay.example.com/balance",
                jsonPath: "data.balance",
                refreshIntervalSeconds: 600,
                lastBalanceText: "88",
                lastRefreshedAt: now
            )
        )

        await state.refreshDueAPIBalances()
        XCTAssertEqual(balanceTester.callCount, 0)

        now = now.addingTimeInterval(601)
        await state.refreshDueAPIBalances()

        XCTAssertEqual(balanceTester.callCount, 1)
        XCTAssertEqual(state.accounts.first?.apiProvider?.balanceQuery?.lastBalanceText, "99")
    }

    func testSwitchClearsStaleSaveStatus() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        let firstAuth = try AuthSnapshot(jsonData: Data(#"{"account_id":"first","access_token":"first-secret"}"#.utf8))
        let secondAuth = try AuthSnapshot(jsonData: Data(#"{"account_id":"second","access_token":"second-secret"}"#.utf8))
        let firstFingerprint = try AccountFingerprint.generate(from: firstAuth)
        let secondFingerprint = try AccountFingerprint.generate(from: secondAuth)
        let vault = InMemoryVault()
        try firstAuth.jsonData.write(to: paths.authJSON)
        try vault.save(snapshot: firstAuth, fingerprint: firstFingerprint)
        try vault.save(snapshot: secondAuth, fingerprint: secondFingerprint)
        let state = AppState(
            paths: paths,
            vault: vault,
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy()
        )

        state.saveCurrentAccount(alias: "First")
        XCTAssertEqual(state.accountSaveStatus, .success(alias: "First"))
        var metadata = try AccountMetadataStore(paths: paths).load()
        let second = CodixxAccount(
            id: UUID(),
            alias: "Second",
            fingerprint: secondFingerprint,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: nil,
            quota: .unknown(accountId: "second", alias: "Second"),
            isEnabled: true,
            priority: 1
        )
        metadata.accounts.append(second)
        try AccountMetadataStore(paths: paths).save(metadata)

        state.switchToAccount(second)

        XCTAssertNil(state.accountSaveStatus)
    }

    func testMenuOpenRefreshAppliesLatestQuotaObservationWithoutFullUsageRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        let authData = Data(#"{"account_id":"acct_main","access_token":"secret"}"#.utf8)
        try authData.write(to: paths.authJSON)
        let fingerprint = try AccountFingerprint.generate(from: AuthSnapshot(jsonData: authData))
        let accountId = UUID()
        let oldReset = Date(timeIntervalSince1970: 1_778_200_000)
        let observedReset = Date(timeIntervalSince1970: 1_778_206_586)
        let account = CodixxAccount(
            id: accountId,
            alias: "main",
            fingerprint: fingerprint,
            createdAt: oldReset,
            updatedAt: oldReset,
            lastUsedAt: nil,
            quota: AccountQuotaState(
                accountId: accountId.uuidString,
                alias: "main",
                primaryUsedPercent: 80,
                primaryWindowMinutes: 300,
                primaryResetsAt: oldReset,
                secondaryUsedPercent: 20,
                secondaryWindowMinutes: 10_080,
                secondaryResetsAt: Date(timeIntervalSince1970: 1_778_700_000),
                lastObservedAt: oldReset,
                confidence: .recent
            ),
            isEnabled: true,
            priority: 0
        )
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [account]))

        let sessionDirectory = paths.codexHome.appendingPathComponent("sessions/2026/05/08", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let sessionFile = sessionDirectory.appendingPathComponent("rollout.jsonl")
        let observationLine = """
        {"timestamp":"2026-05-08T01:00:00Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"primary":{"used_percent":62.0,"window_minutes":300,"resets_at":\(Int(observedReset.timeIntervalSince1970))},"secondary":{"used_percent":72.0,"window_minutes":10080,"resets_at":1778700000},"plan_type":"plus"}}
        """
        try (observationLine + "\n").write(to: sessionFile, atomically: true, encoding: .utf8)

        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy()
        )

        state.refreshFromMenuOpen()

        XCTAssertEqual(state.currentAccount?.quota.primaryUsedPercent, 62)
        XCTAssertEqual(state.currentAccount?.quota.primaryResetsAt, observedReset)
        XCTAssertFalse(state.isLoadingFullUsageSnapshot)
        XCTAssertFalse(state.hasLoadedFullUsageSnapshot)
    }

    func testTrendRefreshMarksFullUsageSnapshotLoaded() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = AppState(
            paths: CodixxPaths(home: directory),
            vault: InMemoryVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy()
        )

        XCTAssertFalse(state.hasLoadedFullUsageSnapshot)
        XCTAssertFalse(state.isLoadingFullUsageSnapshot)

        state.refreshTrendsIfNeeded()

        XCTAssertTrue(state.isLoadingFullUsageSnapshot)
        try await waitUntil { state.hasLoadedFullUsageSnapshot }
        XCTAssertFalse(state.isLoadingFullUsageSnapshot)
    }

    func testAccountUsageWindowsAttributeHistoryBeforeFirstSwitchToSourceAccount() throws {
        let accountA = UUID()
        let accountB = UUID()
        let accountCreatedAt = Date(timeIntervalSince1970: 1_777_000_000)
        let firstSwitchAt = Date(timeIntervalSince1970: 1_778_000_000)
        let account = CodixxAccount(
            id: accountA,
            alias: "A",
            fingerprint: "fingerprint-a",
            createdAt: accountCreatedAt,
            updatedAt: accountCreatedAt,
            lastUsedAt: nil,
            quota: .unknown(accountId: accountA.uuidString, alias: "A"),
            isEnabled: true,
            priority: 0
        )
        let target = CodixxAccount(
            id: accountB,
            alias: "B",
            fingerprint: "fingerprint-b",
            createdAt: accountCreatedAt,
            updatedAt: accountCreatedAt,
            lastUsedAt: nil,
            quota: .unknown(accountId: accountB.uuidString, alias: "B"),
            isEnabled: true,
            priority: 1
        )
        let switchEvent = SwitchAuditEvent(
            timestamp: firstSwitchAt,
            trigger: .manual,
            sourceAccountId: accountA,
            sourceAlias: "A",
            targetAccountId: accountB,
            targetAlias: "B",
            sourcePrimaryUsedPercent: nil,
            sourceSecondaryUsedPercent: nil,
            threshold: nil,
            result: .success,
            errorSummary: nil,
            backupPath: nil
        )

        let windows = AppState.accountUsageWindows(
            accounts: [account, target],
            switchEvents: [switchEvent]
        )

        XCTAssertTrue(windows.contains {
            $0.accountId == accountA
                && $0.start == .distantPast
                && $0.end == firstSwitchAt
        })
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        predicate: @escaping @MainActor @Sendable () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await MainActor.run(body: predicate) { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for predicate")
    }
}

private final class InMemoryVault: AuthSnapshotVault {
    var snapshots: [String: AuthSnapshot] = [:]

    func save(snapshot: AuthSnapshot, fingerprint: String) throws {
        snapshots[fingerprint] = snapshot
    }

    func load(fingerprint: String) throws -> AuthSnapshot {
        guard let snapshot = snapshots[fingerprint] else {
            throw InMemoryVaultError.missingSnapshot
        }
        return snapshot
    }

    func delete(fingerprint: String) throws {
        snapshots.removeValue(forKey: fingerprint)
    }
}

private enum InMemoryVaultError: Error {
    case missingSnapshot
}

@MainActor
private final class CodexDesktopManagerSpy: CodexDesktopManaging {
    var isRunning = false
    var quitForCleanSwitchCallCount = 0
    var restartCallCount = 0
    var restoreActivationCallCount = 0

    func currentActivation() -> CodexActivation {
        CodexActivation(activeProcessIdentifier: nil)
    }

    func restoreActivationIfNeeded(_ activation: CodexActivation) {
        restoreActivationCallCount += 1
    }

    func quitForCleanSwitch() {
        quitForCleanSwitchCallCount += 1
    }

    func restart() throws {
        restartCallCount += 1
    }
}

private final class InMemoryAPIKeyVault: APIKeyVault {
    var keys: [String: String] = [:]

    func save(apiKey: String, fingerprint: String) throws {
        keys[fingerprint] = apiKey
    }

    func load(fingerprint: String) throws -> String {
        guard let key = keys[fingerprint] else {
            throw InMemoryVaultError.missingSnapshot
        }
        return key
    }

    func delete(fingerprint: String) throws {
        keys.removeValue(forKey: fingerprint)
    }
}

private final class APIBalanceQueryTesterSpy: APIBalanceQueryTesting, @unchecked Sendable {
    let result: APIBalanceQueryResult
    private(set) var callCount = 0

    init(result: APIBalanceQueryResult) {
        self.result = result
    }

    func queryBalance(url: URL, apiKey: String, jsonPath: String) async -> APIBalanceQueryResult {
        callCount += 1
        return result
    }
}
