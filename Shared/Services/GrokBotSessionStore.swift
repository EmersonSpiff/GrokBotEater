import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.emersonspiff.grokboteater.app", category: "GrokBotSessionStore")

/// Persists a web-captured `WorkosCursorSessionToken` cookie in the Keychain so Connect
/// and GrokBotUsageStore can authenticate without scraping Chromium DBs.
final class GrokBotSessionStore: @unchecked Sendable {
    static let shared = GrokBotSessionStore()

    private let service = "com.emersonspiff.grokboteater.cursor-session"
    private let account = "WorkosCursorSessionToken"

    func savedCookie() -> String? {
        if let value = readAccount(account) { return value }
        // Migrate legacy Keychain item from CursorAppLogin era.
        if let legacy = readAccount("CursorAppLogin") {
            save(cookie: legacy)
            deleteAccount("CursorAppLogin")
            return legacy
        }
        return nil
    }

    private func readAccount(_ accountName: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func deleteAccount(_ accountName: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func save(cookie: String) {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }

        // Replace any existing item.
        clear()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain save failed: \(status, privacy: .public)")
        }
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
