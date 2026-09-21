import Foundation

final class GrokBotAPIClient: GrokBotAPIClientProtocol, @unchecked Sendable {
    private let sandUsageURL = URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!
    
    private func session() -> URLSession {
        .shared
    }
    
    private func makeRequest(cookie: String) -> URLRequest {
        var request = URLRequest(url: sandUsageURL)
        request.httpMethod = "POST"
        request.httpBody = "{}".data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        let cookieHeader: String
        if cookie.hasPrefix("WorkosCursorSessionToken=") || cookie.hasPrefix("CursorAppLogin=") {
            cookieHeader = cookie
        } else {
            cookieHeader = "WorkosCursorSessionToken=\(cookie)"
        }
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        return request
    }
    
    func fetchUsage(cookie: String) async throws -> GrokBotUsageResponse {
        let request = makeRequest(cookie: cookie)
        let endpoint = sandUsageURL.path
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await session().data(for: request)
        } catch {
            throw GrokBotAPIError.networkError(endpoint: endpoint, underlying: error.localizedDescription)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokBotAPIError.invalidResponse(endpoint: endpoint)
        }
        
        switch httpResponse.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(GrokBotUsageResponse.self, from: data)
            } catch {
                throw GrokBotAPIError.invalidResponse(endpoint: endpoint)
            }
        case 401, 403:
            throw GrokBotAPIError.cookieExpired(endpoint: endpoint, statusCode: httpResponse.statusCode)
        case 429:
            let retryAfterRaw = httpResponse.value(forHTTPHeaderField: "Retry-After")
            let retryAfter = retryAfterRaw.flatMap(TimeInterval.init)
            throw GrokBotAPIError.rateLimited(retryAfter: retryAfter, retryAfterRaw: retryAfterRaw, endpoint: endpoint)
        default:
            throw GrokBotAPIError.httpError(statusCode: httpResponse.statusCode, endpoint: endpoint)
        }
    }
    
    func testConnection(cookie: String) async -> ConnectionTestResult {
        let request = makeRequest(cookie: cookie)
        
        do {
            let (data, response) = try await session().data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ConnectionTestResult(success: false, message: "Invalid response")
            }
            
            if httpResponse.statusCode == 200 {
                guard let usage = try? JSONDecoder().decode(GrokBotUsageResponse.self, from: data) else {
                    return ConnectionTestResult(success: false, message: "Invalid response format")
                }
                let pct = usage.usagePercentInt
                return ConnectionTestResult(success: true, message: "Grok Bot usage: \(pct)% used")
            } else if httpResponse.statusCode == 429 {
                return ConnectionTestResult(success: true, message: "Rate limited (cookie valid)")
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return ConnectionTestResult(success: false, message: "Cookie expired or invalid (HTTP \(httpResponse.statusCode))")
            } else {
                return ConnectionTestResult(success: false, message: "HTTP \(httpResponse.statusCode)")
            }
        } catch {
            return ConnectionTestResult(success: false, message: "Network error: \(error.localizedDescription)")
        }
    }
}
