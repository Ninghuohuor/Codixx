import Foundation

public struct AuthProfile: Equatable, Sendable {
    public var planType: String?
    public var membershipExpiresAt: Date?

    public init(planType: String? = nil, membershipExpiresAt: Date? = nil) {
        self.planType = planType
        self.membershipExpiresAt = membershipExpiresAt
    }
}

public enum AuthProfileReader {
    public static func profile(from snapshot: AuthSnapshot) -> AuthProfile? {
        let profiles = ["id_token", "access_token"]
            .compactMap { snapshot.stringValue(for: $0) }
            .compactMap(profileFromJWT)

        guard !profiles.isEmpty else { return nil }

        return AuthProfile(
            planType: profiles.compactMap(\.planType).first,
            membershipExpiresAt: profiles.compactMap(\.membershipExpiresAt).first
        )
    }

    private static func profileFromJWT(_ token: String) -> AuthProfile? {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payloadData = base64URLDecode(String(parts[1])),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: payloadData),
              let auth = payload.openAIAuth
        else {
            return nil
        }

        return AuthProfile(
            planType: auth.chatGPTPlanType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            membershipExpiresAt: auth.membershipExpiresAt
        )
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }
        return Data(base64Encoded: base64)
    }
}

private struct JWTPayload: Decodable {
    var openAIAuth: OpenAIAuthClaim?

    enum CodingKeys: String, CodingKey {
        case openAIAuth = "https://api.openai.com/auth"
    }
}

private struct OpenAIAuthClaim: Decodable {
    var chatGPTPlanType: String?
    var membershipExpiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case chatGPTPlanType = "chatgpt_plan_type"
        case subscriptionActiveUntil = "chatgpt_subscription_active_until"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chatGPTPlanType = try container.decodeIfPresent(String.self, forKey: .chatGPTPlanType)
        self.membershipExpiresAt = try container
            .decodeIfPresent(AuthProfileFlexibleDate.self, forKey: .subscriptionActiveUntil)?
            .date
    }
}

private struct AuthProfileFlexibleDate: Decodable {
    var date: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let timestamp = try? container.decode(Int64.self) {
            self.date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            return
        }

        if let timestamp = try? container.decode(Double.self) {
            self.date = Date(timeIntervalSince1970: timestamp)
            return
        }

        let text = try container.decode(String.self)
        if let timestamp = Double(text) {
            self.date = Date(timeIntervalSince1970: timestamp)
            return
        }

        if let date = Self.parseISO8601Date(text) {
            self.date = date
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date value")
    }

    private static func parseISO8601Date(_ text: String) -> Date? {
        let wholeSecondFormatter = ISO8601DateFormatter()
        wholeSecondFormatter.formatOptions = [.withInternetDateTime]
        if let date = wholeSecondFormatter.date(from: text) {
            return date
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: text)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
