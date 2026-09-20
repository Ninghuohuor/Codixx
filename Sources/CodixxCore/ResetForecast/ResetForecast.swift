import Foundation

public struct ResetFeed: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var lastSuccessAt: Date?
    public var syncIssue: String
    public var announcements: [ResetAnnouncement]
    public var replyLeads: [ResetReply]?

    public static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: raw) else { throw CocoaError(.coderReadCorrupt) }
            return date
        }
        let feed = try decoder.decode(Self.self, from: data)
        guard feed.schemaVersion == 1, feed.announcements.count <= 5000 else { throw CocoaError(.coderReadCorrupt) }
        return feed
    }

    public func isFresh(at now: Date) -> Bool {
        guard syncIssue == "none", let lastSuccessAt else { return false }
        return now.timeIntervalSince(lastSuccessAt) >= -60 && now.timeIntervalSince(lastSuccessAt) < 900
    }

    public func latest(_ kind: String, now: Date) -> ResetAnnouncement? {
        announcements.filter { $0.isUsable && $0.announcedAt <= now && $0.effects.contains { $0.kind == kind } }
            .max { $0.announcedAt < $1.announcedAt }
    }
}

public struct ResetAnnouncement: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var originalUrl: String
    public var announcedAt: Date
    public var originalText: String?
    public var summaryZh: String?
    public var effects: [Effect]
    public var retracted: Bool
    public var sourceChanged: Bool?
    public var notificationEligible: Bool?
    public var xReplyTo: String?
    public struct Effect: Codable, Equatable, Sendable {
        public var kind: String
        public var phase: String
        public var effectiveAt: Date?
        public var expiresAt: Date?
        public var audienceText: String?
    }
    public var isUsable: Bool { !retracted && sourceChanged != true }
    public var safeURL: URL? { Self.safeURL(originalUrl) }
    public static func safeURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

public struct ResetReply: Codable, Equatable, Sendable {
    public var id: String
    public var url: String
    public var publishedAt: Date
    public var text: String
    public var parent: Parent?
    public struct Parent: Codable, Equatable, Sendable {
        public var text: String
    }
}

/// Ported from codexreset/lib/reset-estimate.ts. Forecasts public announcements,
/// never the logged-in account's quota reset. All day buckets use Beijing time.
public struct ResetEstimate: Equatable, Sendable {
    public var day: Date
    public var probability: Double
    public var basis: String
    public var averageDays: Double?
    public var sampleCount: Int
    public var latestAt: Date?
    private static let daySeconds = 86400.0
    private static func dayStart(_ time: TimeInterval) -> TimeInterval {
        floor((time + 28800) / daySeconds) * daySeconds - 28800
    }

    public static func calculate(feed: ResetFeed, now: Date) -> Self {
        var urls = Set<String>()
        let times = feed.announcements.filter { event in
            guard event.isUsable, event.announcedAt <= now,
                  event.effects.contains(where: { $0.kind == "automatic_reset" }) else { return false }
            let key = event.originalUrl.components(separatedBy: CharacterSet(charactersIn: "?#"))[0].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return urls.insert(key).inserted
        }.map { $0.announcedAt.timeIntervalSince1970 }
        let unique = Set(times).sorted()
        let gaps = zip(unique.dropFirst(), unique).map(-).filter { $0 > 0 }.sorted()
        let average = gaps.isEmpty ? nil : gaps.reduce(0, +) / Double(gaps.count)
        let latest = unique.last
        let current = now.timeIntervalSince1970
        if let latest, gaps.count >= 12 {
            var threshold = 0.0
            for _ in 0...gaps.count {
                let candidates = gaps.filter { $0 > threshold }
                if candidates.count < 12 { break }
                let days = Dictionary(grouping: candidates, by: { dayStart(latest + $0) })
                let start = days.keys.sorted { a, b in
                    let ac = days[a]!.count, bc = days[b]!.count
                    return ac == bc ? a < b : ac > bc
                }[0]
                let deadline = start + daySeconds - 0.001
                if current > deadline { threshold = deadline - latest; continue }
                let remaining = gaps.filter { $0 > max(0, current - latest) }
                if remaining.count < 12 { break }
                let hits = remaining.filter { latest + $0 >= start && latest + $0 <= deadline }.count
                return Self(day: Date(timeIntervalSince1970: start), probability: Double(hits) / Double(remaining.count), basis: "empirical", averageDays: average.map { $0 / daySeconds }, sampleCount: gaps.count, latestAt: Date(timeIntervalSince1970: latest))
            }
        }
        let interval = max(daySeconds, average ?? 7 * daySeconds)
        let today = dayStart(current)
        func probability(_ start: Double) -> Double {
            exp(-max(0, start - current) / interval) * -expm1(-(start + daySeconds - max(start, current)) / interval)
        }
        let start = probability(today) >= probability(today + daySeconds) ? today : today + daySeconds
        return Self(day: Date(timeIntervalSince1970: start), probability: probability(start), basis: gaps.isEmpty ? "default" : "average", averageDays: average.map { $0 / daySeconds }, sampleCount: gaps.count, latestAt: latest.map { Date(timeIntervalSince1970: $0) })
    }
}

