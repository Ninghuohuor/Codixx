import XCTest
@testable import CodixxCore

final class CodixxModelsTests: XCTestCase {
    func testQuotaConfidenceFromObservationAge() {
        let now = Date(timeIntervalSince1970: 1_800)
        XCTAssertEqual(QuotaConfidence.observed(at: now.addingTimeInterval(-60), now: now), .fresh)
        XCTAssertEqual(QuotaConfidence.observed(at: now.addingTimeInterval(-3_600), now: now), .recent)
        XCTAssertEqual(QuotaConfidence.observed(at: now.addingTimeInterval(-90_000), now: now), .stale)
    }

    func testAccountIsSwitchCandidateWhenEnabledAndSnapshotExists() {
        let account = CodixxAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            alias: "Work",
            fingerprint: "abc123",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            lastUsedAt: nil,
            quota: .unknown(accountId: "11111111-1111-1111-1111-111111111111", alias: "Work"),
            isEnabled: true,
            priority: 10
        )

        XCTAssertTrue(account.isEligibleForSwitch(hasSnapshot: true))
        XCTAssertFalse(account.isEligibleForSwitch(hasSnapshot: false))
    }
}
