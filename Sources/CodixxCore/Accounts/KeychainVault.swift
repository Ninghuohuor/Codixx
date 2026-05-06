import Foundation
import Security

public struct KeychainVault: AuthSnapshotVault {
    public let service: String

    public init(service: String = "Codixx.AuthSnapshot") {
        self.service = service
    }

    public func save(snapshot: AuthSnapshot, fingerprint: String) throws {
        let query = baseQuery(fingerprint: fingerprint)
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = snapshot.jsonData
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AccountStoreError.keychainError(Self.message(for: status))
        }
    }

    public func load(fingerprint: String) throws -> AuthSnapshot {
        var query = baseQuery(fingerprint: fingerprint)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status == errSecItemNotFound {
                throw AccountStoreError.snapshotNotFound(fingerprint)
            }
            throw AccountStoreError.keychainError(Self.message(for: status))
        }
        return try AuthSnapshot(jsonData: data)
    }

    public func delete(fingerprint: String) throws {
        let status = SecItemDelete(baseQuery(fingerprint: fingerprint) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountStoreError.keychainError(Self.message(for: status))
        }
    }

    private func baseQuery(fingerprint: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: fingerprint
        ]
    }

    private static func message(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
    }
}
