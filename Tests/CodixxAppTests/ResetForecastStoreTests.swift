import XCTest
import CodixxCore
@testable import CodixxApp

final class ResetForecastStoreTests: XCTestCase {
    @MainActor
    func testRemindersFilterOldSeenRetractedAndStaleEventsAcrossRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let settings = ResetForecastStore.Preferences(automatic: true, cards: false, subscribedAt: now.addingTimeInterval(-60), seen: ["seen:automatic_reset:completed"])
        try JSONFileStore<ResetForecastStore.Preferences>(url: directory.appendingPathComponent("reset-forecast-preferences.json")).save(settings)
        let store = ResetForecastStore(directory: directory)
        let raw = #"{"schemaVersion":1,"syncIssue":"none","announcements":[{"id":"new","originalUrl":"https://x.com/thsottiaux/status/1","announcedAt":"2026-09-20T14:00:00Z","effects":[{"kind":"automatic_reset","phase":"completed"}],"retracted":false}]}"#
        var feed = try ResetFeed.decode(Data(raw.utf8))
        feed.lastSuccessAt = now
        feed.announcements[0].announcedAt = now.addingTimeInterval(-10)
        let fresh = feed.announcements[0]
        var seen = fresh; seen.id = "seen"
        var old = fresh; old.id = "old"; old.announcedAt = now.addingTimeInterval(-120)
        var withdrawn = fresh; withdrawn.id = "withdrawn"; withdrawn.retracted = true
        var ineligible = fresh; ineligible.id = "ineligible"; ineligible.notificationEligible = false
        feed.announcements = [fresh, seen, old, withdrawn, ineligible]
        XCTAssertEqual(store.newNotices(feed, now: now).map(\.id), ["new:automatic_reset:completed"])
        XCTAssertEqual(ResetForecastStore(directory: directory).newNotices(feed, now: now).count, 1)
        feed.lastSuccessAt = now.addingTimeInterval(-3600)
        XCTAssertTrue(store.newNotices(feed, now: now).isEmpty)
        XCTAssertTrue(ResetForecastStore(directory: directory.appendingPathComponent("new-user")).newNotices(feed, now: now).isEmpty)
    }
}
