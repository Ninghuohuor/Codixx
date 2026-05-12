import XCTest
@testable import CodixxApp
import CodixxCore

final class AccountSummaryMetricsTests: XCTestCase {
    func testSummaryCountsFullOnlyWhenQuotaReachesOneHundredPercent() {
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let available = account(
            alias: "Available",
            quota: quota(alias: "Available", primary: 95, secondary: 20, now: now),
            isEnabled: true,
            now: now
        )
        let full = account(
            alias: "Full",
            quota: quota(alias: "Full", primary: 100, secondary: 20, now: now),
            isEnabled: true,
            now: now
        )
        let unknown = account(
            alias: "Unknown",
            quota: .unknown(accountId: "Unknown", alias: "Unknown"),
            isEnabled: true,
            now: now
        )
        let disabled = account(
            alias: "Disabled",
            quota: quota(alias: "Disabled", primary: 100, secondary: 100, now: now),
            isEnabled: false,
            now: now
        )

        let summary = AccountSummaryMetrics(accounts: [available, full, unknown, disabled])

        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.available, 1)
        XCTAssertEqual(summary.full, 1)
        XCTAssertEqual(summary.unknown, 1)
        XCTAssertEqual(summary.disabled, 1)
    }

    func testSummaryTreatsAPIProviderBalanceAsAvailableFullOrUnknown() {
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let availableAPI = apiAccount(
            alias: "Relay",
            balanceQuery: APIBalanceQueryConfig(
                isEnabled: true,
                minimumBalance: 0,
                lastBalanceText: "10"
            ),
            now: now
        )
        let depletedAPI = apiAccount(
            alias: "Depleted Relay",
            balanceQuery: APIBalanceQueryConfig(
                isEnabled: true,
                minimumBalance: 0,
                lastBalanceText: "0"
            ),
            now: now
        )
        let insufficientBalanceAPI = apiAccount(
            alias: "Insufficient Relay",
            balanceQuery: APIBalanceQueryConfig(
                isEnabled: true,
                minimumBalance: 0,
                lastBalanceText: "insufficient balance"
            ),
            now: now
        )
        let unknownAPI = apiAccount(
            alias: "Unknown Relay",
            balanceQuery: APIBalanceQueryConfig(isEnabled: true, minimumBalance: 0),
            now: now
        )

        let summary = AccountSummaryMetrics(accounts: [availableAPI, depletedAPI, insufficientBalanceAPI, unknownAPI])

        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.available, 1)
        XCTAssertEqual(summary.full, 2)
        XCTAssertEqual(summary.unknown, 1)
        XCTAssertEqual(summary.disabled, 0)
    }

    private func account(
        alias: String,
        quota: AccountQuotaState,
        isEnabled: Bool,
        now: Date
    ) -> CodixxAccount {
        CodixxAccount(
            id: UUID(),
            alias: alias,
            fingerprint: "fingerprint-\(alias)",
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil,
            quota: quota,
            isEnabled: isEnabled,
            priority: 0
        )
    }

    private func apiAccount(
        alias: String,
        balanceQuery: APIBalanceQueryConfig?,
        now: Date
    ) -> CodixxAccount {
        CodixxAccount(
            id: UUID(),
            alias: alias,
            fingerprint: "api-\(alias)",
            credentialKind: .apiProvider,
            apiProvider: APIProviderAccount(
                providerName: alias,
                baseURL: URL(string: "https://api.example.com/v1")!,
                defaultModel: nil,
                keyFingerprint: "api-\(alias)",
                balanceQuery: balanceQuery
            ),
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil,
            quota: .unknown(accountId: alias, alias: alias),
            isEnabled: true,
            priority: 0
        )
    }

    private func quota(alias: String, primary: Double, secondary: Double, now: Date) -> AccountQuotaState {
        AccountQuotaState(
            accountId: alias,
            alias: alias,
            primaryUsedPercent: primary,
            primaryWindowMinutes: 300,
            primaryResetsAt: nil,
            secondaryUsedPercent: secondary,
            secondaryWindowMinutes: 10_080,
            secondaryResetsAt: nil,
            lastObservedAt: now,
            confidence: .fresh
        )
    }
}
