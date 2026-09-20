import XCTest
@testable import CodixxApp

final class RuntimeAccountStateTests: XCTestCase {
    func testChatGPTLoginBecomesCurrentWithoutRestartingCodex() throws {
        let apiAccount = UUID(), proAccount = UUID()
        let previous = RuntimeAccountState(processIdentity: "100", accountID: apiAccount)
        // Covers upgrading from the persisted state of the previous release.
        let restored = try JSONDecoder().decode(RuntimeAccountState.self, from: JSONEncoder().encode(previous))
        let loggedIn = RuntimeAccountState.resolve(previous: restored, processIdentity: "100", configuredAccountID: proAccount, isChatGPTLogin: true)
        XCTAssertEqual(loggedIn.accountID, proAccount)
        XCTAssertEqual(loggedIn.processIdentity, "100")
        let apiTarget = UUID()
        XCTAssertEqual(RuntimeAccountState.resolve(previous: loggedIn, processIdentity: "100", configuredAccountID: apiTarget).accountID, proAccount)
    }

    func testChatGPTLoginCanBeSavedAfterLoginWithoutRestart() {
        let previous = RuntimeAccountState(processIdentity: "100", accountID: UUID())
        let unregistered = RuntimeAccountState.resolve(previous: previous, processIdentity: "100", configuredAccountID: nil, isChatGPTLogin: true)
        XCTAssertNil(unregistered.accountID)
        let saved = UUID()
        XCTAssertEqual(RuntimeAccountState.resolve(previous: unregistered, processIdentity: "100", configuredAccountID: saved, isChatGPTLogin: true).accountID, saved)
    }

    func testChatGPTAccountCanChangeWithinSameProcess() {
        let previous = RuntimeAccountState(processIdentity: "100", accountID: UUID())
        let target = UUID()
        XCTAssertEqual(RuntimeAccountState.resolve(previous: previous, processIdentity: "100", configuredAccountID: target, isChatGPTLogin: true).accountID, target)
    }

    func testConfigWriteDoesNotChangeCurrentAccountUntilNewProcess() throws {
        let original = UUID(), target = UUID()
        let initial = RuntimeAccountState.resolve(previous: nil, processIdentity: "100:launchA", configuredAccountID: original)
        let pending = RuntimeAccountState.resolve(previous: initial, processIdentity: "100:launchA", configuredAccountID: target)
        XCTAssertEqual(pending.accountID, original)
        // Restarting Codixx reloads the record, not Codex's process.
        let restored = try JSONDecoder().decode(RuntimeAccountState.self, from: JSONEncoder().encode(pending))
        XCTAssertEqual(RuntimeAccountState.resolve(previous: restored, processIdentity: "100:launchA", configuredAccountID: target).accountID, original)
        XCTAssertEqual(RuntimeAccountState.resolve(previous: restored, processIdentity: "101:launchB", configuredAccountID: target).accountID, target)
    }

    func testStoppedCodexUsesConfiguredAccountAndUnknownRuntimeIsNotGuessed() {
        let target = UUID()
        let unknown = RuntimeAccountState(processIdentity: "100", accountID: nil)
        XCTAssertNil(RuntimeAccountState.resolve(previous: unknown, processIdentity: "100", configuredAccountID: target).accountID)
        XCTAssertEqual(RuntimeAccountState.resolve(previous: unknown, processIdentity: nil, configuredAccountID: target).accountID, target)
    }
}
