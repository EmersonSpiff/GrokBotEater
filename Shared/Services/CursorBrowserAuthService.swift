import Foundation
import CryptoKit

/// Browser-based PKCE authentication for Cursor following the loginDeepControl flow.
/// Generates a challenge/verifier pair, opens the browser, and polls for tokens.
final class CursorBrowserAuthService: @unchecked Sendable {
    
    struct AuthTokens {
        let accessToken: String
        let refreshToken: String
    }
    
    enum AuthError: Error, LocalizedError {
        case cancelled
        case timeout
        case networkError(String)
        case invalidResponse
        case authenticationFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .cancelled:
                return String(localized: "onboarding.browser.auth.error.cancelled")
            case .timeout:
                return String(localized: "onboarding.browser.auth.error.timeout")
            case .networkError(let message):
                return String(localized: "onboarding.browser.auth.error.network.\(message)")
            case .invalidResponse:
                return String(localized: "onboarding.browser.auth.error.invalid")
            case .authenticationFailed(let message):
                return message
            }
        }
    }
    
    private static let websiteURL = "https://cursor.com"
    private static let backendURL = "https://api2.cursor.sh"
    private static let pollInterval: TimeInterval = 2.0
    private static let timeout: TimeInterval = 300.0 // 5 minutes
    
    /// Generates a PKCE verifier and challenge pair.
    /// The verifier is a random 32-byte base64url string.
    /// The challenge is base64url(SHA-256(verifier)).
    private static func generatePKCE() -> (verifier: String, challenge: String) {
        var randomBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        
        let verifier = Data(randomBytes).base64URLEncodedString()
        let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
        let challenge = challengeData.base64URLEncodedString()
        
        return (verifier, challenge)
    }
    
    /// Creates the browser login URL with the PKCE challenge.
    static func createLoginURL() -> (url: URL, uuid: String, verifier: String)? {
        let (verifier, challenge) = generatePKCE()
        let uuid = UUID().uuidString.lowercased()
        
        guard var components = URLComponents(string: "\(websiteURL)/loginDeepControl") else {
            return nil
        }
        
        components.queryItems = [
            URLQueryItem(name: "challenge", value: challenge),
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "mode", value: "login"),
            URLQueryItem(name: "redirectTarget", value: "sand"),
            URLQueryItem(name: "supportsSelectedTeamLogin", value: "true"),
        ]
        
        guard let url = components.url else { return nil }
        return (url, uuid, verifier)
    }
    
    /// Polls the auth endpoint until tokens are received or timeout occurs.
    /// Returns nil if the user hasn't completed authentication yet (404).
    private static func pollOnce(uuid: String, verifier: String) async throws -> AuthTokens? {
        guard var components = URLComponents(string: "\(backendURL)/auth/poll") else {
            throw AuthError.invalidResponse
        }
        
        components.queryItems = [
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "verifier", value: verifier),
        ]
        
        guard let url = components.url else {
            throw AuthError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Network errors don't abort the flow, just return nil to retry
            if error is CancellationError { throw AuthError.cancelled }
            return nil
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }
        
        // 404 means authentication is still pending
        if httpResponse.statusCode == 404 {
            return nil
        }
        
        // 403 with error message means authentication was refused
        if httpResponse.statusCode == 403 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = json["error"] as? String {
                throw AuthError.authenticationFailed(errorMessage)
            }
            throw AuthError.authenticationFailed("Authentication refused")
        }
        
        // 200 means success - parse the tokens
        guard httpResponse.statusCode == 200 else {
            return nil
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["accessToken"] as? String,
              let refreshToken = json["refreshToken"] as? String else {
            throw AuthError.invalidResponse
        }
        
        return AuthTokens(accessToken: accessToken, refreshToken: refreshToken)
    }
    
    /// Polls for authentication completion with exponential backoff.
    /// Continues until tokens are received, timeout occurs, or cancellation.
    static func pollForTokens(
        uuid: String,
        verifier: String,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> AuthTokens {
        let deadline = Date().addingTimeInterval(timeout)
        var attempt = 0
        
        while Date() < deadline {
            try Task.checkCancellation()
            
            attempt += 1
            onProgress?(String(localized: "onboarding.browser.auth.polling.\(attempt)"))
            
            if let tokens = try await pollOnce(uuid: uuid, verifier: verifier) {
                return tokens
            }
            
            // Wait before next poll
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        
        throw AuthError.timeout
    }
    
    /// Converts Cursor access/refresh tokens to a WorkosCursorSessionToken cookie value.
    /// The access token itself is the cookie value used by the Grok Bot API.
    static func convertToSessionCookie(tokens: AuthTokens) -> String {
        // The accessToken is what we use as the session cookie value
        return tokens.accessToken
    }
}

// MARK: - Data Extensions for Base64URL

private extension Data {
    /// Base64URL encoding (RFC 4648 Section 5) without padding.
    func base64URLEncodedString() -> String {
        let base64 = self.base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
