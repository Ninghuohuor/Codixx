import Foundation
import Security

public protocol APIKeyVault {
    func save(apiKey: String, fingerprint: String) throws
    func load(fingerprint: String) throws -> String
    func delete(fingerprint: String) throws
}

public enum APIKeyFingerprint {
    public static func generate(apiKey: String) -> String {
        "api-key:\(sha256Prefix16(apiKey))"
    }
}

public struct KeychainAPIKeyVault: APIKeyVault {
    public let service: String

    public init(service: String = "Codixx.APIKey") {
        self.service = service
    }

    public func save(apiKey: String, fingerprint: String) throws {
        let query = baseQuery(fingerprint: fingerprint)
        let updateQuery = [
            kSecValueData as String: Data(apiKey.utf8)
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateQuery as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AccountStoreError.keychainError(KeychainVault.message(for: updateStatus))
        }

        var addQuery = query
        addQuery[kSecValueData as String] = Data(apiKey.utf8)
        if let access = KeychainVault.currentApplicationAccess(descriptor: service) {
            addQuery[kSecAttrAccess as String] = access
        }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AccountStoreError.keychainError(KeychainVault.message(for: status))
        }
    }

    public func load(fingerprint: String) throws -> String {
        var query = baseQuery(fingerprint: fingerprint)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw AccountStoreError.snapshotNotFound(fingerprint)
            }
            throw AccountStoreError.keychainError(KeychainVault.message(for: status))
        }
        guard let data = item as? Data, let apiKey = String(data: data, encoding: .utf8) else {
            throw AccountStoreError.keychainError("Stored API key data is invalid")
        }
        return apiKey
    }

    public func delete(fingerprint: String) throws {
        let status = SecItemDelete(baseQuery(fingerprint: fingerprint) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountStoreError.keychainError(KeychainVault.message(for: status))
        }
    }

    private func baseQuery(fingerprint: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: fingerprint
        ]
    }
}
