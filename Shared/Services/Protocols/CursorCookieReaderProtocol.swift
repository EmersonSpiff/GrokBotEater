import Foundation

protocol CursorCookieReaderProtocol: Sendable {
    /// Read the `CursorAppLogin` cookie for authenticating with Cursor's Grok Bot API.
    /// Returns the cookie value if found and not expired, nil otherwise.
    /// Synchronous: returns cached value or scrapes disk. Does NOT hit Keychain.
    func readCookie() -> String?
    
    /// Async version: loads from Keychain on background thread, then falls back to disk scrape.
    /// Call this once at app launch to populate the cache without blocking the main thread.
    func readCookieAsync() async -> String?
}
