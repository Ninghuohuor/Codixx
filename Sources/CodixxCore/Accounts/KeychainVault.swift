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
        if let access = Self.currentApplicationAccess(descriptor: service) {
            addQuery[kSecAttrAccess as String] = access
        }
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
        refreshCurrentApplicationAccess(fingerprint: fingerprint, data: data)
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

    private func refreshCurrentApplicationAccess(fingerprint: String, data: Data) {
        guard let access = Self.currentApplicationAccess(descriptor: service) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccess as String: access
        ]
        _ = SecItemUpdate(baseQuery(fingerprint: fingerprint) as CFDictionary, attributes as CFDictionary)
    }

    private static func currentApplicationAccess(descriptor: String) -> SecAccess? {
        var trustedApplication: SecTrustedApplication?
        let trustedStatus = SecTrustedApplicationCreateFromPath(nil, &trustedApplication)
        guard trustedStatus == errSecSuccess, let trustedApplication else { return nil }

        var access: SecAccess?
        let accessStatus = SecAccessCreate(
            descriptor as CFString,
            [trustedApplication] as CFArray,
            &access
        )
        guard accessStatus == errSecSuccess else { return nil }
        return access
    }

    private static func message(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
    }
}
