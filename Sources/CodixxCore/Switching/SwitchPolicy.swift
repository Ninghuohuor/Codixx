import Foundation

public struct SwitchPolicy: Sendable {
    public var primaryThresholdPercent: Double

    public init(primaryThresholdPercent: Double = 93) {
        self.primaryThresholdPercent = primaryThresholdPercent
    }

    public func shouldAutoSwitch(currentAccount: CodixxAccount?) -> Bool {
        guard let currentAccount,
              currentAccount.quota.confidence == .fresh || currentAccount.quota.confidence == .recent,
              let primaryUsedPercent = currentAccount.quota.primaryUsedPercent
        else {
            return false
        }
        return primaryUsedPercent >= primaryThresholdPercent
    }

    public func orderedCandidates(
        from accounts: [CodixxAccount],
        snapshotExists: (CodixxAccount) -> Bool
    ) -> [CodixxAccount] {
        accounts
            .filter { $0.isEligibleForSwitch(hasSnapshot: snapshotExists($0)) }
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
