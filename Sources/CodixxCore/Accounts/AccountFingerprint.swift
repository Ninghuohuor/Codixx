import CryptoKit
import Foundation

public enum AccountFingerprint {
    public static func generate(from snapshot: AuthSnapshot) throws -> String {
        if let accountId = snapshot.stringValue(for: "account_id"), !accountId.isEmpty {
            return "account:\(accountId)"
        }
        if let email = snapshot.stringValue(for: "email"), !email.isEmpty {
            return "email:\(email.lowercased())"
        }
        if let accessToken = snapshot.stringValue(for: "access_token"), !accessToken.isEmpty {
            return "token:\(sha256Prefix16(accessToken))"
        }
        throw AccountStoreError.missingFingerprintSource
    }

    private static func sha256Prefix16(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
            .description
    }
}
