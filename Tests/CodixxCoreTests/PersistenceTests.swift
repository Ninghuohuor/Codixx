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

    func testConfigStoreLoadsDefaultConfigWhenFileIsAbsent() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let paths = CodixxPaths(home: tempHome)
        let store = CodixxConfigStore(paths: paths)

        let config = try store.load()

        XCTAssertEqual(config.codexDirectoryPath, paths.codexHome.path)
        XCTAssertTrue(config.autoSwitchEnabled)
        XCTAssertEqual(config.primaryThresholdPercent, 93)
        XCTAssertTrue(config.notificationsEnabled)
        XCTAssertTrue(config.detailedSwitchLoggingEnabled)
        XCTAssertEqual(config.quotaRefreshIntervalSeconds, 60)
        XCTAssertEqual(config.usageRefreshIntervalSeconds, 300)
        XCTAssertEqual(config.language, .english)
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
            notificationsEnabled: false,
            detailedSwitchLoggingEnabled: false,
            quotaRefreshIntervalSeconds: 30,
            usageRefreshIntervalSeconds: 120,
            language: .chinese
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
}
