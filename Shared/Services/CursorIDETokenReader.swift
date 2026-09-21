import Foundation
import SQLite3
import os.log

private let logger = Logger(subsystem: "com.emersonspiff.grokboteater.app", category: "CursorIDETokenReader")

/// Builds a `WorkosCursorSessionToken` cookie value from Cursor IDE's
/// `cursorAuth/accessToken` in globalStorage/state.vscdb.
enum CursorIDETokenReader {
    static func sessionCookieValue() -> String? {
        let home: String = {
            guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
            return String(cString: pw.pointee.pw_dir)
        }()
        let path = "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        var db: OpaquePointer?
        let uri = "file:\(path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        guard let cString = sqlite3_column_text(statement, 0) else { return nil }
        let token = String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        return cookieValue(fromJWT: token)
    }

    /// `{userId}%3A%3A{jwt}` where userId is the segment after `|` in `sub`.
    static func cookieValue(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - payload.count % 4) % 4
        if pad > 0 { payload += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String,
              let userId = sub.split(separator: "|").last.map(String.init),
              !userId.isEmpty
        else {
            logger.error("Failed to parse Cursor JWT sub claim")
            return nil
        }
        return "\(userId)%3A%3A\(token)"
    }
}
