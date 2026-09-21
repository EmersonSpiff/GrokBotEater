import Foundation

enum GrokBotAPIError: LocalizedError {
    case noCookie
    case invalidResponse(endpoint: String)
    case cookieExpired(endpoint: String, statusCode: Int)
    case rateLimited(retryAfter: TimeInterval?, retryAfterRaw: String?, endpoint: String)
    case httpError(statusCode: Int, endpoint: String)
    case networkError(endpoint: String, underlying: String)
    
    var errorDescription: String? {
        switch self {
        case .noCookie:
            return "Cursor cookie not found. Please log in to Cursor at cursor.com"
        case .invalidResponse:
            return "Invalid response from Grok Bot API"
        case .cookieExpired:
            return "Cursor session expired. Please log in again"
        case .rateLimited:
            return "Rate limited by Grok Bot API"
        case .httpError(let code, _):
            return "HTTP error \(code) from Grok Bot API"
        case .networkError(_, let underlying):
            return "Network error: \(underlying)"
        }
    }
}

protocol GrokBotAPIClientProtocol: Sendable {
    func fetchUsage(cookie: String) async throws -> GrokBotUsageResponse
    func testConnection(cookie: String) async -> ConnectionTestResult
}
