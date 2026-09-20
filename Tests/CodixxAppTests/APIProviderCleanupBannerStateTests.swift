import XCTest
@testable import CodixxApp
import CodixxCore

/// 覆盖「退出 API 登录」横幅的两种触发状态。
///
/// 这两条曾经被一个 `guard currentAuthMode != "apikey"` 合并成一条，导致用户
/// 主动切到 API 登录之后，横幅再也不出现、也就退不回去了。
@MainActor
final class APIProviderCleanupBannerStateTests: XCTestCase {
    /// 真实场景：用户用 Codixx 切到 API 登录。
    ///
    /// `auth.json` 是 apikey，`config.toml` 挂着托管 provider。
    /// 期望：给出「退出 API 登录」入口，但**不是**凭据外发警告 —— 用户就是
    /// 特意这么配的，弹警告就是假警报。
    func testAPIKeyLoginWithManagedProviderOffersSignOutWithoutLeakWarning() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        try writeAPIKeyAuth(to: paths)
        try writeManagedConfig(to: paths)

        let state = makeState(paths: paths)

        XCTAssertTrue(state.isSignedInWithAPIProvider)
        XCTAssertFalse(state.needsAPIProviderCleanup)
    }

    /// 危险态：ChatGPT 凭据还在，`config.toml` 仍指向中转站。
    /// 这是静默的凭据外发，必须给橙色警告。
    func testChatGPTLoginWithManagedProviderRaisesLeakWarning() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        try writeChatGPTAuth(to: paths)
        try writeManagedConfig(to: paths)

        let state = makeState(paths: paths)

        XCTAssertTrue(state.needsAPIProviderCleanup)
        XCTAssertFalse(state.isSignedInWithAPIProvider)
    }

    /// 干净状态：ChatGPT 登录 + 没有托管 provider。
    func testChatGPTLoginWithoutManagedProviderShowsNothing() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        try writeChatGPTAuth(to: paths)
        try writePlainConfig(to: paths)

        let state = makeState(paths: paths)

        XCTAssertFalse(state.needsAPIProviderCleanup)
        XCTAssertFalse(state.isSignedInWithAPIProvider)
    }

    /// API 登录，但 `config.toml` 里没有 Codixx 写的 provider 块。
    func testAPIKeyLoginWithoutManagedProviderShowsNothing() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        try writeAPIKeyAuth(to: paths)
        try writePlainConfig(to: paths)

        let state = makeState(paths: paths)

        XCTAssertFalse(state.needsAPIProviderCleanup)
        XCTAssertFalse(state.isSignedInWithAPIProvider)
    }

    /// 只剩根级 `model_provider = "openai-custom"`、BEGIN/END 块已被手删：
    /// 仍然算「挂着托管 provider」，两种状态都要能识别出来。
    func testRootModelProviderAloneStillCountsAsManagedRouting() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        try writeAPIKeyAuth(to: paths)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try #"model_provider = "openai-custom""#
            .write(to: paths.configTOML, atomically: true, encoding: .utf8)

        let state = makeState(paths: paths)

        XCTAssertTrue(state.isSignedInWithAPIProvider)
    }

    /// 没有 `auth.json`，但 `config.toml` 里托管 provider 块还在。
    ///
    /// 这时手上没有凭据，所以**不是**正在外发；但残留的块是个地雷 ——
    /// 下一次用 ChatGPT 登录，token 就会被发到中转站。所以照旧警告，
    /// 只是不把它算成「API 登录态」。
    func testMissingAuthJSONWithDirtyConfigStillWarnsAboutLatentLeak() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        try writeManagedConfig(to: paths)

        let state = makeState(paths: paths)

        XCTAssertTrue(state.needsAPIProviderCleanup)
        XCTAssertFalse(state.isSignedInWithAPIProvider)
    }

    // MARK: - Helpers

    private func makeState(paths: CodixxPaths) -> AppState {
        AppState(
            paths: paths,
            vault: InMemoryAuthSnapshotVault(),
            apiKeyVault: InMemoryAPIKeyVault(),
            codexDesktopState: NoopCodexDesktopStateCleaner(),
            now: { Date(timeIntervalSince1970: 1_778_000_000) }
        )
    }

    private func makeTempHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func writeAPIKeyAuth(to paths: CodixxPaths) throws {
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try #"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-relay-test"}"#
            .write(to: paths.authJSON, atomically: true, encoding: .utf8)
    }

    private func writeChatGPTAuth(to paths: CodixxPaths) throws {
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let json = #"{"auth_mode":"chatgpt","tokens":{"account_id":"acct_1","access_token":"secret"}}"#
        try json.write(to: paths.authJSON, atomically: true, encoding: .utf8)
    }

    /// 复刻 `CodexProviderConfigStore.writeAPIProvider` 的产物形态。
    private func writeManagedConfig(to paths: CodixxPaths) throws {
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let config = """
        model_provider = "openai-custom"

        # BEGIN CODIXX API PROVIDER
        [model_providers.openai-custom]
        name = "Relay"
        base_url = "https://relay.example.com"
        wire_api = "responses"
        requires_openai_auth = true
        # END CODIXX API PROVIDER
        """
        try config.write(to: paths.configTOML, atomically: true, encoding: .utf8)
    }

    private func writePlainConfig(to paths: CodixxPaths) throws {
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try #"model = "gpt-5""#
            .write(to: paths.configTOML, atomically: true, encoding: .utf8)
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
        snapshotDataByFingerprint[fingerprint] = nil
    }
}

private final class InMemoryAPIKeyVault: APIKeyVault {
    var keys: [String: String] = [:]

    func save(apiKey: String, fingerprint: String) throws {
        keys[fingerprint] = apiKey
    }

    func load(fingerprint: String) throws -> String {
        guard let apiKey = keys[fingerprint] else {
            throw AccountStoreError.keychainError("missing key \(fingerprint)")
        }
        return apiKey
    }

    func delete(fingerprint: String) throws {
        keys[fingerprint] = nil
    }
}
