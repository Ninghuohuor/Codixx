import XCTest
@testable import CodixxCore

final class CodixxModelsTests: XCTestCase {
    func testQuotaConfidenceFromObservationAge() {
        let now = Date(timeIntervalSince1970: 1_800)
        XCTAssertEqual(QuotaConfidence.observed(at: now.addingTimeInterval(-60), now: now), .fresh)
        XCTAssertEqual(QuotaConfidence.observed(at: now.addingTimeInterval(-3_600), now: now), .recent)
        XCTAssertEqual(QuotaConfidence.observed(at: now.addingTimeInterval(-90_000), now: now), .stale)
        XCTAssertEqual(QuotaConfidence.observed(at: nil, now: now), .unknown)
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

    func testAccountSwitchEligibilityRespectsDisabledAndQuotaThresholds() {
        let account = CodixxAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            alias: "Work",
            fingerprint: "abc123",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            lastUsedAt: nil,
            quota: AccountQuotaState(
                accountId: "11111111-1111-1111-1111-111111111111",
                alias: "Work",
                primaryUsedPercent: 92.9,
                primaryWindowMinutes: 300,
                primaryResetsAt: nil,
                secondaryUsedPercent: 99.9,
                secondaryWindowMinutes: 10_080,
                secondaryResetsAt: nil,
                lastObservedAt: Date(timeIntervalSince1970: 1),
                confidence: .fresh
            ),
            isEnabled: true,
            priority: 10
        )

        XCTAssertTrue(account.isEligibleForSwitch(hasSnapshot: true))

        var disabled = account
        disabled.isEnabled = false
        XCTAssertFalse(disabled.isEligibleForSwitch(hasSnapshot: true))

        var primaryAtThreshold = account
        primaryAtThreshold.quota.primaryUsedPercent = 93
        XCTAssertFalse(primaryAtThreshold.isEligibleForSwitch(hasSnapshot: true))

        var secondaryFull = account
        secondaryFull.quota.secondaryUsedPercent = 100
        XCTAssertFalse(secondaryFull.isEligibleForSwitch(hasSnapshot: true))
    }

    func testQuotaStateRollsForwardExpiredWindows() {
        let now = Date(timeIntervalSince1970: 10_000)
        var quota = AccountQuotaState(
            accountId: "account-1",
            alias: "Work",
            primaryUsedPercent: 100,
            primaryWindowMinutes: 300,
            primaryResetsAt: now.addingTimeInterval(-60),
            secondaryUsedPercent: 31,
            secondaryWindowMinutes: 10_080,
            secondaryResetsAt: now.addingTimeInterval(600),
            lastObservedAt: now.addingTimeInterval(-3_600),
            confidence: .fresh
        )

        XCTAssertTrue(quota.rollForwardExpiredWindows(now: now))
        XCTAssertEqual(quota.primaryUsedPercent, 0)
        XCTAssertEqual(quota.primaryResetsAt, now.addingTimeInterval(-60 + 300 * 60))
        XCTAssertEqual(quota.secondaryUsedPercent, 31)
        XCTAssertEqual(quota.secondaryResetsAt, now.addingTimeInterval(600))
    }

    func testQuotaStateRollsForwardMultipleElapsedWindows() {
        let now = Date(timeIntervalSince1970: 100_000)
        var quota = AccountQuotaState(
            accountId: "account-1",
            alias: "Work",
            primaryUsedPercent: 90,
            primaryWindowMinutes: 300,
            primaryResetsAt: now.addingTimeInterval(-301 * 60),
            secondaryUsedPercent: 100,
            secondaryWindowMinutes: 10_080,
            secondaryResetsAt: now.addingTimeInterval(-10_081 * 60),
            lastObservedAt: now.addingTimeInterval(-90_000),
            confidence: .stale
        )

        XCTAssertTrue(quota.rollForwardExpiredWindows(now: now))
        XCTAssertEqual(quota.primaryUsedPercent, 0)
        XCTAssertGreaterThan(quota.primaryResetsAt ?? .distantPast, now)
        XCTAssertEqual(quota.secondaryUsedPercent, 0)
        XCTAssertGreaterThan(quota.secondaryResetsAt ?? .distantPast, now)
    }
}
