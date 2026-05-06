import Foundation

public enum QuotaConfidence: String, Codable, Sendable {
    case fresh
    case recent
    case stale
    case unknown

    public static func observed(at observedAt: Date?, now: Date) -> QuotaConfidence {
        guard let observedAt else { return .unknown }
        let age = now.timeIntervalSince(observedAt)
        if age <= 600 { return .fresh }
        if age <= 86_400 { return .recent }
        return .stale
    }
}

public struct AccountQuotaState: Codable, Equatable, Sendable {
    public var accountId: String
    public var alias: String
    public var primaryUsedPercent: Double?
    public var primaryWindowMinutes: Int?
    public var primaryResetsAt: Date?
    public var secondaryUsedPercent: Double?
    public var secondaryWindowMinutes: Int?
    public var secondaryResetsAt: Date?
    public var lastObservedAt: Date?
    public var confidence: QuotaConfidence

    public static func unknown(accountId: String, alias: String) -> AccountQuotaState {
        AccountQuotaState(
            accountId: accountId,
            alias: alias,
            primaryUsedPercent: nil,
            primaryWindowMinutes: nil,
            primaryResetsAt: nil,
            secondaryUsedPercent: nil,
            secondaryWindowMinutes: nil,
            secondaryResetsAt: nil,
            lastObservedAt: nil,
            confidence: .unknown
        )
    }
}

public struct CodixxAccount: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var alias: String
    public var fingerprint: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var quota: AccountQuotaState
    public var isEnabled: Bool
    public var priority: Int

    public func isEligibleForSwitch(hasSnapshot: Bool) -> Bool {
        guard isEnabled, hasSnapshot else { return false }
        let primaryOK = quota.primaryUsedPercent.map { $0 < 93.0 } ?? true
        let secondaryOK = quota.secondaryUsedPercent.map { $0 < 100.0 } ?? true
        return primaryOK && secondaryOK
    }
}
