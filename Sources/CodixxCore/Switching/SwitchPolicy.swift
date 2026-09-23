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
    public var secondaryThresholdPercent: Double
    public var autoSwitchCooldownSeconds: TimeInterval
    public var activeThreadIdleSeconds: TimeInterval

    public init(
        primaryThresholdPercent: Double = 93,
        secondaryThresholdPercent: Double = 90,
        autoSwitchCooldownSeconds: TimeInterval = 300,
        activeThreadIdleSeconds: TimeInterval = 120
    ) {
        self.primaryThresholdPercent = primaryThresholdPercent
        self.secondaryThresholdPercent = secondaryThresholdPercent
        self.autoSwitchCooldownSeconds = autoSwitchCooldownSeconds
        self.activeThreadIdleSeconds = activeThreadIdleSeconds
    }

    public func shouldAutoSwitch(currentAccount: CodixxAccount?, allAccounts: [CodixxAccount] = []) -> Bool {
        shouldAutoSwitch(currentAccount: currentAccount, allAccounts: allAccounts, context: .idle(now: Date()))
    }

    public func shouldAutoSwitch(currentAccount: CodixxAccount?, allAccounts: [CodixxAccount] = [], context: SwitchSafetyContext) -> Bool {
        guard let currentAccount else { return false }
        if currentAccount.isAPIProvider {
            guard currentAccount.hasMeasuredAPIBalance, currentAccount.isAPIBalanceDepleted else { return false }
            guard isSafeToAutoSwitch(context: context) else { return false }
            let others = allAccounts.filter { $0.id != currentAccount.id }
            return !orderedCandidates(from: others) { _ in true }.isEmpty
        }
        guard currentAccount.isChatGPT,
              currentAccount.quota.confidence == .fresh || currentAccount.quota.confidence == .recent,
              currentAccount.quota.primaryUsedPercent != nil || currentAccount.quota.secondaryUsedPercent != nil
        else { return false }
        guard isSafeToAutoSwitch(context: context) else { return false }
        if isDepleted(currentAccount) {
            let others = allAccounts.filter { $0.id != currentAccount.id }
            let hasAvailable = !orderedCandidates(from: others) { _ in true }.isEmpty
            return hasAvailable
        }
        return currentAccount.quota.reachesThreshold(short: primaryThresholdPercent, weekly: secondaryThresholdPercent)
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
                    primaryThresholdPercent: primaryThresholdPercent,
                    secondaryThresholdPercent: secondaryThresholdPercent
                )
            }
            .sorted(by: candidatePrecedes)
    }

    private func candidatePrecedes(_ lhs: CodixxAccount, _ rhs: CodixxAccount) -> Bool {
        if lhs.isChatGPT != rhs.isChatGPT { return lhs.isChatGPT }
        let lhsKnown = lhs.quota.confidence != .unknown
        let rhsKnown = rhs.quota.confidence != .unknown
        if lhsKnown != rhsKnown { return lhsKnown }
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }

        let lhsHeadroomFloor = minimumNormalizedHeadroom(for: lhs)
        let rhsHeadroomFloor = minimumNormalizedHeadroom(for: rhs)
        if lhsHeadroomFloor != rhsHeadroomFloor { return lhsHeadroomFloor > rhsHeadroomFloor }

        let lhsHeadroomScore = weightedHeadroomScore(for: lhs)
        let rhsHeadroomScore = weightedHeadroomScore(for: rhs)
        if lhsHeadroomScore != rhsHeadroomScore { return lhsHeadroomScore > rhsHeadroomScore }

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

    private func minimumNormalizedHeadroom(for account: CodixxAccount) -> Double {
        account.quota.reportedWindows.map {
            normalizedHeadroom(usedPercent: $0.usedPercent, threshold: $0.threshold(short: primaryThresholdPercent, weekly: secondaryThresholdPercent))
        }.min() ?? 0
    }

    private func weightedHeadroomScore(for account: CodixxAccount) -> Double {
        let windows = account.quota.reportedWindows
        let weights = windows.map { window -> Double in
            if let minutes = window.minutes { return minutes >= 10_080 ? 0.4 : 0.6 }
            return window.isSecondary ? 0.4 : 0.6
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }
        return zip(windows, weights).reduce(0) { sum, entry in
            sum + normalizedHeadroom(usedPercent: entry.0.usedPercent, threshold: entry.0.threshold(short: primaryThresholdPercent, weekly: secondaryThresholdPercent)) * entry.1
        } / total
    }

    private func normalizedHeadroom(usedPercent: Double?, threshold: Double) -> Double {
        guard threshold > 0, let usedPercent else { return 0 }
        return max(0, min(1, (threshold - usedPercent) / threshold))
    }

    private func isDepleted(_ account: CodixxAccount) -> Bool {
        let primaryDepleted = account.quota.primaryUsedPercent.map { $0 >= 100 } ?? false
        let secondaryDepleted = account.quota.secondaryUsedPercent.map { $0 >= 100 } ?? false
        return primaryDepleted || secondaryDepleted
    }
}
