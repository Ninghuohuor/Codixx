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

    public static func == (lhs: AuthSnapshot, rhs: AuthSnapshot) -> Bool {
        lhs.jsonData == rhs.jsonData
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
