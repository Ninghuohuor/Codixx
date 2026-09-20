import XCTest
@testable import CodixxApp

final class RuntimeAccountStateTests: XCTestCase {
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
