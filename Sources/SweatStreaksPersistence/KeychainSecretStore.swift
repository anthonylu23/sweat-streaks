import Foundation
import Security

public protocol SecretStore {
    func setSecret(_ value: String, for key: String) throws
    func getSecret(for key: String) throws -> String?
    func deleteSecret(for key: String) throws
}

public enum SecretStoreError: Error {
    case unexpectedStatus(OSStatus)
    case invalidData
}

public final class KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "com.sweatstreaks.app") {
        self.service = service
    }

    public func setSecret(_ value: String, for key: String) throws {
        guard let valueData = value.data(using: .utf8) else {
            throw SecretStoreError.invalidData
        }

        let query = lookupQuery(for: key)

        let attributes: [String: Any] = [
            kSecValueData as String: valueData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var insertQuery = baseQuery(for: key)
            insertQuery[kSecValueData as String] = valueData
            let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecretStoreError.unexpectedStatus(addStatus)
            }
            return
        }

        throw SecretStoreError.unexpectedStatus(updateStatus)
    }

    public func getSecret(for key: String) throws -> String? {
        var query = lookupQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidData
        }

        return value
    }

    public func deleteSecret(for key: String) throws {
        let status = SecItemDelete(lookupQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        var query = lookupQuery(for: key)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return query
    }

    private func lookupQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
