import Foundation

/// Public, unclassified reset clues are kept separate from confirmed reset events.
public struct ResetClue: Codable, Equatable, Sendable {
    public var id: String
    public var url: String
    public var publishedAt: Date
    public var text: String
    public var progress: Progress?

    public struct Progress: Codable, Equatable, Sendable {
        public var rootId: String
        public var phase: String
        public var summaryZh: String
    }
}

public struct ResetUpdate: Equatable, Identifiable, Sendable {
    public enum Kind: Int, Sendable {
        case progress, clue, announcement, preannouncement
    }

    public let id: String
    public let kind: Kind
    public let publishedAt: Date
    public let sourceURL: URL
    public let summary: String
    public let originalText: String?
    public let progressPhase: String?
    public let effects: [ResetAnnouncement.Effect]

    /// Matches the website's Tibo progress/latest-announcement selection. Progress
    /// is visible for 48 hours and never becomes a confirmed automatic reset.
    public static func calculate(feed: ResetFeed, now: Date) -> [Self] {
        let signals = (feed.resetClues ?? []).filter {
            $0.publishedAt <= now && now.timeIntervalSince($0.publishedAt) < 48 * 3600
                && officialPost($0.url)?.id == $0.id
        }.sorted { $0.publishedAt > $1.publishedAt }
        var updates: [Self] = []
        var roots: Set<String> = []
        for signal in signals {
            guard let progress = signal.progress,
                  ["announced", "rolling_out", "completed"].contains(progress.phase),
                  roots.insert(progress.rootId).inserted,
                  let post = officialPost(signal.url) else { continue }
            updates.append(Self(id: post.id, kind: .progress, publishedAt: signal.publishedAt,
                sourceURL: post.url, summary: progress.summaryZh, originalText: signal.text,
                progressPhase: progress.phase, effects: []))
        }

        let known = feed.announcements.filter { $0.isUsable && $0.sourceType != "observed" && $0.announcedAt <= now }
        let teaser = signals.first { signal in
            guard signal.progress == nil || signal.progress?.phase == "announced" else { return false }
            if signals.contains(where: { other in
                other.progress != nil && other.publishedAt > signal.publishedAt
                    && (other.progress?.rootId == signal.id || other.progress?.rootId == signal.progress?.rootId)
            }) { return false }
            return !known.contains { event in
                event.effects.contains { effect in
                    effect.phase != "unknown" && (event.announcedAt >= signal.publishedAt
                        || (occurredAt(event, effect: effect, now: now) ?? .distantPast) >= signal.publishedAt)
                }
            }
        }
        if let teaser, !roots.contains(teaser.progress?.rootId ?? teaser.id), let post = officialPost(teaser.url) {
            updates.append(Self(id: post.id, kind: .clue, publishedAt: teaser.publishedAt,
                sourceURL: post.url, summary: "Tibo 提到可能重置", originalText: teaser.text,
                progressPhase: nil, effects: []))
        }

        let official = known.filter { officialPost($0.originalUrl) != nil }.sorted { $0.announcedAt > $1.announcedAt }
        if let latest = official.first { updates.append(announcement(latest, kind: .announcement)) }
        let completed = feed.announcements.filter { event in
            event.isUsable && event.announcedAt <= now && event.effects.contains {
                $0.kind == "automatic_reset" && occurredAt(event, effect: $0, now: now) != nil
            }
        }.map(\.announcedAt).max() ?? .distantPast
        if let pending = official.first(where: { event in
            event.announcedAt > completed && event.effects.contains { $0.kind == "automatic_reset" && $0.phase == "announced" }
        }), officialPost(pending.originalUrl)?.id != official.first.flatMap({ officialPost($0.originalUrl)?.id }) {
            updates.append(announcement(pending, kind: .preannouncement))
        }

        var seen: Set<String> = []
        return updates.sorted {
            $0.publishedAt == $1.publishedAt ? $0.kind.rawValue < $1.kind.rawValue : $0.publishedAt > $1.publishedAt
        }.filter { seen.insert($0.id).inserted }
    }

    private static func announcement(_ event: ResetAnnouncement, kind: Kind) -> Self {
        let post = officialPost(event.originalUrl)!
        return Self(id: post.id, kind: kind, publishedAt: event.announcedAt, sourceURL: post.url,
            summary: event.summaryZh.flatMap { $0.isEmpty ? nil : $0 } ?? "中文摘要待补充",
            originalText: nil, progressPhase: nil, effects: event.effects)
    }

    private static func occurredAt(_ event: ResetAnnouncement, effect: ResetAnnouncement.Effect, now: Date) -> Date? {
        guard ["rolling_out", "completed"].contains(effect.phase) else { return nil }
        let date = effect.effectiveAt ?? event.announcedAt
        return date <= now ? date : nil
    }

    private static func officialPost(_ value: String) -> (id: String, url: URL)? {
        guard value.range(of: #"^https://(?:x\.com|twitter\.com)/thsottiaux/status/[0-9]+/?$"#,
                          options: .caseInsensitive.union(.regularExpression)) != nil,
              let url = ResetAnnouncement.safeURL(value), let id = url.path.split(separator: "/").last else { return nil }
        return (String(id), url)
    }
}
