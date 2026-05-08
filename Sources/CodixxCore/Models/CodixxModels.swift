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

public enum CredentialKind: String, Codable, Equatable, Sendable {
    case chatgpt
    case apiProvider
}

public struct APIProviderAccount: Codable, Equatable, Sendable {
    public var providerName: String
    public var baseURL: URL
    public var defaultModel: String?
    public var keyFingerprint: String

    public init(
        providerName: String,
        baseURL: URL,
        defaultModel: String?,
        keyFingerprint: String
    ) {
        self.providerName = providerName
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.keyFingerprint = keyFingerprint
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

    public func isEligibleForSwitch(
        hasSnapshot: Bool,
        primaryThresholdPercent: Double = 93.0,
        secondaryThresholdPercent: Double = 90.0
    ) -> Bool {
        guard isChatGPT, isEnabled, hasSnapshot else { return false }
        let primaryOK = quota.primaryUsedPercent.map { $0 < primaryThresholdPercent } ?? true
        let secondaryOK = quota.secondaryUsedPercent.map { $0 < secondaryThresholdPercent } ?? true
        return primaryOK && secondaryOK
    }
}
