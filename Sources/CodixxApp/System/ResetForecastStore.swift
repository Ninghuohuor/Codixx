import Foundation
import CodixxCore
import UserNotifications

@MainActor
final class ResetForecastStore: ObservableObject {
    struct Preferences: Codable {
        var automatic = false
        var cards = false
        var subscribedAt: Date?
        var seen: Set<String> = []
    }
    @Published private(set) var feed: ResetFeed?
    @Published private(set) var isRefreshing = false
    @Published private(set) var error: String?
    @Published private(set) var notificationError: String?
    @Published private(set) var preferences: Preferences
    private let cache: JSONFileStore<ResetFeed>
    private let settings: JSONFileStore<Preferences>
    private var timer: Timer?
    private var lastAttempt: Date?
    private var pendingNotifications: Set<String> = []
    static let feedURL = URL(string: "https://codexreset.club/api/feed")!

    init(directory: URL) {
        cache = JSONFileStore(url: directory.appendingPathComponent("reset-forecast.json"))
        settings = JSONFileStore(url: directory.appendingPathComponent("reset-forecast-preferences.json"))
        feed = try? cache.load()
        preferences = (try? settings.load()) ?? Preferences()
    }

    func startMonitoring() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 300 { return }
        lastAttempt = Date()
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            do {
                var request = URLRequest(url: Self.feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 8_000_000 else { throw CocoaError(.fileReadCorruptFile) }
                let latest = try ResetFeed.decode(data)
                try cache.save(latest)
                feed = latest
                error = nil
                await notifyChanges(latest)
            } catch {
                self.error = "暂时无法更新，保留上次获取的数据。"
            }
        }
    }

    func setReminder(automatic: Bool? = nil, cards: Bool? = nil) {
        let wasEnabled = preferences.automatic || preferences.cards
        if let automatic { preferences.automatic = automatic }
        if let cards { preferences.cards = cards }
        if !wasEnabled && (preferences.automatic || preferences.cards) { preferences.subscribedAt = Date() }
        // Enabling a category never replays already visible announcements.
        if let feed { preferences.seen.formUnion(notificationItems(feed).map(\.id)) }
        persist()
        guard preferences.automatic || preferences.cards else { return }
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                notificationError = granted ? nil : "请在 macOS 系统设置 → 通知中允许 Codixx 通知。"
            } catch { notificationError = "无法开启系统通知，请检查 macOS 通知设置。" }
        }
        refresh()
    }

    struct Notice {
        var id: String
        var title: String
        var body: String
        var date: Date
    }
    private func notificationItems(_ feed: ResetFeed) -> [Notice] {
        var notices: [Notice] = []
        for event in feed.announcements where event.isUsable && event.notificationEligible != false && event.announcedAt <= Date() {
            for effect in event.effects {
                guard (effect.kind == "automatic_reset" && preferences.automatic) || (effect.kind == "banked_reset" && preferences.cards) else { continue }
                let type = effect.kind == "automatic_reset" ? "自动重置" : "重置卡"
                notices.append(Notice(id: "\(event.id):\(effect.kind):\(effect.phase)", title: "Codex \(type)有新公告", body: event.summaryZh ?? event.originalText ?? "打开 Codixx 重置预测查看详情。", date: event.announcedAt))
            }
        }
        if preferences.cards, let outlook = ResetCardOutlook.calculate(feed: feed, now: Date()) {
            let date = (feed.replyLeads ?? []).first { $0.id == outlook.id }?.publishedAt ?? feed.announcements.first { $0.id == outlook.id }?.announcedAt ?? .distantPast
            notices.append(Notice(id: "outlook:\(outlook.id)", title: "Codex 重置卡有新线索（未确认）", body: outlook.text, date: date))
        }
        return notices
    }

    func newNotices(_ feed: ResetFeed, now: Date = Date()) -> [Notice] {
        guard feed.isFresh(at: now), preferences.automatic || preferences.cards,
              let subscribedAt = preferences.subscribedAt else { return [] }
        return notificationItems(feed).filter {
            $0.date > subscribedAt && !preferences.seen.contains($0.id) && !pendingNotifications.contains($0.id)
        }
    }

    private func notifyChanges(_ feed: ResetFeed) async {
        guard feed.isFresh(at: Date()), preferences.automatic || preferences.cards else { return }
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings()
        guard authorization.authorizationStatus == .authorized || authorization.authorizationStatus == .provisional else { return }
        for notice in newNotices(feed) {
            pendingNotifications.insert(notice.id)
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = String(notice.body.prefix(600))
            content.sound = .default
            do {
                try await center.add(UNNotificationRequest(identifier: "reset-\(notice.id)", content: content, trigger: nil))
                preferences.seen.insert(notice.id)
                persist()
            } catch { notificationError = "重置提醒发送失败，请检查系统通知设置。" }
            pendingNotifications.remove(notice.id)
        }
    }
    private func persist() {
        do { try settings.save(preferences) }
        catch { notificationError = "提醒设置未能保存，请重试。" }
    }
}
