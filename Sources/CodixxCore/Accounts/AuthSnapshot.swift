import Foundation

public struct AuthSnapshot: Equatable, Sendable {
    public let jsonData: Data
    private let object: [String: AnySendableValue]

    public init(jsonData: Data) throws {
        let raw = try JSONSerialization.jsonObject(with: jsonData)
        guard let dictionary = raw as? [String: Any] else {
            throw AccountStoreError.invalidAuthSnapshot
        }
        self.jsonData = jsonData
        self.object = dictionary.mapValues(AnySendableValue.init)
    }

    public func stringValue(for key: String) -> String? {
        if let value = object[key]?.stringValue {
            return value
        }
        return object["tokens"]?.dictionaryValue?[key]?.stringValue
    }

    public static func apiKey(_ apiKey: String) throws -> AuthSnapshot {
        let object: [String: String] = [
            "auth_mode": "apikey",
            "OPENAI_API_KEY": apiKey
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return try AuthSnapshot(jsonData: data)
    }

    public var accessTokenExpiresAt: Date? {
        guard let accessToken = stringValue(for: "access_token") else { return nil }
        return Self.jwtExpirationDate(accessToken)
    }

    /// Returns a new snapshot with rotated ChatGPT OAuth tokens while preserving
    /// the rest of Codex's auth.json payload. OpenAI may omit an id or refresh
    /// token from a successful refresh response, so nil values keep the existing
    /// field instead of deleting it.
    public func replacingChatGPTTokens(
        idToken: String?,
        accessToken: String,
        refreshToken: String?,
        refreshedAt: Date
    ) throws -> AuthSnapshot {
        guard !accessToken.isEmpty else { throw AccountStoreError.invalidAuthSnapshot }
        guard var root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AccountStoreError.invalidAuthSnapshot
        }

        if var tokens = root["tokens"] as? [String: Any] {
            if let idToken, !idToken.isEmpty { tokens["id_token"] = idToken }
            tokens["access_token"] = accessToken
            if let refreshToken, !refreshToken.isEmpty { tokens["refresh_token"] = refreshToken }
            root["tokens"] = tokens
        } else {
            if let idToken, !idToken.isEmpty { root["id_token"] = idToken }
            root["access_token"] = accessToken
            if let refreshToken, !refreshToken.isEmpty { root["refresh_token"] = refreshToken }
        }
        root["last_refresh"] = Self.iso8601WithFractionalSeconds.string(from: refreshedAt)

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return try AuthSnapshot(jsonData: data)
    }

    public static func == (lhs: AuthSnapshot, rhs: AuthSnapshot) -> Bool {
        lhs.jsonData == rhs.jsonData
    }

    private static func jwtExpirationDate(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payloadData = base64URLDecode(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let expiration = numericValue(payload["exp"])
        else {
            return nil
        }
        return Date(timeIntervalSince1970: expiration)
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

    private static func numericValue(_ value: Any?) -> TimeInterval? {
        switch value {
        case let int as Int:
            return TimeInterval(int)
        case let int64 as Int64:
            return TimeInterval(int64)
        case let double as Double:
            return double
        case let number as NSNumber:
            return number.doubleValue
        default:
            return nil
        }
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct AnySendableValue: @unchecked Sendable {
    let value: Any

    var stringValue: String? {
        value as? String
    }

    var dictionaryValue: [String: AnySendableValue]? {
        guard let dictionary = value as? [String: Any] else { return nil }
        return dictionary.mapValues(AnySendableValue.init)
    }
}
