import Foundation

public struct ThreadUsage: Equatable, Sendable {
    public var id: String
    public var title: String
    public var model: String
    public var reasoningEffort: String
    public var tokensUsed: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var rolloutPath: String

    public init(
        id: String,
        title: String,
        model: String,
        reasoningEffort: String,
        tokensUsed: Int,
        createdAt: Date,
        updatedAt: Date,
        rolloutPath: String
    ) {
        self.id = id
        self.title = title
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.tokensUsed = tokensUsed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rolloutPath = rolloutPath
    }
}

public struct ThreadUsageSnapshot: Equatable, Sendable {
    public var threads: [ThreadUsage]
    public var totalTokens: Int
    public var activeThread: ThreadUsage?
    public var errorSummary: String?

    public var isDegraded: Bool {
        errorSummary != nil
    }

    public init(
        threads: [ThreadUsage],
        totalTokens: Int,
        activeThread: ThreadUsage?,
        errorSummary: String? = nil
    ) {
        self.threads = threads
        self.totalTokens = totalTokens
        self.activeThread = activeThread
        self.errorSummary = errorSummary
    }

    public static func degraded(_ errorSummary: String) -> ThreadUsageSnapshot {
        ThreadUsageSnapshot(threads: [], totalTokens: 0, activeThread: nil, errorSummary: errorSummary)
    }
}

public enum UsageAggregator {
    public static func snapshot(
        threads: [ThreadUsage],
        now: Date,
        activeWindow: TimeInterval = 600
    ) -> ThreadUsageSnapshot {
        let sortedThreads = threads.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.id < $1.id
            }
            return $0.updatedAt > $1.updatedAt
        }
        let totalTokens = sortedThreads.reduce(0) { $0 + $1.tokensUsed }
        let activeThread = sortedThreads.first.flatMap { thread in
            now.timeIntervalSince(thread.updatedAt) <= activeWindow ? thread : nil
        }

        return ThreadUsageSnapshot(
            threads: sortedThreads,
            totalTokens: totalTokens,
            activeThread: activeThread
        )
    }
}
