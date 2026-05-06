import Foundation

public struct SwitchSafetyContext: Equatable, Sendable {
    public var now: Date
    public var activeThreadUpdatedAt: Date?
    public var lastSwitchAt: Date?

    public init(now: Date, activeThreadUpdatedAt: Date?, lastSwitchAt: Date?) {
        self.now = now
        self.activeThreadUpdatedAt = activeThreadUpdatedAt
        self.lastSwitchAt = lastSwitchAt
    }

    public static func idle(now: Date) -> SwitchSafetyContext {
        SwitchSafetyContext(now: now, activeThreadUpdatedAt: nil, lastSwitchAt: nil)
    }
}

public struct SwitchPolicy: Sendable {
    public var primaryThresholdPercent: Double
    public var autoSwitchCooldownSeconds: TimeInterval
    public var activeThreadIdleSeconds: TimeInterval

    public init(
        primaryThresholdPercent: Double = 93,
        autoSwitchCooldownSeconds: TimeInterval = 300,
        activeThreadIdleSeconds: TimeInterval = 120
    ) {
        self.primaryThresholdPercent = primaryThresholdPercent
        self.autoSwitchCooldownSeconds = autoSwitchCooldownSeconds
        self.activeThreadIdleSeconds = activeThreadIdleSeconds
    }

    public func shouldAutoSwitch(currentAccount: CodixxAccount?) -> Bool {
        shouldAutoSwitch(currentAccount: currentAccount, context: .idle(now: Date()))
    }

    public func shouldAutoSwitch(currentAccount: CodixxAccount?, context: SwitchSafetyContext) -> Bool {
        guard isSafeToAutoSwitch(context: context) else {
            return false
        }
        guard let currentAccount,
              currentAccount.quota.confidence == .fresh || currentAccount.quota.confidence == .recent,
              let primaryUsedPercent = currentAccount.quota.primaryUsedPercent
        else {
            return false
        }
        return primaryUsedPercent >= primaryThresholdPercent
    }

    public func isSafeToAutoSwitch(context: SwitchSafetyContext) -> Bool {
        if let activeThreadUpdatedAt = context.activeThreadUpdatedAt,
           context.now.timeIntervalSince(activeThreadUpdatedAt) < activeThreadIdleSeconds
        {
            return false
        }

        if let lastSwitchAt = context.lastSwitchAt,
           context.now.timeIntervalSince(lastSwitchAt) < autoSwitchCooldownSeconds
        {
            return false
        }

        return true
    }

    public func orderedCandidates(
        from accounts: [CodixxAccount],
        snapshotExists: (CodixxAccount) -> Bool
    ) -> [CodixxAccount] {
        accounts
            .filter {
                $0.isEligibleForSwitch(
                    hasSnapshot: snapshotExists($0),
                    primaryThresholdPercent: primaryThresholdPercent
                )
            }
            .sorted(by: candidatePrecedes)
    }

    private func candidatePrecedes(_ lhs: CodixxAccount, _ rhs: CodixxAccount) -> Bool {
        let lhsKnown = lhs.quota.confidence != .unknown
        let rhsKnown = rhs.quota.confidence != .unknown
        if lhsKnown != rhsKnown { return lhsKnown }
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }

        let lhsSecondary = lhs.quota.secondaryUsedPercent ?? Double.greatestFiniteMagnitude
        let rhsSecondary = rhs.quota.secondaryUsedPercent ?? Double.greatestFiniteMagnitude
        if lhsSecondary != rhsSecondary { return lhsSecondary < rhsSecondary }

        let lhsPrimary = lhs.quota.primaryUsedPercent ?? Double.greatestFiniteMagnitude
        let rhsPrimary = rhs.quota.primaryUsedPercent ?? Double.greatestFiniteMagnitude
        if lhsPrimary != rhsPrimary { return lhsPrimary < rhsPrimary }

        switch (lhs.lastUsedAt, rhs.lastUsedAt) {
        case (nil, nil):
            return lhs.alias < rhs.alias
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        case let (lhsDate?, rhsDate?):
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return lhs.alias < rhs.alias
        }
    }
}
