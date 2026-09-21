import Foundation
import SQLite3

/// Reads the `CursorAppLogin` cookie from Cursor/Chromium's cookie database.
/// Used for authenticating Grok Bot usage API calls.
final class CursorCookieReader: CursorCookieReaderProtocol, @unchecked Sendable {
    
    /// Known cookie database locations for Cursor/Chromium apps.
    /// Ordered by likelihood (Cursor, then Chromium fallback).
    private static let cookieDBPaths: [String] = [
        "Library/Application Support/Cursor/User Data/Default/Cookies",
        "Library/Application Support/Cursor/User Data/Profile 1/Cookies",
        "Library/Application Support/Google/Chrome/Default/Cookies",
        "Library/Application Support/Chromium/Default/Cookies"
    ]
    
    private var realHomeDirectory: String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }
    
    /// Read the `CursorAppLogin` cookie for `cursor.com` domain.
    /// Returns the cookie value if found and not expired.
    func readCookie() -> String? {
        let home = realHomeDirectory
        
        for relativePath in Self.cookieDBPaths {
            let fullPath = "\(home)/\(relativePath)"
            if let cookie = readCookieFromDB(path: fullPath) {
                return cookie
            }
        }
        
        return nil
    }
    
    /// Read cookie from a specific SQLite database path.
    /// Chromium cookie databases use encrypted_value in v10+ format.
    private func readCookieFromDB(path: String) -> String? {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        
        // Copy to temp location to avoid locking the live database
        let tempPath = NSTemporaryDirectory() + "cursor-cookies-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }
        
        do {
            try FileManager.default.copyItem(atPath: path, toPath: tempPath)
        } catch {
            return nil
        }
        
        // Open database
        var db: OpaquePointer?
        guard sqlite3_open_v2(tempPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }
        
        // Query for CursorAppLogin cookie for cursor.com domain
        let query = """
        SELECT value, encrypted_value, expires_utc 
        FROM cookies 
        WHERE name = 'CursorAppLogin' 
        AND (host_key = '.cursor.com' OR host_key = 'cursor.com')
        ORDER BY expires_utc DESC
        LIMIT 1
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        
        // Execute query
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        // Check expiry (Chromium stores as microseconds since Windows epoch: 1601-01-01)
        let expiresUtc = sqlite3_column_int64(statement, 2)
        let now = Date()
        let windowsEpoch = Date(timeIntervalSince1970: -11644473600) // 1601-01-01
        let expiryDate = windowsEpoch.addingTimeInterval(TimeInterval(expiresUtc) / 1_000_000)
        
        if expiryDate < now {
            // Cookie expired
            return nil
        }
        
        // Try plain value first (older Chromium versions)
        if let cString = sqlite3_column_text(statement, 0) {
            let value = String(cString: cString)
            if !value.isEmpty {
                return value
            }
        }
        
        // Try encrypted_value (v10+ format)
        // [Inference] Chromium cookie encryption on macOS typically uses Keychain
        // for the encryption key. Full decryption requires additional keychain calls
        // and is beyond the current scope. If the plain value is empty, we return nil
        // and document that the user should use a browser session where Cursor is logged in.
        
        return nil
    }
}
