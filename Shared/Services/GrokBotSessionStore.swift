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
    /// Serial queue for all keychain operations to avoid blocking the main thread.
    private let keychainQueue = DispatchQueue(label: "com.emersonspiff.grokboteater.keychain", qos: .userInitiated)

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
        
        // Read from Keychain on serial queue (not main thread)
        return await withCheckedContinuation { continuation in
            keychainQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                if let value = self.readAccountInternal(self.account) {
                    self.lock.lock()
                    self.memoryCookie = value
                    self.lock.unlock()
                    continuation.resume(returning: value)
                    return
                }
                
                // Migrate legacy Keychain item from CursorAppLogin era.
                if let legacy = self.readAccountInternal("CursorAppLogin") {
                    self.lock.lock()
                    self.memoryCookie = legacy
                    self.lock.unlock()
                    
                    // Save to new account and delete old (both on keychain queue already)
                    self.saveInternal(cookie: legacy)
                    self.deleteAccountInternal("CursorAppLogin")
                    continuation.resume(returning: legacy)
                    return
                }
                
                continuation.resume(returning: nil)
            }
        }
    }
    
    /// Internal keychain read, must be called from keychainQueue
    private func readAccountInternal(_ accountName: String) -> String? {
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
    
    /// Internal keychain save (update or add), must be called from keychainQueue
    private func saveInternal(cookie: String) {
        guard let data = cookie.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        
        // Try update first, fall back to add if item doesn't exist
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if status == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        
        if status != errSecSuccess {
            logger.error("Keychain save failed: \(status, privacy: .public)")
        }
    }

    func save(cookie: String) {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Check if cookie is already cached (skip keychain write if unchanged)
        lock.lock()
        let alreadyCached = memoryCookie == trimmed
        if !alreadyCached {
            memoryCookie = trimmed
        }
        lock.unlock()
        
        if alreadyCached {
            logger.debug("Keychain write skipped: cookie unchanged")
            return
        }
        
        // Write to keychain asynchronously on dedicated serial queue
        keychainQueue.async { [weak self] in
            guard let self else { return }
            guard let data = trimmed.data(using: .utf8) else { return }
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: self.service,
                kSecAttrAccount as String: self.account,
            ]
            
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            
            // Try update first, fall back to add if item doesn't exist
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            
            if status == errSecItemNotFound {
                // Item doesn't exist, add it
                var addQuery = query
                addQuery[kSecValueData as String] = data
                addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(addQuery as CFDictionary, nil)
            }
            
            if status == errSecSuccess {
                logger.info("Keychain write succeeded")
            } else {
                logger.error("Keychain write failed: \(status, privacy: .public)")
            }
        }
    }

    func clear() {
        lock.lock()
        memoryCookie = nil
        lock.unlock()
        
        // Delete from keychain asynchronously
        keychainQueue.async { [weak self] in
            guard let self else { return }
            self.deleteAccountInternal(self.account)
        }
    }
    
    /// Internal keychain delete, must be called from keychainQueue
    private func deleteAccountInternal(_ accountName: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
