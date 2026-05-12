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
    public var planType: String?
    public var primaryUsedPercent: Double?
    public var primaryWindowMinutes: Int?
    public var primaryResetsAt: Date?
    public var secondaryUsedPercent: Double?
    public var secondaryWindowMinutes: Int?
    public var secondaryResetsAt: Date?
    public var lastObservedAt: Date?
    public var confidence: QuotaConfidence

    public init(
        accountId: String,
        alias: String,
        planType: String? = nil,
        primaryUsedPercent: Double?,
        primaryWindowMinutes: Int?,
        primaryResetsAt: Date?,
        secondaryUsedPercent: Double?,
        secondaryWindowMinutes: Int?,
        secondaryResetsAt: Date?,
        lastObservedAt: Date?,
        confidence: QuotaConfidence
    ) {
        self.accountId = accountId
        self.alias = alias
        self.planType = planType
        self.primaryUsedPercent = primaryUsedPercent
        self.primaryWindowMinutes = primaryWindowMinutes
        self.primaryResetsAt = primaryResetsAt
        self.secondaryUsedPercent = secondaryUsedPercent
        self.secondaryWindowMinutes = secondaryWindowMinutes
        self.secondaryResetsAt = secondaryResetsAt
        self.lastObservedAt = lastObservedAt
        self.confidence = confidence
    }

    public static func unknown(accountId: String, alias: String) -> AccountQuotaState {
        AccountQuotaState(
            accountId: accountId,
            alias: alias,
            planType: nil,
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

    @discardableResult
    public mutating func rollForwardExpiredWindows(now: Date) -> Bool {
        var didChange = false
        didChange = rollForwardExpiredWindow(
            usedPercent: &primaryUsedPercent,
            windowMinutes: primaryWindowMinutes,
            resetsAt: &primaryResetsAt,
            now: now
        ) || didChange
        didChange = rollForwardExpiredWindow(
            usedPercent: &secondaryUsedPercent,
            windowMinutes: secondaryWindowMinutes,
            resetsAt: &secondaryResetsAt,
            now: now
        ) || didChange
        return didChange
    }

    private func rollForwardExpiredWindow(
        usedPercent: inout Double?,
        windowMinutes: Int?,
        resetsAt: inout Date?,
        now: Date
    ) -> Bool {
        guard let reset = resetsAt, reset <= now else { return false }

        usedPercent = 0
        guard let windowMinutes, windowMinutes > 0 else { return true }

        let windowSeconds = TimeInterval(windowMinutes * 60)
        var nextReset = reset
        while nextReset <= now {
            nextReset = nextReset.addingTimeInterval(windowSeconds)
        }
        resetsAt = nextReset
        return true
    }
}

public enum CredentialKind: String, Codable, Equatable, Hashable, Sendable {
    case chatgpt
    case apiProvider
}

public struct APIBalanceQueryConfig: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case urlText
        case jsonPath
        case refreshIntervalSeconds
        case minimumBalance
        case lastBalanceText
        case lastRefreshedAt
    }

    public var isEnabled: Bool
    public var urlText: String
    public var jsonPath: String
    public var refreshIntervalSeconds: TimeInterval
    public var minimumBalance: Double
    public var lastBalanceText: String?
    public var lastRefreshedAt: Date?

    public init(
        isEnabled: Bool = false,
        urlText: String = "",
        jsonPath: String = "",
        refreshIntervalSeconds: TimeInterval = 900,
        minimumBalance: Double = 0,
        lastBalanceText: String? = nil,
        lastRefreshedAt: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.urlText = urlText
        self.jsonPath = jsonPath
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.minimumBalance = minimumBalance
        self.lastBalanceText = lastBalanceText
        self.lastRefreshedAt = lastRefreshedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.urlText = try container.decode(String.self, forKey: .urlText)
        self.jsonPath = try container.decode(String.self, forKey: .jsonPath)
        self.refreshIntervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .refreshIntervalSeconds) ?? 900
        self.minimumBalance = try container.decodeIfPresent(Double.self, forKey: .minimumBalance) ?? 0
        self.lastBalanceText = try container.decodeIfPresent(String.self, forKey: .lastBalanceText)
        self.lastRefreshedAt = try container.decodeIfPresent(Date.self, forKey: .lastRefreshedAt)
    }

    public var parsedLastBalance: Double? {
        guard let lastBalanceText else { return nil }
        return Self.parseBalance(lastBalanceText)
    }

    public var hasSufficientBalance: Bool {
        guard isEnabled, let balance = parsedLastBalance else { return false }
        return balance > minimumBalance
    }

    public var isBalanceDepleted: Bool {
        guard isEnabled, let balance = parsedLastBalance else { return false }
        return balance <= minimumBalance
    }

    public static func parseBalance(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed) {
            return value
        }
        let pattern = #"[-+]?(?:\d+(?:\.\d*)?|\.\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range, in: trimmed)
        else {
            return nil
        }
        return Double(trimmed[range])
    }
}

