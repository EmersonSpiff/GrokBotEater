import Foundation
import SQLite3

/// Reads the `CursorAppLogin` cookie for Grok Bot API auth.
/// Priority: Keychain web-login session → Chromium/Cursor cookie DB scrape.
final class CursorCookieReader: CursorCookieReaderProtocol, @unchecked Sendable {

    /// Static relative paths under the real home directory.
    private static let cookieDBPaths: [String] = [
        // Top-level Cursor Cookies DB (Electron / newer layouts)
        "Library/Application Support/Cursor/Cookies",
        // Classic Chromium profile paths
        "Library/Application Support/Cursor/User Data/Default/Cookies",
        "Library/Application Support/Cursor/User Data/Profile 1/Cookies",
        "Library/Application Support/Google/Chrome/Default/Cookies",
        "Library/Application Support/Chromium/Default/Cookies",
    ]

    private let sessionStore: GrokBotSessionStore

    init(sessionStore: GrokBotSessionStore = .shared) {
        self.sessionStore = sessionStore
    }

    private var realHomeDirectory: String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }

    /// Prefer the Keychain web session, then fall back to disk scrape.
    func readCookie() -> String? {
        if let saved = sessionStore.savedCookie() {
            return saved
        }
        return scrapeCookieFromDisk()
    }

    /// Disk scrape only (ignores Keychain). Useful for diagnostics.
    func scrapeCookieFromDisk() -> String? {
        let home = realHomeDirectory
        let fm = FileManager.default

        for relativePath in Self.cookieDBPaths {
            let fullPath = "\(home)/\(relativePath)"
            if let cookie = readCookieFromDB(path: fullPath) {
                return cookie
            }
        }

        // Partitioned Chromium profiles: .../Cursor/Partitions/*/Cookies
        let partitionsRoot = "\(home)/Library/Application Support/Cursor/Partitions"
        if let contents = try? fm.contentsOfDirectory(atPath: partitionsRoot) {
            for name in contents.sorted() {
                let candidate = "\(partitionsRoot)/\(name)/Cookies"
                if let cookie = readCookieFromDB(path: candidate) {
                    return cookie
                }
            }
        }

        // Also scan User Data/* /Cookies for other profiles
        let userDataRoot = "\(home)/Library/Application Support/Cursor/User Data"
        if let contents = try? fm.contentsOfDirectory(atPath: userDataRoot) {
            for name in contents.sorted() where name != "Default" && name != "Profile 1" {
                let candidate = "\(userDataRoot)/\(name)/Cookies"
                if fm.fileExists(atPath: candidate),
                   let cookie = readCookieFromDB(path: candidate) {
                    return cookie
                }
            }
        }

        return nil
    }

    /// Read cookie from a specific SQLite database path.
    private func readCookieFromDB(path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let tempPath = NSTemporaryDirectory() + "cursor-cookies-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        do {
            try FileManager.default.copyItem(atPath: path, toPath: tempPath)
        } catch {
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }

        let query = """
        SELECT value, encrypted_value, expires_utc
        FROM cookies
        WHERE name = 'CursorAppLogin'
        AND (host_key = '.cursor.com' OR host_key = 'cursor.com' OR host_key LIKE '%.cursor.com')
        ORDER BY expires_utc DESC
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let expiresUtc = sqlite3_column_int64(statement, 2)
        // Session cookies may have expires_utc == 0; treat those as valid.
        if expiresUtc > 0 {
            let now = Date()
            let windowsEpoch = Date(timeIntervalSince1970: -11644473600)
            let expiryDate = windowsEpoch.addingTimeInterval(TimeInterval(expiresUtc) / 1_000_000)
            if expiryDate < now {
                return nil
            }
        }

        if let cString = sqlite3_column_text(statement, 0) {
            let value = String(cString: cString)
            if !value.isEmpty {
                return value
            }
        }

        // Encrypted v10+ values are not decrypted here; web login is the primary path.
        return nil
    }
}
