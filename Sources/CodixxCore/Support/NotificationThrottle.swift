import Foundation

public struct NotificationThrottle: Sendable {
    public enum QuotaKind: String, Hashable, Sendable {
        case primary
        case secondary
    }

    public enum Event: Hashable, Sendable {
        case quotaWarning(accountId: String, quotaKind: QuotaKind)
        case generic(type: String)
        case protectionModeEntered
    }

    public static let quotaWarningInterval: TimeInterval = 5 * 60 * 60
    public static let sameTypeInterval: TimeInterval = 5 * 60

    private var lastSentAtByKey: [String: Date]
    private var hasSentProtectionModeEntry: Bool

    public init() {
        self.lastSentAtByKey = [:]
        self.hasSentProtectionModeEntry = false
    }

    public mutating func shouldSend(_ event: Event, at now: Date = Date()) -> Bool {
        switch event {
        case .quotaWarning:
            return shouldSend(event, at: now, minimumInterval: Self.quotaWarningInterval)
        case .generic:
            return shouldSend(event, at: now, minimumInterval: Self.sameTypeInterval)
        case .protectionModeEntered:
            guard !hasSentProtectionModeEntry else { return false }
            hasSentProtectionModeEntry = true
            return true
        }
    }

    private mutating func shouldSend(_ event: Event, at now: Date, minimumInterval: TimeInterval) -> Bool {
        let key = event.throttleKey
        if let lastSentAt = lastSentAtByKey[key],
           now.timeIntervalSince(lastSentAt) < minimumInterval {
            return false
        }

        lastSentAtByKey[key] = now
        return true
    }
}

private extension NotificationThrottle.Event {
    var throttleKey: String {
        switch self {
        case let .quotaWarning(accountId, quotaKind):
            return "quota-warning:\(accountId):\(quotaKind.rawValue)"
        case let .generic(type):
            return "generic:\(type)"
        case .protectionModeEntered:
            return "protection-mode-entered"
        }
    }
}