public struct ResetCardOutlook: Equatable, Sendable {
    public var id: String
    public var date: Date
    public var sourceURL: URL
    public var text: String
    public var explicitTime: Bool

    public static func calculate(feed: ResetFeed, now: Date) -> Self? {
        let completed = feed.announcements.filter { $0.isUsable && $0.effects.contains { $0.kind == "banked_reset" && ["completed", "rolling_out"].contains($0.phase) } }.map(\.announcedAt).max() ?? .distantPast
        var candidates = (feed.replyLeads ?? []).map { ($0.id, $0.url, $0.publishedAt, $0.text, $0.parent?.text ?? $0.text, Optional<Date>.none, true) }
        for event in feed.announcements where event.isUsable {
            if let effect = event.effects.first(where: { $0.kind == "banked_reset" && $0.phase == "announced" }) {
                candidates.append((event.id, event.originalUrl, event.announcedAt, event.originalText ?? "", event.originalText ?? "", effect.effectiveAt, event.xReplyTo != nil))
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (id, url, published, text, parent, effective, reply) in candidates.sorted(by: { $0.2 > $1.2 }) {
            guard published <= now, published > completed, now.timeIntervalSince(published) <= 14 * 86400,
                  url.range(of: #"^https://(?:x\.com|twitter\.com)/thsottiaux/status/\d+/?$"#, options: .regularExpression) != nil,
                  let sourceURL = ResetAnnouncement.safeURL(url) else { continue }
            if reply && parent.range(of: #"\bbanked\s+resets?\b|\breset\s+cards?\b"#, options: [.regularExpression, .caseInsensitive]) == nil { continue }
            if let effective {
                if effective > now { return Self(id: id, date: effective, sourceURL: sourceURL, text: text, explicitTime: true) }
                continue
            }
            let lower = text.lowercased()
            guard !lower.contains("?"), lower.range(of: #"\b(?:not|never|won't|isn't)\b"#, options: .regularExpression) == nil,
                  let range = lower.range(of: #"\b(?:coming|lands?|landing|arriv\w*|on|by)\s+(?:(?:in|on|this|next)\s+)*(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#, options: .regularExpression) else { continue }
            let phrase = String(lower[range])
            guard let weekday = weekdays.firstIndex(where: { phrase.hasSuffix($0) }) else { continue }
            var delta = (weekday + 1 - calendar.component(.weekday, from: published) + 7) % 7
            if delta == 0 && phrase.contains("next") { delta = 7 }
            let day = calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: published))!
            guard calendar.startOfDay(for: now) <= day else { continue }
            return Self(id: id, date: day, sourceURL: sourceURL, text: text, explicitTime: false)
        }
        return nil
    }
}
