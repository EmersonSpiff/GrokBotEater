import Foundation
@testable import GrokBotEaterApp

final class MockGrokBotAPIClient: GrokBotAPIClientProtocol {
    var fetchUsageResult: Result<GrokBotUsageResponse, Error>?
    var testConnectionResult: ConnectionTestResult?
    
    func fetchUsage(cookie: String) async throws -> GrokBotUsageResponse {
        guard let result = fetchUsageResult else {
            throw GrokBotAPIError.noCookie
        }
        return try result.get()
    }
    
    func testConnection(cookie: String) async -> ConnectionTestResult {
        testConnectionResult ?? ConnectionTestResult(success: false, message: "Not configured")
    }
}
