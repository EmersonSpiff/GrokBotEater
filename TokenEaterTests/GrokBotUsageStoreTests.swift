import Testing
import Foundation
@testable import GrokBotEaterApp

@Suite("Grok Bot Usage Store", .serialized)
@MainActor
struct GrokBotUsageStoreTests {
    
    @Test("Initial state is not connected")
    func initialState() {
        let mockClient = MockGrokBotAPIClient()
        let mockCookieReader = MockCursorCookieReader()
        let store = GrokBotUsageStore(
            apiClient: mockClient,
            cookieReader: mockCookieReader
        )
        
        #expect(store.usagePercent == 0)
        #expect(store.hasGrokBot == false)
        #expect(store.shouldShowRing == false)
        #expect(store.errorState == .none)
        #expect(store.statusMessage == "Not connected")
    }
    
    @Test("Refresh succeeds with valid ring-drawable response")
    func refreshSuccessWithRing() async {
        let mockClient = MockGrokBotAPIClient()
        let mockCookieReader = MockCursorCookieReader()
        mockCookieReader.cookieToReturn = "valid-session-cookie"
        
        let response = GrokBotUsageResponse(
            usagePercent: 42.5,
            currentPeriodStart: nil,
            usesPooledEnterpriseAllowance: false,
            includedLimitZero: false,
            hasNonZeroIncludedLimit: true
        )
        mockClient.fetchUsageResult = .success(response)
        
        let store = GrokBotUsageStore(
            apiClient: mockClient,
            cookieReader: mockCookieReader
        )
        
        await store.refresh(force: true)
        
        #expect(store.usagePercent == 43)
        #expect(store.hasGrokBot == true)
        #expect(store.shouldShowRing == true)
        #expect(store.errorState == .none)
        #expect(store.statusMessage == "Grok Bot: 43% used")
        #expect(store.lastUpdate != nil)
    }
    
    @Test("Refresh with pooled enterprise shows no ring")
    func refreshPooledEnterprise() async {
        let mockClient = MockGrokBotAPIClient()
        let mockCookieReader = MockCursorCookieReader()
        mockCookieReader.cookieToReturn = "valid-session-cookie"
        
        let response = GrokBotUsageResponse(
            usagePercent: 50.0,
            currentPeriodStart: nil,
            usesPooledEnterpriseAllowance: true,
            includedLimitZero: false,
            hasNonZeroIncludedLimit: true
        )
        mockClient.fetchUsageResult = .success(response)
        
        let store = GrokBotUsageStore(
            apiClient: mockClient,
            cookieReader: mockCookieReader
        )
        
        await store.refresh(force: true)
        
        #expect(store.usagePercent == 50)
        #expect(store.hasGrokBot == false)
        #expect(store.shouldShowRing == false)
        #expect(store.statusMessage == "Grok Bot: Enterprise pooled (no personal ring)")
    }
    
    @Test("Refresh with zero included limit shows not included")
    func refreshIncludedLimitZero() async {
        let mockClient = MockGrokBotAPIClient()
        let mockCookieReader = MockCursorCookieReader()
        mockCookieReader.cookieToReturn = "valid-session-cookie"
        
        let response = GrokBotUsageResponse(
            usagePercent: nil,
            currentPeriodStart: nil,
            usesPooledEnterpriseAllowance: false,
            includedLimitZero: true,
            hasNonZeroIncludedLimit: false
        )
        mockClient.fetchUsageResult = .success(response)
        
        let store = GrokBotUsageStore(
            apiClient: mockClient,
            cookieReader: mockCookieReader
        )
        
        await store.refresh(force: true)
        
        #expect(store.hasGrokBot == false)
        #expect(store.shouldShowRing == false)
        #expect(store.statusMessage == "Grok Bot: Not included in plan")
    }
    
    @Test("Refresh fails when cookie unavailable")
    func refreshNoCookie() async {
        let mockClient = MockGrokBotAPIClient()
        let mockCookieReader = MockCursorCookieReader()
        mockCookieReader.cookieToReturn = nil
        
        let store = GrokBotUsageStore(
            apiClient: mockClient,
            cookieReader: mockCookieReader
        )
        
        await store.refresh(force: true)
        
        #expect(store.hasGrokBot == false)
        #expect(store.shouldShowRing == false)
        #expect(store.errorState == .cookieUnavailable)
        #expect(store.statusMessage == "Cursor session not found. Log in to cursor.com")
    }
    
    @Test("Refresh handles cookie expired error")
    func refreshCookieExpired() async {
        let mockClient = MockGrokBotAPIClient()
        let mockCookieReader = MockCursorCookieReader()
        mockCookieReader.cookieToReturn = "expired-cookie"
        mockClient.fetchUsageResult = .failure(
            GrokBotAPIError.cookieExpired(endpoint: "/test", statusCode: 401)
        )
        
        let store = GrokBotUsageStore(
            apiClient: mockClient,
            cookieReader: mockCookieReader
        )
        
        await store.refresh(force: true)
        
        #expect(store.hasGrokBot == false)
        #expect(store.shouldShowRing == false)
        #expect(store.errorState == .cookieExpired)
        #expect(store.statusMessage == "Cursor session expired. Log in again at cursor.com")
    }
    
    @Test("Refresh handles rate limit error")
    func refreshRateLimited() async {
        let mockClient = MockGrokBotAPIClient()
        let mockCookieReader = MockCursorCookieReader()
        mockCookieReader.cookieToReturn = "valid-cookie"
        mockClient.fetchUsageResult = .failure(
            GrokBotAPIError.rateLimited(retryAfter: 60, retryAfterRaw: "60", endpoint: "/test")
        )
        
        let store = GrokBotUsageStore(
            apiClient: mockClient,
            cookieReader: mockCookieReader
        )
        
        await store.refresh(force: true)
        
        #expect(store.errorState == .rateLimited)
        #expect(store.statusMessage == "Rate limited by Grok Bot API")
    }
    
    @Test("Test connection returns success when cookie valid")
    func testConnectionSuccess() async {
        let mockClient = MockGrokBotAPIClient()
        let mockCookieReader = MockCursorCookieReader()
        mockCookieReader.cookieToReturn = "valid-cookie"
        mockClient.testConnectionResult = ConnectionTestResult(
            success: true,
            message: "Grok Bot usage: 42% used"
        )
        
        let store = GrokBotUsageStore(
            apiClient: mockClient,
            cookieReader: mockCookieReader
        )
        
        let result = await store.testConnection()
        
        #expect(result.success == true)
        #expect(result.message == "Grok Bot usage: 42% used")
    }
    
    @Test("Test connection returns failure when no cookie")
    func testConnectionNoCookie() async {
        let mockClient = MockGrokBotAPIClient()
        let mockCookieReader = MockCursorCookieReader()
        mockCookieReader.cookieToReturn = nil
        
        let store = GrokBotUsageStore(
            apiClient: mockClient,
            cookieReader: mockCookieReader
        )
        
        let result = await store.testConnection()
        
        #expect(result.success == false)
        #expect(result.message.contains("cookie not found"))
    }
}
