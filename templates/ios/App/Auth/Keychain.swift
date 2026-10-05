import Foundation
import os
import Security

private let keychainLog = Logger(subsystem: "app.storefront", category: "Keychain")

/// Small secrets as Keychain generic passwords under the app's bundle id: readable once the device has been unlocked after a
/// restart, never synced or restored to another device. A failure is logged with its status only (never a value) and reads as
/// nothing stored. The functions are async so the Keychain is never called on the main thread (it can block).
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "argon"

    private static func item(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load(_ account: String) async -> Data? {
        var query = item(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            keychainLog.warning("keychain read failed (\(status))")
            return nil
        }
        return data
    }

    /// Stores `data` under `account`; nil deletes it.
    /// ponytail: delete-then-add, so a failed add loses the old value too; that only costs the session across a restart.
    static func save(_ account: String, _ data: Data?) async {
        var status = SecItemDelete(item(account) as CFDictionary)
        if status == errSecItemNotFound { status = errSecSuccess }
        if status == errSecSuccess, let data = data {
            var add = item(account)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess { keychainLog.warning("keychain write failed (\(status))") }
    }
}
