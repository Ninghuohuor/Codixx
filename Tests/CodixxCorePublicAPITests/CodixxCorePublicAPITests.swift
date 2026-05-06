import XCTest
import CodixxCore

final class CodixxCorePublicAPITests: XCTestCase {
    func testPublicClientsCanInitializeAccountModels() {
        let quota = AccountQuotaState(
            accountId: "11111111-1111-1111-1111-111111111111",
            alias: "Main",
            primaryUsedPercent: nil,
            primaryWindowMinutes: nil,
            primaryResetsAt: nil,
            secondaryUsedPercent: nil,
            secondaryWindowMinutes: nil,
            secondaryResetsAt: nil,
            lastObservedAt: nil,
            confidence: .unknown
        )

        let account = CodixxAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            alias: "Main",
            fingerprint: "abc123",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            lastUsedAt: nil,
            quota: quota,
            isEnabled: true,
            priority: 10
        )

        XCTAssertEqual(account.alias, "Main")
        XCTAssertEqual(account.quota.confidence, .unknown)
    }
}
