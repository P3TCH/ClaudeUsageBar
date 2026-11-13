import Foundation
import Security

/// Stores one token per provider as a generic-password Keychain item.
public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String = "com.usagebar.app") {
        self.service = service
    }

    public func load(_ provider: Provider) -> StoredToken? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredToken.self, from: data)
    }

    public func save(_ token: StoredToken, for provider: Provider) throws {
        let data = try JSONEncoder().encode(token)
        let update = [kSecValueData as String: data] as CFDictionary
        var status = SecItemUpdate(baseQuery(provider) as CFDictionary, update)
        if status == errSecItemNotFound {
            var add = baseQuery(provider)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecAttrLabel as String] = "UsageBar (\(provider.displayName))"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw UsageError.network("Keychain error \(status)")
        }
    }

    public func delete(_ provider: Provider) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
    }

    private func baseQuery(_ provider: Provider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }
}
