import XCTest
@testable import CodixxApp
import CodixxCore

@MainActor
final class AppStateTrendRefreshTests: XCTestCase {
    func testReorderAccountsPersistsDisplayOrderWithoutChangingPriorities() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let first = displayOrderAccount(alias: "First", priority: 10, now: now)
        let second = displayOrderAccount(alias: "Second", priority: 20, now: now)
        let third = displayOrderAccount(alias: "Third", priority: 30, now: now)
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [first, second, third]))
        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            apiKeyVault: InMemoryAPIKeyVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            now: { now }
        )
        state.refreshNow()

        state.moveAccount(first, before: third)

        XCTAssertEqual(state.accounts.map(\.alias), ["Second", "First", "Third"])
        XCTAssertEqual(state.accounts.map(\.priority), [20, 10, 30])
        let persisted = try AccountMetadataStore(paths: paths).load().accounts
        XCTAssertEqual(persisted.map(\.alias), ["Second", "First", "Third"])
        XCTAssertEqual(persisted.map(\.priority), [20, 10, 30])
    }

    func testDragReorderPreviewsInMemoryAndPersistsOnceOnCommit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let first = displayOrderAccount(alias: "First", priority: 10, now: now)
        let second = displayOrderAccount(alias: "Second", priority: 20, now: now)
        let third = displayOrderAccount(alias: "Third", priority: 30, now: now)
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [first, second, third]))
        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            apiKeyVault: InMemoryAPIKeyVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            now: { now }
        )
        state.refreshNow()

        state.previewAccountMove(first, before: third)

        XCTAssertEqual(state.accounts.map(\.alias), ["Second", "First", "Third"])
        let persistedBeforeCommit = try AccountMetadataStore(paths: paths).load().accounts
        XCTAssertEqual(persistedBeforeCommit.map(\.alias), ["First", "Second", "Third"])
        XCTAssertTrue(try AppActivityLog(paths: paths).loadEvents().isEmpty)

        let task = try XCTUnwrap(state.scheduleAccountOrderCommit(movedAccountID: first.id))
        await task.value

        let persistedAfterCommit = try AccountMetadataStore(paths: paths).load().accounts
        XCTAssertEqual(persistedAfterCommit.map(\.alias), ["Second", "First", "Third"])
        XCTAssertEqual(try AppActivityLog(paths: paths).loadEvents().map(\.kind), [.accountReordered])

        XCTAssertNil(state.scheduleAccountOrderCommit(movedAccountID: first.id))

        XCTAssertEqual(try AppActivityLog(paths: paths).loadEvents().map(\.kind), [.accountReordered])
    }

    func testDragReorderCanPreviewMoveToEndByVisibleIndex() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let first = displayOrderAccount(alias: "First", priority: 10, now: now)
        let second = displayOrderAccount(alias: "Second", priority: 20, now: now)
        let third = displayOrderAccount(alias: "Third", priority: 30, now: now)
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [first, second, third]))
        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            apiKeyVault: InMemoryAPIKeyVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            now: { now }
        )
        state.refreshNow()

        state.previewAccountMove(first, toVisibleIndex: 2)

        XCTAssertEqual(state.accounts.map(\.alias), ["Second", "Third", "First"])
    }

    func testAccountSettingUpdatesUIImmediatelyAndPersistsInBackground() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let first = displayOrderAccount(alias: "First", priority: 10, now: now)
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [first]))
        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            apiKeyVault: InMemoryAPIKeyVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            now: { now }
        )
        state.refreshNow()

        state.setAccount(first, priority: 11)

        XCTAssertEqual(state.accounts.first?.priority, 11)
        try await waitUntil {
            (try? AccountMetadataStore(paths: paths).load().accounts.first?.priority) == 11
        }

        let updated = try XCTUnwrap(state.accounts.first)
        state.setAccount(updated, isEnabled: false)

        XCTAssertEqual(state.accounts.first?.isEnabled, false)
        try await waitUntil {
            (try? AccountMetadataStore(paths: paths).load().accounts.first?.isEnabled) == false
        }
        try await waitUntil {
            (try? AppActivityLog(paths: paths).loadEvents().map(\.kind)) == [.accountDisabled]
        }
    }

    func testConfigSettingUpdatesUIImmediatelyAndPersistsInBackground() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            apiKeyVault: InMemoryAPIKeyVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy()
        )

        state.setPrimaryThresholdPercent(88)

        XCTAssertEqual(state.config.primaryThresholdPercent, 88)
        try await waitUntil {
            (try? CodixxConfigStore(paths: paths).load().primaryThresholdPercent) == 88
        }
    }

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

    func testAPIProviderAutoSwitchRefreshesActivityBeforeReturningToChatGPT() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        var now = Date(timeIntervalSince1970: 1_778_000_000)
        let chatGPTAuth = try AuthSnapshot(jsonData: Data(#"{"account_id":"chatgpt","access_token":"chatgpt-secret"}"#.utf8))
        let chatGPTFingerprint = try AccountFingerprint.generate(from: chatGPTAuth)
        let vault = InMemoryVault()
        try vault.save(snapshot: chatGPTAuth, fingerprint: chatGPTFingerprint)
        let apiKeyVault = InMemoryAPIKeyVault()
        let apiKeyFingerprint = "api-key:cd0d9f0295a12e50"
        try apiKeyVault.save(apiKey: "sk-relay", fingerprint: apiKeyFingerprint)

        let api = CodixxAccount(
            id: UUID(),
            alias: "Relay",
            fingerprint: apiKeyFingerprint,
            credentialKind: .apiProvider,
            apiProvider: APIProviderAccount(
                providerName: "Relay",
                baseURL: URL(string: "https://relay.example.com/v1")!,
                defaultModel: nil,
                keyFingerprint: apiKeyFingerprint
            ),
            createdAt: now,
            updatedAt: now,
            lastUsedAt: now.addingTimeInterval(-600),
            quota: .unknown(accountId: apiKeyFingerprint, alias: "Relay"),
            isEnabled: true,
            priority: 0
        )
        let chatGPT = CodixxAccount(
            id: UUID(),
            alias: "ChatGPT",
            fingerprint: chatGPTFingerprint,
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil,
            quota: AccountQuotaState(
                accountId: "chatgpt",
                alias: "ChatGPT",
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
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [api, chatGPT]))
        try CodexProviderConfigStore(paths: paths).writeAPIProvider(
            providerID: "codixx-\(api.id.uuidString.lowercased())",
            providerName: "Relay",
            baseURL: URL(string: "https://relay.example.com/v1")!,
            defaultModel: nil
        )
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try AuthSnapshot.apiKey("sk-relay").jsonData.write(to: paths.authJSON)
        try writeThreadsDatabase(
            at: paths.latestStateDatabaseURL(),
            now: now,
            threadUpdatedAt: now.addingTimeInterval(-30)
        )

        let codexDesktopManager = CodexDesktopManagerSpy()
        let state = AppState(
            paths: paths,
            vault: vault,
            apiKeyVault: apiKeyVault,
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: codexDesktopManager,
            now: { now }
        )

        state.refreshQuotaNow()

        XCTAssertEqual(state.currentAccount?.id, api.id)
        XCTAssertEqual(state.usageSnapshot.activeThread?.id, "active")
        XCTAssertEqual(codexDesktopManager.restartCallCount, 0)

        now = now.addingTimeInterval(180)
        try writeThreadsDatabase(
            at: paths.latestStateDatabaseURL(),
            now: now,
            threadUpdatedAt: now.addingTimeInterval(-180)
        )

        state.refreshQuotaNow()

        XCTAssertEqual(state.currentAccount?.id, chatGPT.id)
        XCTAssertEqual(codexDesktopManager.quitForCleanSwitchCallCount, 1)
        XCTAssertEqual(codexDesktopManager.restartCallCount, 1)
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

    func testAPIBalanceRefreshAutoSwitchesFromDepletedAPIWhenIdle() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 1_778_300_000)
        let chatGPTAuth = try AuthSnapshot(jsonData: Data(#"{"account_id":"chatgpt","access_token":"chatgpt-secret"}"#.utf8))
        let chatGPTFingerprint = try AccountFingerprint.generate(from: chatGPTAuth)
        let vault = InMemoryVault()
        try vault.save(snapshot: chatGPTAuth, fingerprint: chatGPTFingerprint)
        let apiKeyVault = InMemoryAPIKeyVault()
        let apiAuth = try AuthSnapshot.apiKey("sk-relay")
        let apiKeyFingerprint = try AccountFingerprint.generate(from: apiAuth)
        try apiKeyVault.save(apiKey: "sk-relay", fingerprint: apiKeyFingerprint)
        try apiAuth.jsonData.write(to: paths.authJSON)

        let api = CodixxAccount(
            id: UUID(),
            alias: "Relay",
            fingerprint: apiKeyFingerprint,
            credentialKind: .apiProvider,
            apiProvider: APIProviderAccount(
                providerName: "Relay",
                baseURL: URL(string: "https://relay.example.com/v1")!,
                defaultModel: nil,
                keyFingerprint: apiKeyFingerprint,
                balanceQuery: APIBalanceQueryConfig(
                    isEnabled: true,
                    urlText: "https://relay.example.com/balance",
                    jsonPath: "data.balance",
                    minimumBalance: 0,
                    lastBalanceText: "10",
                    lastRefreshedAt: now.addingTimeInterval(-1_000)
                )
            ),
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil,
            quota: .unknown(accountId: apiKeyFingerprint, alias: "Relay"),
            isEnabled: true,
            priority: 0
        )
        let chatGPT = CodixxAccount(
            id: UUID(),
            alias: "ChatGPT",
            fingerprint: chatGPTFingerprint,
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil,
            quota: AccountQuotaState(
                accountId: "chatgpt",
                alias: "ChatGPT",
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
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [api, chatGPT]))
        let codexDesktopManager = CodexDesktopManagerSpy()
        let state = AppState(
            paths: paths,
            vault: vault,
            apiKeyVault: apiKeyVault,
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: codexDesktopManager,
            balanceQueryTester: APIBalanceQueryTesterSpy(result: APIBalanceQueryResult(isSuccess: true, message: "Balance: 0", balanceText: "0")),
            now: { now }
        )
        state.refreshQuotaNow()
        XCTAssertEqual(state.currentAccount?.id, api.id)

        await state.refreshDueAPIBalances(force: true)

        XCTAssertEqual(state.currentAccount?.id, chatGPT.id)
        XCTAssertEqual(codexDesktopManager.quitForCleanSwitchCallCount, 1)
        XCTAssertEqual(codexDesktopManager.restartCallCount, 1)
    }

    func testSwitchClearsStaleSaveStatusAndMarksTrendSnapshotStale() async throws {
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

        state.refreshTrendsIfNeeded()
        try await waitUntil { state.hasLoadedFullUsageSnapshot }
        XCTAssertTrue(state.hasLoadedFullUsageSnapshot)

        state.switchToAccount(second)

        XCTAssertNil(state.accountSaveStatus)
        XCTAssertFalse(state.hasLoadedFullUsageSnapshot)
        XCTAssertFalse(state.isLoadingFullUsageSnapshot)
    }

    func testAccountOperationsWriteActivityLogEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        var now = Date(timeIntervalSince1970: 1_778_000_000)
        let auth = try AuthSnapshot(jsonData: Data(#"{"account_id":"pro","access_token":"pro-secret"}"#.utf8))
        try auth.jsonData.write(to: paths.authJSON)
        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            now: { now }
        )

        state.saveCurrentAccount(alias: "Pro")
        now = now.addingTimeInterval(10)
        let saved = try XCTUnwrap(state.accounts.first)
        state.renameAccount(saved, alias: "Pro Renamed")

        let events = try AppActivityLog(paths: paths).loadEvents()
        XCTAssertEqual(events.map(\.kind), [.accountSaved, .accountRenamed])
        XCTAssertEqual(events.first?.accountAlias, "Pro")
        XCTAssertEqual(events.last?.accountAlias, "Pro")
        XCTAssertEqual(events.last?.secondaryAlias, "Pro Renamed")
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

    func testQuotaRefreshPreservesEffectiveTokenTotalsFromFullTrendSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_778_300_000)
        let rolloutURL = paths.codexHome.appendingPathComponent("sessions/2026/05/13/rollout.jsonl")
        try FileManager.default.createDirectory(
            at: rolloutURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeDetailedTokenUsageEvents(
            [
                (now.addingTimeInterval(-600), 10_000, 8_000, 750)
            ],
            to: rolloutURL
        )
        try writeCachedTokenUsageDatabase(
            at: paths.latestStateDatabaseURL(),
            now: now,
            rolloutURL: rolloutURL,
            rawTokens: 10_750
        )
        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            now: { now }
        )

        state.refreshNow()
        try await waitUntil { state.hasLoadedFullUsageSnapshot }

        XCTAssertEqual(state.usageSnapshot.totalTokens, 2_750)
        XCTAssertEqual(state.topThreads.first?.tokensUsed, 2_750)

        state.refreshQuotaNow()

        XCTAssertEqual(state.usageSnapshot.totalTokens, 2_750)
        XCTAssertEqual(state.usageSnapshot.threads.first?.tokensUsed, 2_750)
        XCTAssertEqual(state.topThreads.first?.tokensUsed, 2_750)
        XCTAssertEqual(state.usageSnapshot.activeThread?.tokensUsed, 2_750)
    }

    func testQuotaRefreshDoesNotShowRawTokenTotalsBeforeFullTrendSnapshotLoads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_778_300_000)
        let rolloutURL = paths.codexHome.appendingPathComponent("sessions/2026/05/13/rollout.jsonl")
        try FileManager.default.createDirectory(
            at: rolloutURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeDetailedTokenUsageEvents(
            [
                (now.addingTimeInterval(-600), 10_000, 8_000, 750)
            ],
            to: rolloutURL
        )
        try writeCachedTokenUsageDatabase(
            at: paths.latestStateDatabaseURL(),
            now: now,
            rolloutURL: rolloutURL,
            rawTokens: 10_750
        )
        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            now: { now }
        )

        state.refreshQuotaNow()

        XCTAssertFalse(state.hasLoadedFullUsageSnapshot)
        XCTAssertEqual(state.usageSnapshot.totalTokens, 0)
        XCTAssertTrue(state.usageSnapshot.threads.isEmpty)
        XCTAssertTrue(state.topThreads.isEmpty)
        XCTAssertEqual(state.usageSnapshot.activeThread?.id, "cached-heavy")
    }

    func testMenuOpenRefreshAutoSwitchesWhenLatestObservationShowsCurrentQuotaDepleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        let currentAuth = try AuthSnapshot(jsonData: Data(#"{"account_id":"current","access_token":"current-secret"}"#.utf8))
        let targetAuth = try AuthSnapshot(jsonData: Data(#"{"account_id":"target","access_token":"target-secret"}"#.utf8))
        try currentAuth.jsonData.write(to: paths.authJSON)
        let currentFingerprint = try AccountFingerprint.generate(from: currentAuth)
        let targetFingerprint = try AccountFingerprint.generate(from: targetAuth)
        let vault = InMemoryVault()
        try vault.save(snapshot: currentAuth, fingerprint: currentFingerprint)
        try vault.save(snapshot: targetAuth, fingerprint: targetFingerprint)
        let now = Date(timeIntervalSince1970: 1_778_300_000)
        let current = CodixxAccount(
            id: UUID(),
            alias: "Current",
            fingerprint: currentFingerprint,
            createdAt: now,
            updatedAt: now,
            lastUsedAt: now,
            quota: AccountQuotaState(
                accountId: "current",
                alias: "Current",
                primaryUsedPercent: 80,
                primaryWindowMinutes: 300,
                primaryResetsAt: now.addingTimeInterval(1_800),
                secondaryUsedPercent: 20,
                secondaryWindowMinutes: 10_080,
                secondaryResetsAt: now.addingTimeInterval(86_400),
                lastObservedAt: now,
                confidence: .fresh
            ),
            isEnabled: true,
            priority: 0
        )
        let target = CodixxAccount(
            id: UUID(),
            alias: "Target",
            fingerprint: targetFingerprint,
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil,
            quota: AccountQuotaState(
                accountId: "target",
                alias: "Target",
                primaryUsedPercent: 10,
                primaryWindowMinutes: 300,
                primaryResetsAt: now.addingTimeInterval(1_800),
                secondaryUsedPercent: 10,
                secondaryWindowMinutes: 10_080,
                secondaryResetsAt: now.addingTimeInterval(86_400),
                lastObservedAt: now,
                confidence: .fresh
            ),
            isEnabled: true,
            priority: 1
        )
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [current, target]))

        let sessionDirectory = paths.codexHome.appendingPathComponent("sessions/2026/05/12", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let sessionFile = sessionDirectory.appendingPathComponent("rollout.jsonl")
        let depletedObservation = """
        {"timestamp":"2026-05-12T09:40:01Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"limit_id":"codex","primary":{"used_percent":100.0,"window_minutes":300,"resets_at":1778313600},"secondary":{"used_percent":20.0,"window_minutes":10080,"resets_at":1778913600},"plan_type":"pro"}}
        """
        try (depletedObservation + "\n").write(to: sessionFile, atomically: true, encoding: .utf8)

        let codexDesktopManager = CodexDesktopManagerSpy()
        let state = AppState(
            paths: paths,
            vault: vault,
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: codexDesktopManager,
            now: { now }
        )

        state.refreshFromMenuOpen()

        XCTAssertEqual(state.currentAccount?.id, target.id)
        XCTAssertEqual(codexDesktopManager.quitForCleanSwitchCallCount, 1)
        XCTAssertEqual(codexDesktopManager.restartCallCount, 1)
    }

    func testQuotaRefreshDoesNotApplyObservationOlderThanCurrentAccountUse() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        let authData = Data(#"{"account_id":"acct_main","access_token":"secret"}"#.utf8)
        try authData.write(to: paths.authJSON)
        let fingerprint = try AccountFingerprint.generate(from: AuthSnapshot(jsonData: authData))
        let accountId = UUID()
        let currentUseTime = Date(timeIntervalSince1970: 1_778_300_000)
        let account = CodixxAccount(
            id: accountId,
            alias: "main",
            fingerprint: fingerprint,
            createdAt: currentUseTime,
            updatedAt: currentUseTime,
            lastUsedAt: currentUseTime,
            quota: .unknown(accountId: accountId.uuidString, alias: "main"),
            isEnabled: true,
            priority: 0
        )
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [account]))

        let sessionDirectory = paths.codexHome.appendingPathComponent("sessions/2026/05/08", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let sessionFile = sessionDirectory.appendingPathComponent("rollout.jsonl")
        let observationLine = """
        {"timestamp":"2026-05-08T01:00:00Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"primary":{"used_percent":62.0,"window_minutes":300,"resets_at":1778206586},"secondary":{"used_percent":72.0,"window_minutes":10080,"resets_at":1778700000},"plan_type":"plus"}}
        """
        try (observationLine + "\n").write(to: sessionFile, atomically: true, encoding: .utf8)

        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            now: { currentUseTime }
        )

        state.refreshFromMenuOpen()

        XCTAssertNil(state.currentAccount?.quota.primaryUsedPercent)
        XCTAssertNil(state.currentAccount?.quota.secondaryUsedPercent)
    }

    func testQuotaRefreshPrefersGlobalCodexLimitOverModelSpecificLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        let authData = Data(#"{"account_id":"acct_main","access_token":"secret"}"#.utf8)
        try authData.write(to: paths.authJSON)
        let fingerprint = try AccountFingerprint.generate(from: AuthSnapshot(jsonData: authData))
        let accountId = UUID()
        let currentUseTime = Date(timeIntervalSince1970: 1_778_300_000)
        let account = CodixxAccount(
            id: accountId,
            alias: "main",
            fingerprint: fingerprint,
            createdAt: currentUseTime,
            updatedAt: currentUseTime,
            lastUsedAt: currentUseTime,
            quota: .unknown(accountId: accountId.uuidString, alias: "main"),
            isEnabled: true,
            priority: 0
        )
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [account]))

        let sessionDirectory = paths.codexHome.appendingPathComponent("sessions/2026/05/12", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let sessionFile = sessionDirectory.appendingPathComponent("rollout.jsonl")
        let globalObservation = """
        {"timestamp":"2026-05-12T09:40:00Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"limit_id":"codex","primary":{"used_percent":17.0,"window_minutes":300,"resets_at":1778310000},"secondary":{"used_percent":23.0,"window_minutes":10080,"resets_at":1778910000},"plan_type":"pro"}}
        """
        let modelObservation = """
        {"timestamp":"2026-05-12T09:40:01Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":0.0,"window_minutes":300,"resets_at":1778313600},"secondary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1778913600},"plan_type":"pro"}}
        """
        try (globalObservation + "\n" + modelObservation + "\n").write(to: sessionFile, atomically: true, encoding: .utf8)

        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            now: { currentUseTime }
        )

        state.refreshFromMenuOpen()

        XCTAssertEqual(state.currentAccount?.quota.primaryUsedPercent, 17)
        XCTAssertEqual(state.currentAccount?.quota.secondaryUsedPercent, 23)
    }

    func testQuotaRefreshIgnoresModelSpecificLimitWhenNoGlobalLimitIsPresent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        let authData = Data(#"{"account_id":"acct_main","access_token":"secret"}"#.utf8)
        try authData.write(to: paths.authJSON)
        let fingerprint = try AccountFingerprint.generate(from: AuthSnapshot(jsonData: authData))
        let accountId = UUID()
        let currentUseTime = Date(timeIntervalSince1970: 1_778_300_000)
        let observedAt = currentUseTime.addingTimeInterval(-120)
        let account = CodixxAccount(
            id: accountId,
            alias: "main",
            fingerprint: fingerprint,
            createdAt: currentUseTime,
            updatedAt: currentUseTime,
            lastUsedAt: currentUseTime,
            quota: AccountQuotaState(
                accountId: accountId.uuidString,
                alias: "main",
                planType: "pro",
                primaryUsedPercent: 12,
                primaryWindowMinutes: 300,
                primaryResetsAt: currentUseTime.addingTimeInterval(1_800),
                secondaryUsedPercent: 34,
                secondaryWindowMinutes: 10_080,
                secondaryResetsAt: currentUseTime.addingTimeInterval(86_400),
                lastObservedAt: observedAt,
                confidence: .fresh
            ),
            isEnabled: true,
            priority: 0
        )
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [account]))

        let sessionDirectory = paths.codexHome.appendingPathComponent("sessions/2026/05/12", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let sessionFile = sessionDirectory.appendingPathComponent("rollout.jsonl")
        let modelObservation = """
        {"timestamp":"2026-05-12T09:40:01Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":0.0,"window_minutes":300,"resets_at":1778313600},"secondary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1778913600},"plan_type":"pro"}}
        """
        try (modelObservation + "\n").write(to: sessionFile, atomically: true, encoding: .utf8)

        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            now: { currentUseTime }
        )

        state.refreshFromMenuOpen()

        XCTAssertEqual(state.currentAccount?.quota.primaryUsedPercent, 12)
        XCTAssertEqual(state.currentAccount?.quota.secondaryUsedPercent, 34)
    }

    func testQuotaRefreshStillAcceptsLegacyLimitWithoutLimitID() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        let authData = Data(#"{"account_id":"acct_main","access_token":"secret"}"#.utf8)
        try authData.write(to: paths.authJSON)
        let fingerprint = try AccountFingerprint.generate(from: AuthSnapshot(jsonData: authData))
        let accountId = UUID()
        let currentUseTime = Date(timeIntervalSince1970: 1_778_300_000)
        let account = CodixxAccount(
            id: accountId,
            alias: "main",
            fingerprint: fingerprint,
            createdAt: currentUseTime,
            updatedAt: currentUseTime,
            lastUsedAt: currentUseTime,
            quota: .unknown(accountId: accountId.uuidString, alias: "main"),
            isEnabled: true,
            priority: 0
        )
        try AccountMetadataStore(paths: paths).save(AccountMetadataList(accounts: [account]))

        let sessionDirectory = paths.codexHome.appendingPathComponent("sessions/2026/05/12", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let sessionFile = sessionDirectory.appendingPathComponent("rollout.jsonl")
        let legacyObservation = """
        {"timestamp":"2026-05-12T09:40:01Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"primary":{"used_percent":45.0,"window_minutes":300,"resets_at":1778313600},"secondary":{"used_percent":67.0,"window_minutes":10080,"resets_at":1778913600},"plan_type":"pro"}}
        """
        try (legacyObservation + "\n").write(to: sessionFile, atomically: true, encoding: .utf8)

        let state = AppState(
            paths: paths,
            vault: InMemoryVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            codexDesktopManager: CodexDesktopManagerSpy(),
            now: { currentUseTime }
        )

        state.refreshFromMenuOpen()

        XCTAssertEqual(state.currentAccount?.quota.primaryUsedPercent, 45)
        XCTAssertEqual(state.currentAccount?.quota.secondaryUsedPercent, 67)
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

    func testAccountUsageWindowsAttributeRecentUsageToCurrentAccountAfterExternalLogin() throws {
        let accountA = UUID()
        let accountB = UUID()
        let currentAccountId = UUID()
        let accountCreatedAt = Date(timeIntervalSince1970: 1_777_000_000)
        let firstSwitchAt = Date(timeIntervalSince1970: 1_778_000_000)
        let currentBecameActiveAt = firstSwitchAt.addingTimeInterval(120)
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
        let current = CodixxAccount(
            id: currentAccountId,
            alias: "Current",
            fingerprint: "fingerprint-current",
            createdAt: accountCreatedAt,
            updatedAt: currentBecameActiveAt,
            lastUsedAt: currentBecameActiveAt,
            quota: .unknown(accountId: currentAccountId.uuidString, alias: "Current"),
            isEnabled: true,
            priority: 2
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
            accounts: [account, target, current],
            switchEvents: [switchEvent],
            currentAccount: current
        )

        XCTAssertEqual(windows, [
            AccountUsageWindow(accountId: accountA, start: .distantPast, end: firstSwitchAt),
            AccountUsageWindow(accountId: accountB, start: firstSwitchAt, end: currentBecameActiveAt),
            AccountUsageWindow(accountId: currentAccountId, start: currentBecameActiveAt, end: nil)
        ])
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

    private func writeThreadsDatabase(at url: URL, now: Date, threadUpdatedAt: Date) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            url.path,
            """
            CREATE TABLE threads(
                id TEXT PRIMARY KEY,
                title TEXT,
                model TEXT,
                reasoning_effort TEXT,
                tokens_used INTEGER,
                cwd TEXT,
                created_at INTEGER,
                updated_at INTEGER,
                rollout_path TEXT
            );
            INSERT INTO threads VALUES(
                'active',
                'Active API task',
                'gpt-5',
                'medium',
                100,
                '',
                \(Int(now.addingTimeInterval(-300).timeIntervalSince1970)),
                \(Int(threadUpdatedAt.timeIntervalSince1970)),
                '/tmp/active.jsonl'
            );
            """
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func writeCachedTokenUsageDatabase(
        at url: URL,
        now: Date,
        rolloutURL: URL,
        rawTokens: Int
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            url.path,
            """
            CREATE TABLE threads(
                id TEXT PRIMARY KEY,
                title TEXT,
                model TEXT,
                reasoning_effort TEXT,
                tokens_used INTEGER,
                cwd TEXT,
                created_at INTEGER,
                updated_at INTEGER,
                rollout_path TEXT
            );
            INSERT INTO threads VALUES(
                'cached-heavy',
                'Cached Heavy',
                'gpt-5',
                'medium',
                \(rawTokens),
                '',
                \(Int(now.addingTimeInterval(-3_600).timeIntervalSince1970)),
                \(Int(now.addingTimeInterval(-600).timeIntervalSince1970)),
                '\(rolloutURL.path)'
            );
            """
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func writeDetailedTokenUsageEvents(_ events: [(Date, Int, Int, Int)], to url: URL) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = events.map { date, inputTokens, cachedInputTokens, outputTokens in
            let totalTokens = inputTokens + outputTokens
            return """
            {"timestamp":"\(formatter.string(from: date))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(inputTokens),"cached_input_tokens":\(cachedInputTokens),"output_tokens":\(outputTokens),"total_tokens":\(totalTokens)}}}}
            """
        }
        try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
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

private func displayOrderAccount(alias: String, priority: Int, now: Date) -> CodixxAccount {
    CodixxAccount(
        id: UUID(),
        alias: alias,
        fingerprint: "fingerprint-\(alias)",
        createdAt: now,
        updatedAt: now,
        lastUsedAt: nil,
        quota: .unknown(accountId: alias, alias: alias),
        isEnabled: true,
        priority: priority
    )
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
