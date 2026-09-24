import XCTest
@testable import CodixxCore

final class ResetForecastTests: XCTestCase {
    private func event(_ id: Int, time: Date, kind: String = "automatic_reset", phase: String = "completed") -> ResetAnnouncement {
        ResetAnnouncement(id: "event-\(id)", originalUrl: "https://x.com/thsottiaux/status/\(id)", announcedAt: time, effects: [.init(kind: kind, phase: phase)], retracted: false)
    }
    private func feed(_ events: [ResetAnnouncement]) -> ResetFeed {
        ResetFeed(schemaVersion: 1, lastSuccessAt: Date(), syncIssue: "none", announcements: events)
    }

    func testFeedUsesWebsiteForecastWithoutLocalRecalculation() throws {
        let payload = Data(#"{"schemaVersion":1,"lastSuccessAt":"2026-09-25T00:00:00Z","syncIssue":"none","announcements":[],"forecast":{"day":"2026-09-28T16:00:00Z","probability":0.513,"basis":"average","averageDays":7.7,"sampleCount":47,"latestAt":"2026-09-12T08:09:00Z","computedAt":"2026-09-24T00:00:00Z","zone":"Asia/Shanghai"}}"#.utf8)
        let decoded = try ResetFeed.decode(payload)
        let estimate = try XCTUnwrap(decoded.forecast)
        XCTAssertEqual(estimate.sampleCount, 47)
        XCTAssertEqual(estimate.probability, 0.513)
        XCTAssertEqual(estimate.day, ISO8601DateFormatter().date(from: "2026-09-28T16:00:00Z"))
        XCTAssertEqual(try ResetFeed.decode(Data(#"{"schemaVersion":1,"syncIssue":"none","announcements":[]}"#.utf8)).forecast, nil)
    }

    func testRejectsInvalidWebsiteForecast() {
        let payload = Data(#"{"schemaVersion":1,"syncIssue":"none","announcements":[],"forecast":{"day":"2026-09-28T16:00:00Z","probability":1.5,"basis":"average","averageDays":7.7,"sampleCount":47,"latestAt":null,"computedAt":"2026-09-24T00:00:00Z","zone":"Asia/Shanghai"}}"#.utf8)
        XCTAssertThrowsError(try ResetFeed.decode(payload))
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
