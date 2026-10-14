import Foundation
import Security

enum LicenseKeychainError: Error {
    case encodingFailed
    case unexpectedStatus(OSStatus)
}

struct LicenseKeychain {
    private let service: String

    init(service: String = "com.abel.primarypaste.licensing") {
        self.service = service
    }

    func loadInstallationID() throws -> String {
        if let data = try read(account: "installation-id"),
            let value = String(data: data, encoding: .utf8)
        {
            return value
        }
        let value = UUID().uuidString.lowercased()
        guard let data = value.data(using: .utf8) else { throw LicenseKeychainError.encodingFailed }
        try write(data, account: "installation-id")
        return value
    }

    func loadLicense() throws -> StoredLicense? {
        guard let data = try read(account: "license") else { return nil }
        return try JSONDecoder().decode(StoredLicense.self, from: data)
    }

    func saveLicense(_ license: StoredLicense) throws {
        try write(JSONEncoder().encode(license), account: "license")
    }

    func removeLicense() throws {
        let status = SecItemDelete(baseQuery(account: "license") as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenseKeychainError.unexpectedStatus(status)
        }
    }

    private func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw LicenseKeychainError.unexpectedStatus(status)
        }
        return data
    }

    private func write(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw LicenseKeychainError.unexpectedStatus(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw LicenseKeychainError.unexpectedStatus(addStatus)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
