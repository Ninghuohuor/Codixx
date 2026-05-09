import XCTest
@testable import CodixxCore

final class PersistenceTests: XCTestCase {
    func testPathsResolveCodexHomeAndCreateApplicationSupportDirectories() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let paths = CodixxPaths(home: tempHome)
        try paths.createApplicationSupportDirectories()

        XCTAssertEqual(paths.codexHome.path, tempHome.appendingPathComponent(".codex").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.applicationSupport.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.backups.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.logs.path))
    }

    func testPathsChooseHighestVersionCodexStateDatabase() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try Data().write(to: paths.codexHome.appendingPathComponent("state_5.sqlite"))
        try Data().write(to: paths.codexHome.appendingPathComponent("state_6.sqlite"))
        try Data().write(to: paths.codexHome.appendingPathComponent("state_notes.sqlite"))

        let selectedURL = paths.latestStateDatabaseURL()

        XCTAssertEqual(selectedURL.lastPathComponent, "state_6.sqlite")
    }

    func testThreadProviderSyncUpdatesMatchingThreadsAndWritesBackup() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        try paths.createApplicationSupportDirectories()
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let databaseURL = paths.codexHome.appendingPathComponent("state_5.sqlite")
        try runSQLite(
            databaseURL,
            sql: """
            CREATE TABLE threads(id TEXT PRIMARY KEY, model_provider TEXT);
            INSERT INTO threads VALUES('openai-thread', 'openai');
            INSERT INTO threads VALUES('custom-thread', 'rightcode');
            """
        )
        let sync = SQLiteCodexThreadProviderSync(paths: paths)

        let changedRows = try sync.syncProvider(from: "openai", to: "openai-custom")

        XCTAssertEqual(changedRows, 1)
        XCTAssertEqual(try sqliteScalar(databaseURL, sql: "SELECT model_provider FROM threads WHERE id = 'openai-thread'"), "openai-custom")
        XCTAssertEqual(try sqliteScalar(databaseURL, sql: "SELECT model_provider FROM threads WHERE id = 'custom-thread'"), "rightcode")
        let backups = try FileManager.default.contentsOfDirectory(atPath: paths.backups.path)
        XCTAssertTrue(backups.contains { $0.hasPrefix("state_5.sqlite.provider-sync-") })
    }

    func testThreadProviderSyncUpdatesSessionMetadataRolloutFiles() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        try paths.createApplicationSupportDirectories()
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let sessionURL = paths.codexHome.appendingPathComponent("sessions/rollout-test.jsonl")
        try FileManager.default.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {"type":"session_meta","payload":{"id":"thread-1","model_provider":"openai","source":"vscode"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"hi"}}
        """.write(to: sessionURL, atomically: true, encoding: .utf8)
        let databaseURL = paths.codexHome.appendingPathComponent("state_5.sqlite")
        try runSQLite(
            databaseURL,
            sql: """
            CREATE TABLE threads(id TEXT PRIMARY KEY, model_provider TEXT, rollout_path TEXT);
            INSERT INTO threads VALUES('thread-1', 'openai', '\(sessionURL.path)');
            """
        )
        let sync = SQLiteCodexThreadProviderSync(paths: paths)

        let changedRows = try sync.syncProvider(from: "openai", to: "openai-custom")

        XCTAssertEqual(changedRows, 1)
        XCTAssertEqual(try sqliteScalar(databaseURL, sql: "SELECT model_provider FROM threads WHERE id = 'thread-1'"), "openai-custom")
        let firstLine = try String(contentsOf: sessionURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first
        XCTAssertTrue(firstLine?.contains(#""model_provider":"openai-custom""#) == true)
        let backups = try FileManager.default.contentsOfDirectory(atPath: paths.backups.path)
        XCTAssertTrue(backups.contains { $0.hasPrefix("rollout-test.jsonl.provider-sync-") })
    }

    func testThreadProviderSyncRestoresSessionMetadataWhenDatabaseUpdateFails() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        try paths.createApplicationSupportDirectories()
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let sessionURL = paths.codexHome.appendingPathComponent("sessions/rollout-test.jsonl")
        try FileManager.default.createDirectory(at: sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let originalSessionText = """
        {"type":"session_meta","payload":{"id":"thread-1","model_provider":"openai","source":"vscode"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"hi"}}
        """
        try originalSessionText.write(to: sessionURL, atomically: true, encoding: .utf8)
        let databaseURL = paths.codexHome.appendingPathComponent("state_5.sqlite")
        try runSQLite(
            databaseURL,
            sql: """
            CREATE TABLE threads(id TEXT PRIMARY KEY, model_provider TEXT, rollout_path TEXT);
            CREATE TRIGGER fail_provider_update BEFORE UPDATE OF model_provider ON threads
            BEGIN
                SELECT RAISE(ABORT, 'forced provider update failure');
            END;
            INSERT INTO threads VALUES('thread-1', 'openai', '\(sessionURL.path)');
            """
        )
        let sync = SQLiteCodexThreadProviderSync(paths: paths)

        XCTAssertThrowsError(try sync.syncProvider(from: "openai", to: "openai-custom"))

        XCTAssertEqual(try String(contentsOf: sessionURL, encoding: .utf8), originalSessionText)
        XCTAssertEqual(try sqliteScalar(databaseURL, sql: "SELECT model_provider FROM threads WHERE id = 'thread-1'"), "openai")
    }

    func testThreadProviderSyncOnlyUpdatesVisibleDesktopThreads() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        try paths.createApplicationSupportDirectories()
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let visibleSessionURL = paths.codexHome.appendingPathComponent("sessions/visible.jsonl")
        let subagentSessionURL = paths.codexHome.appendingPathComponent("sessions/subagent.jsonl")
        try FileManager.default.createDirectory(at: visibleSessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sessionText(id: "visible", provider: "openai", source: "vscode")
            .write(to: visibleSessionURL, atomically: true, encoding: .utf8)
        try sessionText(id: "subagent", provider: "openai", source: #"subagent"#)
            .write(to: subagentSessionURL, atomically: true, encoding: .utf8)
        let databaseURL = paths.codexHome.appendingPathComponent("state_5.sqlite")
        try runSQLite(
            databaseURL,
            sql: """
            CREATE TABLE threads(id TEXT PRIMARY KEY, model_provider TEXT, source TEXT, rollout_path TEXT);
            INSERT INTO threads VALUES('visible', 'openai', 'vscode', '\(visibleSessionURL.path)');
            INSERT INTO threads VALUES('subagent', 'openai', '{"subagent":true}', '\(subagentSessionURL.path)');
            """
        )
        let sync = SQLiteCodexThreadProviderSync(paths: paths)

        let changedRows = try sync.syncProvider(from: "openai", to: "openai-custom")

        XCTAssertEqual(changedRows, 1)
        XCTAssertEqual(try sqliteScalar(databaseURL, sql: "SELECT model_provider FROM threads WHERE id = 'visible'"), "openai-custom")
        XCTAssertEqual(try sqliteScalar(databaseURL, sql: "SELECT model_provider FROM threads WHERE id = 'subagent'"), "openai")
        XCTAssertTrue(try String(contentsOf: visibleSessionURL).contains(#""model_provider":"openai-custom""#))
        XCTAssertTrue(try String(contentsOf: subagentSessionURL).contains(#""model_provider":"openai""#))
    }

    func testThreadProviderSyncCanUpdateAllThreads() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        try paths.createApplicationSupportDirectories()
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let visibleSessionURL = paths.codexHome.appendingPathComponent("sessions/visible.jsonl")
        let subagentSessionURL = paths.codexHome.appendingPathComponent("sessions/subagent.jsonl")
        try FileManager.default.createDirectory(at: visibleSessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sessionText(id: "visible", provider: "openai", source: "vscode")
            .write(to: visibleSessionURL, atomically: true, encoding: .utf8)
        try sessionText(id: "subagent", provider: "openai", source: #"subagent"#)
            .write(to: subagentSessionURL, atomically: true, encoding: .utf8)
        let databaseURL = paths.codexHome.appendingPathComponent("state_5.sqlite")
        try runSQLite(
            databaseURL,
            sql: """
            CREATE TABLE threads(id TEXT PRIMARY KEY, model_provider TEXT, source TEXT, rollout_path TEXT);
            INSERT INTO threads VALUES('visible', 'openai', 'vscode', '\(visibleSessionURL.path)');
            INSERT INTO threads VALUES('subagent', 'openai', '{"subagent":true}', '\(subagentSessionURL.path)');
            """
        )
        let sync = SQLiteCodexThreadProviderSync(paths: paths)

        let changedRows = try sync.syncProvider(from: "openai", to: "openai-custom", scope: .allThreads)

        XCTAssertEqual(changedRows, 2)
        XCTAssertEqual(try sqliteScalar(databaseURL, sql: "SELECT model_provider FROM threads WHERE id = 'visible'"), "openai-custom")
        XCTAssertEqual(try sqliteScalar(databaseURL, sql: "SELECT model_provider FROM threads WHERE id = 'subagent'"), "openai-custom")
        XCTAssertTrue(try String(contentsOf: visibleSessionURL).contains(#""model_provider":"openai-custom""#))
        XCTAssertTrue(try String(contentsOf: subagentSessionURL).contains(#""model_provider":"openai-custom""#))
    }

    func testConfigStoreLoadsDefaultConfigWhenFileIsAbsent() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        let store = CodixxConfigStore(paths: paths)

        let config = try store.load()

        XCTAssertEqual(config.codexDirectoryPath, paths.codexHome.path)
        XCTAssertTrue(config.autoSwitchEnabled)
        XCTAssertEqual(config.primaryThresholdPercent, 93)
        XCTAssertEqual(config.secondaryThresholdPercent, 90)
        XCTAssertTrue(config.notificationsEnabled)
        XCTAssertTrue(config.detailedSwitchLoggingEnabled)
        XCTAssertEqual(config.quotaRefreshIntervalSeconds, 60)
        XCTAssertEqual(config.usageRefreshIntervalSeconds, 300)
        XCTAssertEqual(config.language, .english)
        XCTAssertEqual(config.postSwitchAction, .notifyRestartRecommended)
        XCTAssertEqual(config.apiSwitchThreadSyncScope, .visibleDesktopThreads)
    }

    func testConfigStoreSavesAndLoadsConfigJSON() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        let store = CodixxConfigStore(paths: paths)
        let config = CodixxConfig(
            codexDirectoryPath: "/tmp/codex",
            autoSwitchEnabled: false,
            primaryThresholdPercent: 88,
            secondaryThresholdPercent: 85,
            notificationsEnabled: false,
            detailedSwitchLoggingEnabled: false,
            quotaRefreshIntervalSeconds: 30,
            usageRefreshIntervalSeconds: 120,
            language: .chinese,
            postSwitchAction: .restartCodexApp,
            apiSwitchThreadSyncScope: .allThreads
        )

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded, config)
        XCTAssertEqual(loaded.language, .chinese)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.configJSON.path))
    }

    func testConfigStoreLoadsLegacyConfigWithoutLanguageAsEnglish() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        try paths.createApplicationSupportDirectories()
        let legacyJSON = """
        {
          "codexDirectoryPath": "/tmp/codex",
          "autoSwitchEnabled": false,
          "primaryThresholdPercent": 88,
          "notificationsEnabled": false,
          "detailedSwitchLoggingEnabled": false,
          "quotaRefreshIntervalSeconds": 30,
          "usageRefreshIntervalSeconds": 120
        }
        """
        try legacyJSON.data(using: .utf8)?.write(to: paths.configJSON)
        let store = CodixxConfigStore(paths: paths)

        let loaded = try store.load()

        XCTAssertEqual(loaded.codexDirectoryPath, "/tmp/codex")
        XCTAssertEqual(loaded.language, .english)
        XCTAssertEqual(loaded.postSwitchAction, .notifyRestartRecommended)
        XCTAssertEqual(loaded.apiSwitchThreadSyncScope, .visibleDesktopThreads)
        XCTAssertEqual(loaded.secondaryThresholdPercent, 90)
    }

    func testConfigStorePathsCannotBeMutatedAfterInitialization() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let otherHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempHome)
            try? FileManager.default.removeItem(at: otherHome)
        }

        let store = CodixxConfigStore(paths: CodixxPaths(home: tempHome))

        XCTAssertEqual(store.paths.configJSON.path, CodixxPaths(home: tempHome).configJSON.path)
        XCTAssertNotEqual(store.paths.configJSON.path, CodixxPaths(home: otherHome).configJSON.path)
    }

    func testJSONFileStoreOverwritesExistingFileAndLeavesNoTemporaryFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        let store = JSONFileStore<CodixxConfig>(url: url)

        try store.save(CodixxConfig(codexDirectoryPath: "/first"))
        try store.save(CodixxConfig(codexDirectoryPath: "/second"))

        let loaded = try store.load()
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        XCTAssertEqual(loaded.codexDirectoryPath, "/second")
        XCTAssertEqual(entries, ["config.json"])
    }

    func testAccountMetadataStoreLoadsEmptyListWhenFileIsAbsent() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        let store = AccountMetadataStore(paths: paths)

        let loaded = try store.load()

        XCTAssertEqual(loaded.accounts, [])
    }

    func testAccountMetadataStoreSavesAndLoadsAccountsJSON() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        let store = AccountMetadataStore(paths: paths)
        let account = CodixxAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            alias: "Main",
            fingerprint: "abc123",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            lastUsedAt: Date(timeIntervalSince1970: 3),
            quota: .unknown(accountId: "11111111-1111-1111-1111-111111111111", alias: "Main"),
            isEnabled: true,
            priority: 10
        )

        try store.save(AccountMetadataList(accounts: [account]))
        let loaded = try store.load()

        XCTAssertEqual(loaded.accounts.first?.alias, "Main")
        XCTAssertEqual(loaded.accounts, [account])
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.accountsJSON.path))
    }

    func testAccountMetadataStoreRoundTripsAPIProviderAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let store = AccountMetadataStore(paths: paths)
        let id = UUID()
        let account = CodixxAccount(
            id: id,
            alias: "Relay",
            fingerprint: "api:abc123",
            credentialKind: .apiProvider,
            apiProvider: APIProviderAccount(
                providerName: "Relay",
                baseURL: URL(string: "https://relay.example.com/v1")!,
                defaultModel: "gpt-5",
                keyFingerprint: "api-key:abc123"
            ),
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            lastUsedAt: nil,
            quota: .unknown(accountId: id.uuidString, alias: "Relay"),
            isEnabled: true,
            priority: 0
        )

        try store.save(AccountMetadataList(accounts: [account]))

        XCTAssertEqual(try store.load().accounts, [account])
    }

    func testProviderConfigStoreWritesManagedProviderWithoutDroppingExistingConfig() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try """
        model = "gpt-5.5"

        [projects."/tmp/example"]
        trust_level = "trusted"
        """.write(to: paths.configTOML, atomically: true, encoding: .utf8)
        let store = CodexProviderConfigStore(paths: paths)

        try store.writeAPIProvider(
            providerID: "codixx-relay",
            providerName: "Relay",
            baseURL: URL(string: "https://relay.example.com/v1")!,
            defaultModel: "gpt-5"
        )

        let text = try String(contentsOf: paths.configTOML)
        XCTAssertTrue(text.contains("model_provider = \"codixx-relay\""))
        XCTAssertTrue(text.contains("model = \"gpt-5\""))
        XCTAssertTrue(text.contains("[model_providers.codixx-relay]"))
        XCTAssertTrue(text.contains("base_url = \"https://relay.example.com/v1\""))
        XCTAssertTrue(text.contains("wire_api = \"responses\""))
        XCTAssertTrue(text.contains("[projects.\"/tmp/example\"]"))
    }

    func testProviderConfigStoreDoesNotDefaultModelWhenUnset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        let store = CodexProviderConfigStore(paths: paths)

        try store.writeAPIProvider(
            providerID: "codixx-relay",
            providerName: "Relay",
            baseURL: URL(string: "https://relay.example.com/v1")!,
            defaultModel: nil
        )

        let text = try String(contentsOf: paths.configTOML)
        XCTAssertTrue(text.contains("model_provider = \"codixx-relay\""))
        XCTAssertFalse(text.contains("model = \"gpt-5\""))
        XCTAssertFalse(text.contains("model = "))
    }

    func testProviderConfigStoreRestoresBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try "model = \"gpt-5.5\"\n".write(to: paths.configTOML, atomically: true, encoding: .utf8)
        let store = CodexProviderConfigStore(paths: paths)

        let backup = try store.backupConfig()
        try store.writeAPIProvider(
            providerID: "codixx-relay",
            providerName: "Relay",
            baseURL: URL(string: "https://relay.example.com/v1")!,
            defaultModel: "gpt-5"
        )
        try store.restoreConfig(from: backup)

        XCTAssertEqual(try String(contentsOf: paths.configTOML), "model = \"gpt-5.5\"\n")
    }

    func testProviderConfigStoreClearsManagedProviderForChatGPTSwitch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try """
        model = "gpt-5"
        model_provider = "codixx-relay"

        # BEGIN CODIXX API PROVIDER
        [model_providers.codixx-relay]
        name = "Relay"
        base_url = "https://relay.example.com/v1"
        wire_api = "responses"
        # END CODIXX API PROVIDER

        [projects."/tmp/example"]
        trust_level = "trusted"
        """.write(to: paths.configTOML, atomically: true, encoding: .utf8)
        let store = CodexProviderConfigStore(paths: paths)

        try store.clearManagedAPIProvider()

        let text = try String(contentsOf: paths.configTOML)
        XCTAssertFalse(text.contains("model_provider = \"codixx-relay\""))
        XCTAssertFalse(text.contains("BEGIN CODIXX API PROVIDER"))
        XCTAssertFalse(text.contains("[model_providers.codixx-relay]"))
        XCTAssertTrue(text.contains("model = \"gpt-5\""))
        XCTAssertTrue(text.contains("[projects.\"/tmp/example\"]"))
    }

    func testProviderConfigStoreClearsManagedOpenAICustomProviderForChatGPTSwitch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try """
        model = "gpt-5"
        model_provider = "openai-custom"

        # BEGIN CODIXX API PROVIDER
        [model_providers.openai-custom]
        name = "Relay"
        base_url = "https://relay.example.com/v1"
        wire_api = "responses"
        # END CODIXX API PROVIDER

        [projects."/tmp/example"]
        trust_level = "trusted"
        """.write(to: paths.configTOML, atomically: true, encoding: .utf8)
        let store = CodexProviderConfigStore(paths: paths)

        try store.clearManagedAPIProvider()

        let text = try String(contentsOf: paths.configTOML)
        XCTAssertFalse(text.contains("model_provider = \"openai-custom\""))
        XCTAssertFalse(text.contains("BEGIN CODIXX API PROVIDER"))
        XCTAssertFalse(text.contains("[model_providers.openai-custom]"))
        XCTAssertTrue(text.contains("model = \"gpt-5\""))
        XCTAssertTrue(text.contains("[projects.\"/tmp/example\"]"))
    }

    func testSwitchAuditLogPrunesEventsOlderThanNinetyDays() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        let now = Date(timeIntervalSince1970: 10_000_000)
        let log = SwitchAuditLog(paths: paths, retention: .init(now: { now }))

        try log.append(event(timestamp: now.addingTimeInterval(-91 * 86_400), alias: "Old"))
        try log.append(event(timestamp: now.addingTimeInterval(-89 * 86_400), alias: "Recent"))

        let loaded = try log.loadEvents()

        XCTAssertEqual(loaded.map(\.targetAlias), ["Recent"])
    }

    func testSwitchAuditLogPrunesToMaximumSize() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        let log = SwitchAuditLog(paths: paths, retention: .init(maximumBytes: 900, now: { Date(timeIntervalSince1970: 1_000) }))

        for index in 0..<20 {
            try log.append(event(timestamp: Date(timeIntervalSince1970: Double(index)), alias: "Account \(index)"))
        }

        let data = try Data(contentsOf: paths.switchAuditJSONL)
        let loaded = try log.loadEvents()

        XCTAssertLessThanOrEqual(data.count, 900)
        XCTAssertEqual(loaded.last?.targetAlias, "Account 19")
    }

    func testSwitchAuditLogRotatesToThreeHistoryFiles() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        let log = SwitchAuditLog(paths: paths, retention: .init(maximumBytes: 900, now: { Date(timeIntervalSince1970: 1_000) }))

        for index in 0..<30 {
            try log.append(event(timestamp: Date(timeIntervalSince1970: Double(index)), alias: "Account \(index)"))
        }

        let historyURLs = (1...3).map { switchAuditHistoryURL(paths: paths, index: $0) }
        let staleHistoryURL = switchAuditHistoryURL(paths: paths, index: 4)
        let loaded = try log.loadEvents()

        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURLs[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURLs[1].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURLs[2].path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleHistoryURL.path))
        XCTAssertLessThanOrEqual(try Data(contentsOf: paths.switchAuditJSONL).count, 900)
        for historyURL in historyURLs {
            XCTAssertLessThanOrEqual(try Data(contentsOf: historyURL).count, 900)
        }
        XCTAssertEqual(loaded.last?.targetAlias, "Account 29")
    }

    private func event(timestamp: Date, alias: String) -> SwitchAuditEvent {
        SwitchAuditEvent(
            timestamp: timestamp,
            trigger: .manual,
            sourceAccountId: nil,
            sourceAlias: nil,
            targetAccountId: nil,
            targetAlias: alias,
            sourcePrimaryUsedPercent: nil,
            sourceSecondaryUsedPercent: nil,
            threshold: nil,
            result: .success,
            errorSummary: nil,
            backupPath: nil
        )
    }

    private func switchAuditHistoryURL(paths: CodixxPaths, index: Int) -> URL {
        paths.applicationSupport.appendingPathComponent("switch_audit.\(index).jsonl")
    }

    private func sessionText(id: String, provider: String, source: String) -> String {
        """
        {"type":"session_meta","payload":{"id":"\(id)","model_provider":"\(provider)","source":"\(source)"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"hi"}}
        """
    }

    private func runSQLite(_ databaseURL: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func sqliteScalar(_ databaseURL: URL, sql: String) throws -> String {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-noheader", databaseURL.path, sql]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
