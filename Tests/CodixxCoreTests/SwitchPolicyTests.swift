import XCTest
@testable import CodixxCore

final class SwitchPolicyTests: XCTestCase {
    func testCandidateOrderingPrefersKnownThenPriorityThenQuotaThenLeastRecentlyUsed() {
        let now = Date(timeIntervalSince1970: 1_000)
        let unknown = account(
            alias: "Unknown",
            primary: nil,
            secondary: nil,
            confidence: .unknown,
            priority: 100,
            lastUsedAt: nil,
            now: now
        )
        let lowerPriority = account(
            alias: "Lower Priority",
            primary: 10,
            secondary: 10,
            confidence: .fresh,
            priority: 1,
            lastUsedAt: nil,
            now: now
        )
        let higherPriority = account(
            alias: "Higher Priority",
            primary: 80,
            secondary: 10,
            confidence: .fresh,
            priority: 10,
            lastUsedAt: now,
            now: now
        )
        let samePriorityLowerQuota = account(
            alias: "Same Priority Lower Quota",
            primary: 20,
            secondary: 10,
            confidence: .fresh,
            priority: 10,
            lastUsedAt: now,
            now: now
        )
        let samePriorityLessRecent = account(
            alias: "Same Priority Less Recent",
            primary: 20,
            secondary: 10,
            confidence: .fresh,
            priority: 10,
            lastUsedAt: nil,
            now: now
        )

        let ordered = SwitchPolicy().orderedCandidates(
            from: [unknown, lowerPriority, higherPriority, samePriorityLowerQuota, samePriorityLessRecent],
            snapshotExists: { _ in true }
        )

        XCTAssertEqual(ordered.map(\.alias), [
            "Same Priority Less Recent",
            "Same Priority Lower Quota",
            "Higher Priority",
            "Lower Priority",
            "Unknown"
        ])
    }

    func testShouldAutoSwitchOnlyWhenCurrentAccountIsFreshAndAtThreshold() {
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = SwitchPolicy(primaryThresholdPercent: 93)

        XCTAssertTrue(policy.shouldAutoSwitch(
            currentAccount: account(alias: "Main", primary: 93, confidence: .fresh, now: now),
            context: .idle(now: now)
        ))
        XCTAssertFalse(policy.shouldAutoSwitch(currentAccount: account(alias: "Main", primary: 92.9, confidence: .fresh, now: now)))
        XCTAssertFalse(policy.shouldAutoSwitch(currentAccount: account(alias: "Main", primary: 99, confidence: .stale, now: now)))
        XCTAssertFalse(policy.shouldAutoSwitch(currentAccount: nil))
    }

    func testAutoSwitchWaitsForActiveThreadToBecomeIdle() {
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = SwitchPolicy(primaryThresholdPercent: 93, activeThreadIdleSeconds: 120)
        let current = account(alias: "Main", primary: 93, confidence: .fresh, now: now)

        XCTAssertFalse(policy.shouldAutoSwitch(
            currentAccount: current,
            context: SwitchSafetyContext(
                now: now,
                activeThreadUpdatedAt: now.addingTimeInterval(-119),
                lastSwitchAt: nil
            )
        ))
        XCTAssertTrue(policy.shouldAutoSwitch(
            currentAccount: current,
            context: SwitchSafetyContext(
                now: now,
                activeThreadUpdatedAt: now.addingTimeInterval(-120),
                lastSwitchAt: nil
            )
        ))
    }

    func testAutoSwitchRespectsCooldownAfterLastSuccessfulSwitch() {
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = SwitchPolicy(primaryThresholdPercent: 93, autoSwitchCooldownSeconds: 300)
        let current = account(alias: "Main", primary: 93, confidence: .fresh, now: now)

        XCTAssertFalse(policy.shouldAutoSwitch(
            currentAccount: current,
            context: SwitchSafetyContext(
                now: now,
                activeThreadUpdatedAt: nil,
                lastSwitchAt: now.addingTimeInterval(-299)
            )
        ))
        XCTAssertTrue(policy.shouldAutoSwitch(
            currentAccount: current,
            context: SwitchSafetyContext(
                now: now,
                activeThreadUpdatedAt: nil,
                lastSwitchAt: now.addingTimeInterval(-300)
            )
        ))
    }

    func testCandidateEligibilityUsesConfiguredThreshold() {
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = SwitchPolicy(primaryThresholdPercent: 80)

        let ordered = policy.orderedCandidates(
            from: [
                account(alias: "At Threshold", primary: 80, confidence: .fresh, now: now),
                account(alias: "Under Threshold", primary: 79.9, confidence: .fresh, now: now)
            ],
            snapshotExists: { _ in true }
        )

        XCTAssertEqual(ordered.map(\.alias), ["Under Threshold"])
    }

    private func account(
        alias: String,
        primary: Double?,
        secondary: Double? = 10,
        confidence: QuotaConfidence,
        priority: Int = 0,
        lastUsedAt: Date? = nil,
        now: Date
    ) -> CodixxAccount {
        let id = UUID()
        return CodixxAccount(
            id: id,
            alias: alias,
            fingerprint: "fingerprint-\(alias)",
            createdAt: now,
            updatedAt: now,
            lastUsedAt: lastUsedAt,
            quota: AccountQuotaState(
                accountId: id.uuidString,
                alias: alias,
                primaryUsedPercent: primary,
                primaryWindowMinutes: primary == nil ? nil : 300,
                primaryResetsAt: nil,
                secondaryUsedPercent: secondary,
                secondaryWindowMinutes: secondary == nil ? nil : 10_080,
                secondaryResetsAt: nil,
                lastObservedAt: confidence == .unknown ? nil : now,
                confidence: confidence
            ),
            isEnabled: true,
            priority: priority
        )
    }
}
