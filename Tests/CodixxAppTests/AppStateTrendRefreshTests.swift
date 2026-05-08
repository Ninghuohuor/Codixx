import XCTest
@testable import CodixxApp
import CodixxCore

@MainActor
final class AppStateTrendRefreshTests: XCTestCase {
    func testAppStateCanSaveAPIProviderAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let apiKeyVault = InMemoryAPIKeyVault()
        let state = AppState(paths: CodixxPaths(home: directory), vault: InMemoryVault(), apiKeyVault: apiKeyVault)

        state.saveAPIProviderAccount(
            alias: "Relay",
            providerName: "Relay",
            baseURLText: "https://relay.example.com/v1",
            apiKey: "sk-test-123",
            defaultModel: "gpt-5"
        )

        XCTAssertEqual(state.accounts.first?.credentialKind, .apiProvider)
        XCTAssertEqual(state.accounts.first?.apiProvider?.baseURL.absoluteString, "https://relay.example.com/v1")
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

        let state = AppState(paths: paths, vault: InMemoryVault())

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
        let state = AppState(paths: CodixxPaths(home: directory), vault: InMemoryVault())

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
    func save(snapshot: AuthSnapshot, fingerprint: String) throws {}

    func load(fingerprint: String) throws -> AuthSnapshot {
        throw InMemoryVaultError.missingSnapshot
    }

    func delete(fingerprint: String) throws {}
}

private enum InMemoryVaultError: Error {
    case missingSnapshot
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