public struct APIProviderAccount: Codable, Equatable, Sendable {
    public var providerName: String
    public var baseURL: URL
    public var defaultModel: String?
    public var keyFingerprint: String
    public var balanceQuery: APIBalanceQueryConfig?

    public init(
        providerName: String,
        baseURL: URL,
        defaultModel: String?,
        keyFingerprint: String,
        balanceQuery: APIBalanceQueryConfig? = nil
    ) {
        self.providerName = providerName
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.keyFingerprint = keyFingerprint
        self.balanceQuery = balanceQuery
    }
}

public struct CodixxAccount: Codable, Identifiable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case alias
        case fingerprint
        case credentialKind
        case apiProvider
        case createdAt
        case updatedAt
        case lastUsedAt
        case membershipExpiresAt
        case quota
        case isEnabled
        case priority
    }

    public var id: UUID
    public var alias: String
    public var fingerprint: String
    public var credentialKind: CredentialKind
    public var apiProvider: APIProviderAccount?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var membershipExpiresAt: Date?
    public var quota: AccountQuotaState
    public var isEnabled: Bool
    public var priority: Int

    public init(
        id: UUID,
        alias: String,
        fingerprint: String,
        credentialKind: CredentialKind = .chatgpt,
        apiProvider: APIProviderAccount? = nil,
        createdAt: Date,
        updatedAt: Date,
        lastUsedAt: Date?,
        membershipExpiresAt: Date? = nil,
        quota: AccountQuotaState,
        isEnabled: Bool,
        priority: Int
    ) {
        self.id = id
        self.alias = alias
        self.fingerprint = fingerprint
        self.credentialKind = credentialKind
        self.apiProvider = apiProvider
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.membershipExpiresAt = membershipExpiresAt
        self.quota = quota
        self.isEnabled = isEnabled
        self.priority = priority
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.alias = try container.decode(String.self, forKey: .alias)
        self.fingerprint = try container.decode(String.self, forKey: .fingerprint)
        self.credentialKind = try container.decodeIfPresent(CredentialKind.self, forKey: .credentialKind) ?? .chatgpt
        self.apiProvider = try container.decodeIfPresent(APIProviderAccount.self, forKey: .apiProvider)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        self.membershipExpiresAt = try container.decodeIfPresent(Date.self, forKey: .membershipExpiresAt)
        self.quota = try container.decode(AccountQuotaState.self, forKey: .quota)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.priority = try container.decode(Int.self, forKey: .priority)
    }

    public var isChatGPT: Bool { credentialKind == .chatgpt }
    public var isAPIProvider: Bool { credentialKind == .apiProvider }
    public var hasSufficientAPIBalance: Bool {
        guard isAPIProvider else { return false }
        return apiProvider?.balanceQuery?.hasSufficientBalance == true
    }

    public var hasMeasuredAPIBalance: Bool {
        guard isAPIProvider,
              let balanceQuery = apiProvider?.balanceQuery,
              balanceQuery.isEnabled
        else { return false }
        return balanceQuery.parsedLastBalance != nil
    }

    public var isAPIBalanceDepleted: Bool {
        guard isAPIProvider else { return false }
        return apiProvider?.balanceQuery?.isBalanceDepleted == true
    }

    public func isEligibleForSwitch(
        hasSnapshot: Bool,
        primaryThresholdPercent: Double = 93.0,
        secondaryThresholdPercent: Double = 90.0
    ) -> Bool {
        guard isEnabled else { return false }
        if isAPIProvider {
            return hasSufficientAPIBalance
        }
        guard isChatGPT, hasSnapshot else { return false }
        guard quota.confidence == .fresh || quota.confidence == .recent,
              let primaryUsedPercent = quota.primaryUsedPercent,
              let secondaryUsedPercent = quota.secondaryUsedPercent
        else {
            return false
        }
        let primaryOK = primaryUsedPercent < primaryThresholdPercent
        let secondaryOK = secondaryUsedPercent < secondaryThresholdPercent
        return primaryOK && secondaryOK
    }
}
