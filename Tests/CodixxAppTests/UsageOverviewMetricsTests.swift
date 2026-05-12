import XCTest
@testable import CodixxApp
import CodixxCore

final class UsageOverviewMetricsTests: XCTestCase {
    func testSelectedAccountWithoutSummaryDoesNotFallBackToAllAccounts() {
        let selectedAccountId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let snapshot = ThreadUsageSnapshot(
            threads: [
                ThreadUsage(
                    id: "global-thread",
                    title: "Global",
                    model: "gpt-5",
                    reasoningEffort: "medium",
                    tokensUsed: 12_345,
                    cwd: "",
                    createdAt: Date(timeIntervalSince1970: 1),
                    updatedAt: Date(timeIntervalSince1970: 2),
                    rolloutPath: "/tmp/global.jsonl"
                )
            ],
            totalTokens: 12_345,
            activeThread: nil,
            dailyTokenUsage: [
                TokenUsageBucket(start: Calendar.current.startOfDay(for: Date()), tokens: 500)
            ],
            monthlyTokenUsage: [
                TokenUsageBucket(start: Calendar.current.dateInterval(of: .month, for: Date())!.start, tokens: 6_000)
            ],
            accountUsageSummaries: []
        )

        let metrics = UsageOverviewMetrics(
            snapshot: snapshot,
            selectedAccountId: selectedAccountId,
            now: Date()
        )

        XCTAssertEqual(metrics.totalTokens, 0)
        XCTAssertEqual(metrics.threadCount, 0)
        XCTAssertEqual(metrics.todayTokens, 0)
        XCTAssertEqual(metrics.currentMonthTokens, 0)
    }

    func testAllAccountsUsesSnapshotTotals() {
        let snapshot = ThreadUsageSnapshot(
            threads: [
                ThreadUsage(
                    id: "global-thread",
                    title: "Global",
                    model: "gpt-5",
                    reasoningEffort: "medium",
                    tokensUsed: 12_345,
                    cwd: "",
                    createdAt: Date(timeIntervalSince1970: 1),
                    updatedAt: Date(timeIntervalSince1970: 2),
                    rolloutPath: "/tmp/global.jsonl"
                )
            ],
            totalTokens: 12_345,
            activeThread: nil,
            dailyTokenUsage: [
                TokenUsageBucket(start: Calendar.current.startOfDay(for: Date()), tokens: 500)
            ],
            monthlyTokenUsage: [
                TokenUsageBucket(start: Calendar.current.dateInterval(of: .month, for: Date())!.start, tokens: 6_000)
            ],
            accountUsageSummaries: []
        )

        let metrics = UsageOverviewMetrics(
            snapshot: snapshot,
            selectedAccountId: nil,
            now: Date()
        )

        XCTAssertEqual(metrics.totalTokens, 12_345)
        XCTAssertEqual(metrics.threadCount, 1)
        XCTAssertEqual(metrics.todayTokens, 500)
        XCTAssertEqual(metrics.currentMonthTokens, 6_000)
    }
}
