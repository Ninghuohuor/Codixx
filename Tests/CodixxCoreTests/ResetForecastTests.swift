import XCTest
@testable import CodixxCore

final class ResetForecastTests: XCTestCase {
    private func event(_ id: Int, time: Date, kind: String = "automatic_reset", phase: String = "completed") -> ResetAnnouncement {
        ResetAnnouncement(id: "event-\(id)", originalUrl: "https://x.com/thsottiaux/status/\(id)", announcedAt: time, effects: [.init(kind: kind, phase: phase)], retracted: false)
    }
    private func feed(_ events: [ResetAnnouncement]) -> ResetFeed {
        ResetFeed(schemaVersion: 1, lastSuccessAt: Date(), syncIssue: "none", announcements: events)
    }

    func testEmpiricalEstimateMatchesSevenDayHistory() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let events = (0...12).map { event($0, time: start.addingTimeInterval(Double($0) * 7 * 86400)) }
        let now = events.last!.announcedAt
        let estimate = ResetEstimate.calculate(feed: feed(events), now: now)
        XCTAssertEqual(estimate.basis, "empirical")
        XCTAssertEqual(estimate.sampleCount, 12)
        XCTAssertEqual(estimate.probability, 1)
        XCTAssertEqual(estimate.averageDays, 7)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        XCTAssertEqual(estimate.day, calendar.startOfDay(for: now.addingTimeInterval(7 * 86400)))
    }

    func testSparseAndExhaustedHistoriesUseDisclosedFallback() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let empty = ResetEstimate.calculate(feed: feed([]), now: now)
        XCTAssertEqual(empty.basis, "default")
        XCTAssertNil(empty.averageDays)
        XCTAssertGreaterThan(empty.probability, 0)
        XCTAssertLessThan(empty.probability, 1)
        let events = (0...12).map { event($0, time: now.addingTimeInterval(Double($0 - 20) * 86400)) }
        XCTAssertEqual(ResetEstimate.calculate(feed: feed(events), now: now).basis, "average")
    }

    func testHistoryExcludesFutureRetractedChangedAndDuplicateRecords() {
        let now = Date()
        let first = event(1, time: now.addingTimeInterval(-86400))
        var withdrawn = event(2, time: now); withdrawn.retracted = true
        var changed = event(3, time: now); changed.sourceChanged = true
        let result = ResetEstimate.calculate(feed: feed([first, first, withdrawn, changed, event(4, time: now.addingTimeInterval(86400))]), now: now)
        XCTAssertEqual(result.sampleCount, 0)
        XCTAssertEqual(result.latestAt!.timeIntervalSince1970, first.announcedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testCardReplyUsesPacificWeekdayAndExpires() throws {
        let formatter = ISO8601DateFormatter()
        let published = try XCTUnwrap(formatter.date(from: "2026-09-19T16:48:38Z"))
        var snapshot = feed([])
        snapshot.replyLeads = [ResetReply(id: "123", url: "https://x.com/thsottiaux/status/123", publishedAt: published, text: "OK fine. But it’s also still coming in Tuesday", parent: .init(text: "you owe us a banked reset"))]
        let result = try XCTUnwrap(ResetCardOutlook.calculate(feed: snapshot, now: published))
        XCTAssertEqual(result.date, formatter.date(from: "2026-09-22T07:00:00Z"))
        XCTAssertFalse(result.explicitTime)
        XCTAssertNil(ResetCardOutlook.calculate(feed: snapshot, now: published.addingTimeInterval(6 * 86400)))
        snapshot.announcements = [event(2, time: published.addingTimeInterval(1), kind: "banked_reset")]
        XCTAssertNil(ResetCardOutlook.calculate(feed: snapshot, now: published.addingTimeInterval(2)))
    }

    func testDecodeFeedRejectsUnknownSchemaAndUnsafeLinks() throws {
        let data = Data(#"{"schemaVersion":1,"lastSuccessAt":"2026-09-20T14:09:30.273Z","syncIssue":"none","announcements":[]}"#.utf8)
        XCTAssertEqual(try ResetFeed.decode(data).announcements.count, 0)
        XCTAssertThrowsError(try ResetFeed.decode(Data(#"{"schemaVersion":2,"syncIssue":"none","announcements":[]}"#.utf8)))
        XCTAssertNil(ResetAnnouncement.safeURL("javascript:alert(1)"))
        XCTAssertNil(ResetAnnouncement.safeURL("https://user:pass@example.com/"))
    }
}
