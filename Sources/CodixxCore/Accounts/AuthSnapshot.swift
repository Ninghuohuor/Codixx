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

    public var accessTokenExpiresAt: Date? {
        guard let accessToken = stringValue(for: "access_token") else { return nil }
        return Self.jwtExpirationDate(accessToken)
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
