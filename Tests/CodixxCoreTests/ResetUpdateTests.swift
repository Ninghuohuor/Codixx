import XCTest
@testable import CodixxCore

final class ResetUpdateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_060_000)

    func testProgressDecodesAlongsideLegacyFeedAndObservedSourceType() throws {
        let payload = Data(#"{"schemaVersion":1,"syncIssue":"none","announcements":[{"id":"example","originalUrl":"https://x.com/thsottiaux/status/1","announcedAt":"2026-10-15T05:00:00Z","effects":[],"retracted":false,"sourceType":"observed"}],"resetClues":[{"id":"12","url":"https://x.com/thsottiaux/status/12","publishedAt":"2026-10-15T06:00:00Z","text":"Example completion","progress":{"rootId":"11","phase":"completed","summaryZh":"重置已完成，形式尚未明确。"}}]}"#.utf8)
        let decoded = try ResetFeed.decode(payload)
        XCTAssertEqual(decoded.resetClues?.first?.progress?.phase, "completed")
        XCTAssertEqual(decoded.announcements.first?.sourceType, "observed")
        XCTAssertEqual(try JSONDecoder().decode(ResetFeed.self, from: JSONEncoder().encode(decoded)), decoded)
        XCTAssertNil(try ResetFeed.decode(Data(#"{"schemaVersion":1,"syncIssue":"none","announcements":[]}"#.utf8)).resetClues)
    }

    func testCompletedProgressReplacesItsEarlierHintWithoutChangingResetHistoryOrForecast() {
        let hint = clue(11, age: 7200)
        let done = clue(12, age: 3600, root: "11", phase: "completed")
        var snapshot = feed([event(1, age: 3 * 86400)], clues: [hint, done])
        snapshot.forecast = ResetEstimate(day: now, probability: 0.5, basis: "average", averageDays: 7,
            sampleCount: 10, computedAt: now, zone: "Asia/Shanghai")
        let original = snapshot
        let updates = ResetUpdate.calculate(feed: snapshot, now: now)
        XCTAssertEqual(updates.map(\.id), ["12", "1"])
        XCTAssertEqual(updates.map(\.kind), [.progress, .announcement])
        XCTAssertEqual(updates.first?.progressPhase, "completed")
        XCTAssertEqual(updates.first?.originalText, done.text)
        XCTAssertEqual(snapshot, original)
        XCTAssertEqual(snapshot.latest("automatic_reset", now: now)?.id, "event-1")
    }

    func testProgressUsesOnlyTheNewestUpdatePerRoot() {
        let updates = ResetUpdate.calculate(feed: feed([], clues: [
            clue(11, age: 5000, root: "10", phase: "announced"),
            clue(12, age: 4000, root: "10", phase: "rolling_out"),
            clue(13, age: 3000, root: "10", phase: "completed"),
            clue(21, age: 2000, root: "20", phase: "announced")
        ]), now: now)
        XCTAssertEqual(updates.map(\.id), ["21", "13"])
        XCTAssertEqual(updates.map(\.progressPhase), ["announced", "completed"])
    }

    func testCluesExpireAt48HoursAndExcludeFutureOrUntrustedSources() {
        var otherAuthor = clue(13, age: 1)
        otherAuthor.url = "https://x.com/example/status/13"
        var mismatched = clue(14, age: 1)
        mismatched.url = "https://x.com/thsottiaux/status/15"
        let clues = [clue(11, age: 48 * 3600, root: "10", phase: "completed"),
            clue(12, age: -1, root: "10", phase: "completed"), otherAuthor, mismatched]
        XCTAssertTrue(ResetUpdate.calculate(feed: feed([], clues: clues), now: now).isEmpty)
        XCTAssertEqual(ResetUpdate.calculate(feed: feed([], clues: [clue(16, age: 48 * 3600 - 1)]), now: now).first?.kind, .clue)
    }

    func testLatestAnnouncementExcludesWithdrawnChangedObservedFutureAndOtherAuthors() {
        var withdrawn = event(2, age: 4); withdrawn.retracted = true
        var changed = event(3, age: 3); changed.sourceChanged = true
        var observed = event(4, age: 2); observed.sourceType = "observed"
        var otherAuthor = event(5, age: 1); otherAuthor.originalUrl = "https://x.com/example/status/5"
        var unsafe = event(6, age: 1)
        var credentialURL = URLComponents(string: "https://x.com/thsottiaux/status/6")!
        credentialURL.user = "example-user"
        credentialURL.password = "example-password"
        unsafe.originalUrl = credentialURL.url!.absoluteString
        let snapshot = feed([event(1, age: 100), withdrawn, changed, observed, otherAuthor, unsafe, event(7, age: -1)])
        XCTAssertEqual(ResetUpdate.calculate(feed: snapshot, now: now).map(\.id), ["1"])
    }

    func testConfirmedAnnouncementResolvesTeaserButRetractedAnnouncementDoesNot() {
        let hint = clue(11, age: 7200)
        var confirmed = event(1, age: 3600)
        XCTAssertEqual(ResetUpdate.calculate(feed: feed([confirmed], clues: [hint]), now: now).map(\.kind), [.announcement])
        confirmed.retracted = true
        XCTAssertEqual(ResetUpdate.calculate(feed: feed([confirmed], clues: [hint]), now: now).map(\.kind), [.clue])
        var earlierPost = event(2, age: 10000)
        earlierPost.effects[0].effectiveAt = now.addingTimeInterval(-1800)
        XCTAssertEqual(ResetUpdate.calculate(feed: feed([earlierPost], clues: [hint]), now: now).map(\.kind), [.announcement])
    }

    func testActivePreannouncementSurvivesNewerCardPostUntilAutomaticResetCompletes() {
        let announced = event(1, age: 7200, phase: "announced")
        var card = event(2, age: 3600)
        card.effects[0].kind = "banked_reset"
        let pending = ResetUpdate.calculate(feed: feed([announced, card]), now: now)
        XCTAssertEqual(pending.map(\.id), ["2", "1"])
        XCTAssertEqual(pending.map(\.kind), [.announcement, .preannouncement])
        let complete = ResetUpdate.calculate(feed: feed([announced, card, event(3, age: 1800)]), now: now)
        XCTAssertEqual(complete.map(\.id), ["3"])
    }

    func testSamePostIsShownOnceAcrossProgressAndAnnouncementAndURLAliases() {
        let progress = clue(11, age: 100, root: "10", phase: "completed")
        var announcement = event(11, age: 100)
        announcement.originalUrl = "https://twitter.com/thsottiaux/status/11/"
        let updates = ResetUpdate.calculate(feed: feed([announcement], clues: [progress]), now: now)
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.kind, .progress)
    }

    private func clue(_ id: Int, age: TimeInterval, root: String? = nil, phase: String = "announced") -> ResetClue {
        ResetClue(id: "\(id)", url: "https://x.com/thsottiaux/status/\(id)", publishedAt: now.addingTimeInterval(-age),
            text: "Example reset message", progress: root.map { .init(rootId: $0, phase: phase, summaryZh: "示例重置进展") })
    }

    private func event(_ id: Int, age: TimeInterval, phase: String = "completed") -> ResetAnnouncement {
        ResetAnnouncement(id: "event-\(id)", originalUrl: "https://x.com/thsottiaux/status/\(id)",
            announcedAt: now.addingTimeInterval(-age), summaryZh: "示例公告",
            effects: [.init(kind: "automatic_reset", phase: phase)], retracted: false)
    }

    private func feed(_ events: [ResetAnnouncement], clues: [ResetClue]? = nil) -> ResetFeed {
        ResetFeed(schemaVersion: 1, lastSuccessAt: now, syncIssue: "none", announcements: events, resetClues: clues)
    }
}
