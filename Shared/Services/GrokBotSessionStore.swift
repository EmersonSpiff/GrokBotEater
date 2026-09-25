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
    /// Process-lifetime cache — avoid Keychain SecItemCopyMatching on every poll.
    private var memoryCookie: String?
    private let lock = NSLock()

    /// Synchronous accessor: returns the cached cookie immediately, or nil if not yet loaded.
    /// Use `loadCookieAsync()` to populate the cache on app launch without blocking the main thread.
    func savedCookie() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return memoryCookie
    }
    
    /// Async load from Keychain. Call this once at app launch to populate the cache
    /// without blocking the main thread. Subsequent `savedCookie()` calls return instantly.
    func loadCookieAsync() async -> String? {
        // Check cache first
        lock.lock()
        if let cached = memoryCookie, !cached.isEmpty {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        // Read from Keychain on background thread
        return await Task.detached { [weak self] in
            guard let self else { return nil }
            
            if let value = self.readAccount(self.account) {
                self.lock.lock()
                self.memoryCookie = value
                self.lock.unlock()
                return value
            }
            // Migrate legacy Keychain item from CursorAppLogin era.
            if let legacy = self.readAccount("CursorAppLogin") {
                self.save(cookie: legacy)
                self.deleteAccount("CursorAppLogin")
                return legacy
            }
            return nil
        }.value
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

        lock.lock()
        memoryCookie = trimmed
        lock.unlock()

        // Replace any existing Keychain item without wiping the in-memory cache.
        deleteAccount(account)

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
        lock.lock()
        memoryCookie = nil
        lock.unlock()
        deleteAccount(account)
    }
}
