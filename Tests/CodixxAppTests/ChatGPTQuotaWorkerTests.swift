import XCTest
import CodixxCore
@testable import CodixxApp

final class ChatGPTQuotaWorkerTests: XCTestCase {
    func testExpiredActiveCredentialsAreNeverRotatedOrWritten() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.saved.jsonData.write(to: fixture.paths.authJSON)
        let worker = fixture.worker { _, _ in throw ChatGPTQuotaClient.QueryError.expiredLogin }

        await expectActiveRefreshPending { try await worker.query(for: fixture.account) }

        let calls = await fixture.refreshCalls.count
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.paths.authJSON), fixture.saved.jsonData)
        XCTAssertEqual(try fixture.vault.load(fingerprint: fixture.account.fingerprint), fixture.saved)
    }

    func testUsesCredentialsAlreadyRefreshedByCodexWithoutRotatingAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.saved.jsonData.write(to: fixture.paths.authJSON)
        let worker = fixture.worker { snapshot, account in
            if snapshot == fixture.saved {
                try fixture.renewed.jsonData.write(to: fixture.paths.authJSON)
                throw ChatGPTQuotaClient.QueryError.expiredLogin
            }
            XCTAssertEqual(snapshot, fixture.renewed)
            return .unknown(accountId: account.id.uuidString, alias: account.alias)
        }

        _ = try await worker.query(for: fixture.account)

        let calls = await fixture.refreshCalls.count
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.paths.authJSON), fixture.renewed.jsonData)
    }

    func testInactiveAccountStillRefreshesItsSavedSnapshot() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let live = try AuthSnapshot.apiKey("test-inactive-provider")
        try live.jsonData.write(to: fixture.paths.authJSON)
        let worker = fixture.worker { snapshot, account in
            if snapshot == fixture.saved { throw ChatGPTQuotaClient.QueryError.expiredLogin }
            XCTAssertEqual(snapshot, fixture.renewed)
            return .unknown(accountId: account.id.uuidString, alias: account.alias)
        }

        _ = try await worker.query(for: fixture.account)

        let calls = await fixture.refreshCalls.count
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try fixture.vault.load(fingerprint: fixture.account.fingerprint), fixture.renewed)
        XCTAssertEqual(try Data(contentsOf: fixture.paths.authJSON), live.jsonData)
    }

    func testAccountActivatedDuringQuotaRequestIsNotRotated() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try AuthSnapshot.apiKey("test-other-provider").jsonData.write(to: fixture.paths.authJSON)
        let worker = fixture.worker { _, _ in
            try fixture.saved.jsonData.write(to: fixture.paths.authJSON)
            throw ChatGPTQuotaClient.QueryError.expiredLogin
        }

        await expectActiveRefreshPending { try await worker.query(for: fixture.account) }

        let calls = await fixture.refreshCalls.count
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.paths.authJSON), fixture.saved.jsonData)
    }

    func testAccountDeactivatedDuringRequestDoesNotRefreshItsFormerLiveSnapshot() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.saved.jsonData.write(to: fixture.paths.authJSON)
        let newLive = try AuthSnapshot.apiKey("test-new-provider")
        let worker = fixture.worker { _, _ in
            try newLive.jsonData.write(to: fixture.paths.authJSON)
            throw ChatGPTQuotaClient.QueryError.expiredLogin
        }

        await expectExpired { try await worker.query(for: fixture.account) }

        let calls = await fixture.refreshCalls.count
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.paths.authJSON), newLive.jsonData)
    }

    func testSignedOutCodexCanStillMonitorSavedAccountsWithoutCreatingLiveAuth() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let worker = fixture.worker { snapshot, account in
            if snapshot == fixture.saved { throw ChatGPTQuotaClient.QueryError.expiredLogin }
            return .unknown(accountId: account.id.uuidString, alias: account.alias)
        }

        _ = try await worker.query(for: fixture.account)

        let calls = await fixture.refreshCalls.count
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.authJSON.path))
        XCTAssertEqual(try fixture.vault.load(fingerprint: fixture.account.fingerprint), fixture.renewed)
    }

    func testUnreadableLoginStateDoesNotPermitTokenRotation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let malformed = Data("not-json".utf8)
        try malformed.write(to: fixture.paths.authJSON)
        let worker = fixture.worker { _, _ in throw ChatGPTQuotaClient.QueryError.expiredLogin }

        do {
            _ = try await worker.query(for: fixture.account)
            XCTFail("An unknown active login must not be treated as an inactive account")
        } catch {}

        let calls = await fixture.refreshCalls.count
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.paths.authJSON), malformed)
    }

    func testRejectedRefreshReservationDoesNotRotateToken() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try AuthSnapshot.apiKey("test-other-provider").jsonData.write(to: fixture.paths.authJSON)
        var worker = fixture.worker { _, _ in throw ChatGPTQuotaClient.QueryError.expiredLogin }
        worker.beginCredentialRefresh = { _ in false }

        await expectActiveRefreshPending { try await worker.query(for: fixture.account) }

        let calls = await fixture.refreshCalls.count
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try fixture.vault.load(fingerprint: fixture.account.fingerprint), fixture.saved)
    }

    func testSuccessfulRenewalReleasesReservationAfterSavingRotatedCredential() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let reservation = RenewalReservation()
        var worker = fixture.worker { snapshot, account in
            if snapshot == fixture.saved { throw ChatGPTQuotaClient.QueryError.expiredLogin }
            let isHeld = await reservation.isHeld
            XCTAssertFalse(isHeld)
            XCTAssertEqual(try fixture.vault.load(fingerprint: fixture.account.fingerprint), fixture.renewed)
            return .unknown(accountId: account.id.uuidString, alias: account.alias)
        }
        worker.beginCredentialRefresh = { _ in await reservation.acquire() }
        worker.endCredentialRefresh = { _ in await reservation.release() }

        _ = try await worker.query(for: fixture.account)

        let releaseCount = await reservation.releaseCount
        XCTAssertEqual(releaseCount, 1)
    }

    func testFailedRenewalReleasesReservationSoSwitchingIsNotLeftLocked() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let reservation = RenewalReservation()
        let worker = ChatGPTQuotaWorker(
            paths: fixture.paths, vault: fixture.vault,
            credentialRefresher: FailingQuotaTestRefresher(),
            queryQuota: { _, _ in throw ChatGPTQuotaClient.QueryError.expiredLogin },
            beginCredentialRefresh: { _ in await reservation.acquire() },
            endCredentialRefresh: { _ in await reservation.release() }
        )

        do {
            _ = try await worker.query(for: fixture.account)
            XCTFail("Expected the renewal request to fail")
        } catch {
            XCTAssertEqual(error as? ChatGPTCredentialRefresher.RefreshError, .missingRefreshToken)
        }

        let isHeld = await reservation.isHeld
        let releaseCount = await reservation.releaseCount
        XCTAssertFalse(isHeld)
        XCTAssertEqual(releaseCount, 1)
    }

    private func expectExpired(_ body: () async throws -> AccountQuotaState) async {
        do {
            _ = try await body()
            XCTFail("Active account refresh must remain owned by Codex")
        } catch ChatGPTQuotaClient.QueryError.expiredLogin {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func expectActiveRefreshPending(_ body: () async throws -> AccountQuotaState) async {
        do {
            _ = try await body()
            XCTFail("Active account refresh must remain owned by Codex")
        } catch ChatGPTQuotaClient.QueryError.activeLoginRefreshPending {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct Fixture: @unchecked Sendable {
    let paths: CodixxPaths
    let account: CodixxAccount
    let saved: AuthSnapshot
    let renewed: AuthSnapshot
    let vault: QuotaTestVault
    let refreshCalls = RefreshCalls()

    init() throws {
        paths = CodixxPaths(home: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        saved = try AuthSnapshot(jsonData: Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"test-pro","access_token":"old-access","refresh_token":"old-refresh"}}"#.utf8))
        renewed = try saved.replacingChatGPTTokens(
            idToken: "new-id", accessToken: "new-access", refreshToken: "new-refresh", refreshedAt: Date()
        )
        let id = UUID()
        account = CodixxAccount(
            id: id, alias: "Pro", fingerprint: try AccountFingerprint.generate(from: saved),
            createdAt: Date(), updatedAt: Date(), lastUsedAt: nil,
            quota: .unknown(accountId: id.uuidString, alias: "Pro"), isEnabled: true, priority: 1
        )
        vault = QuotaTestVault(snapshot: saved)
    }

    func worker(query: @escaping @Sendable (AuthSnapshot, CodixxAccount) async throws -> AccountQuotaState) -> ChatGPTQuotaWorker {
        ChatGPTQuotaWorker(
            paths: paths, vault: vault,
            credentialRefresher: QuotaTestRefresher(result: renewed, calls: refreshCalls), queryQuota: query
        )
    }

    func remove() { try? FileManager.default.removeItem(at: paths.home) }
}

private final class QuotaTestVault: AuthSnapshotVault, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: AuthSnapshot
    init(snapshot: AuthSnapshot) { self.snapshot = snapshot }
    func save(snapshot: AuthSnapshot, fingerprint: String) throws {
        lock.lock(); defer { lock.unlock() }
        self.snapshot = snapshot
    }
    func load(fingerprint: String) throws -> AuthSnapshot {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }
    func delete(fingerprint: String) throws {}
}

private actor RefreshCalls {
    private(set) var count = 0
    func record() { count += 1 }
}

private struct QuotaTestRefresher: ChatGPTCredentialRefreshing {
    let result: AuthSnapshot
    let calls: RefreshCalls
    func refresh(snapshot: AuthSnapshot) async throws -> AuthSnapshot {
        await calls.record()
        return result
    }
}

private struct FailingQuotaTestRefresher: ChatGPTCredentialRefreshing {
    func refresh(snapshot: AuthSnapshot) async throws -> AuthSnapshot {
        throw ChatGPTCredentialRefresher.RefreshError.missingRefreshToken
    }
}

private actor RenewalReservation {
    private(set) var isHeld = false
    private(set) var releaseCount = 0
    func acquire() -> Bool { isHeld = true; return true }
    func release() { isHeld = false; releaseCount += 1 }
}
