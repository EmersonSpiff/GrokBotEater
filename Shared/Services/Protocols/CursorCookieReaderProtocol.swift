import Foundation

protocol CursorCookieReaderProtocol: Sendable {
    /// Read the `CursorAppLogin` cookie for authenticating with Cursor's Grok Bot API.
    /// Returns the cookie value if found and not expired, nil otherwise.
    func readCookie() -> String?
}
