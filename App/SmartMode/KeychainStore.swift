// API: App/SmartMode/KeychainStore.swift
// WP13 (04 Appendix B.2.2 / revision 3): the Anthropic API key lives only in this device's Keychain
// (kSecClassGenericPassword, AfterFirstUnlockThisDeviceOnly, no access group → works with a free Apple ID).
// The only file allowed to import Security (§9 r34 as amended by revision 3). Values are never logged.
import Foundation
import Security

final class KeychainStore: @unchecked Sendable {
    static let defaultService = "com.gokhanbudak.asist.smartmode"
    static let apiKeyAccount = "anthropic-api-key"

    let service: String

    init(service: String) {
        self.service = service
    }

    /// nil when missing, unreadable (device locked since boot) or not UTF-8.
    func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            AsistLog.error("Anahtarlık okunamadı (kod " + String(status) + ")", .smart)
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// true when an item exists (no data is returned or decoded).
    func contains(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Delete-then-add. false when the Keychain refused the item (logged with the status code only).
    @discardableResult
    func write(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8), !data.isEmpty else { return false }
        delete(account: account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            AsistLog.error("Anahtarlığa yazılamadı (kod " + String(status) + ")", .smart)
            return false
        }
        return true
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AsistLog.error("Anahtarlıktan silinemedi (kod " + String(status) + ")", .smart)
        }
    }
}
