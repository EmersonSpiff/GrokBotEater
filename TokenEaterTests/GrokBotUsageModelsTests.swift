import Testing
import Foundation
@testable import GrokBotEaterApp

@Suite("Grok Bot Usage Models")
struct GrokBotUsageModelsTests {
    
    @Test("Decode valid response with all fields")
    func decodeValidResponse() throws {
        let json = """
        {
            "usagePercent": 42.5,
            "currentPeriodStart": "2026-09-15T00:00:00Z",
            "usesPooledEnterpriseAllowance": false,
            "includedLimitZero": false,
            "hasNonZeroIncludedLimit": true
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(GrokBotUsageResponse.self, from: data)
        
        #expect(response.usagePercent == 42.5)
        #expect(response.currentPeriodStart == "2026-09-15T00:00:00Z")
        #expect(response.usesPooledEnterpriseAllowance == false)
        #expect(response.includedLimitZero == false)
        #expect(response.hasNonZeroIncludedLimit == true)
        #expect(response.usagePercentInt == 43)
    }
    
    @Test("Decode response with missing usagePercent")
    func decodeMissingUsagePercent() throws {
        let json = """
        {
            "hasNonZeroIncludedLimit": false
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(GrokBotUsageResponse.self, from: data)
        
        #expect(response.usagePercent == nil)
        #expect(response.usagePercentInt == 0)
    }
    
    @Test("Ring gating: should draw ring when conditions met")
    func shouldDrawRingWhenValid() throws {
        let response = GrokBotUsageResponse(
            usagePercent: 50.0,
            currentPeriodStart: nil,
            usesPooledEnterpriseAllowance: false,
            includedLimitZero: false,
            hasNonZeroIncludedLimit: true
        )
        
        #expect(response.shouldDrawRing == true)
    }
    
    @Test("Ring gating: no ring when usagePercent absent")
    func noRingWhenUsagePercentAbsent() throws {
        let response = GrokBotUsageResponse(
            usagePercent: nil,
            currentPeriodStart: nil,
            usesPooledEnterpriseAllowance: false,
            includedLimitZero: false,
            hasNonZeroIncludedLimit: true
        )
        
        #expect(response.shouldDrawRing == false)
    }
    
    @Test("Ring gating: no ring when pooled enterprise allowance")
    func noRingWhenPooledEnterprise() throws {
        let response = GrokBotUsageResponse(
            usagePercent: 50.0,
            currentPeriodStart: nil,
            usesPooledEnterpriseAllowance: true,
            includedLimitZero: false,
            hasNonZeroIncludedLimit: true
        )
        
        #expect(response.shouldDrawRing == false)
    }
    
    @Test("Ring gating: no ring when included limit is zero")
    func noRingWhenIncludedLimitZero() throws {
        let response = GrokBotUsageResponse(
            usagePercent: 50.0,
            currentPeriodStart: nil,
            usesPooledEnterpriseAllowance: false,
            includedLimitZero: true,
            hasNonZeroIncludedLimit: false
        )
        
        #expect(response.shouldDrawRing == false)
    }
    
    @Test("Ring gating: no ring when hasNonZeroIncludedLimit is false")
    func noRingWhenNoIncludedLimit() throws {
        let response = GrokBotUsageResponse(
            usagePercent: 50.0,
            currentPeriodStart: nil,
            usesPooledEnterpriseAllowance: false,
            includedLimitZero: false,
            hasNonZeroIncludedLimit: false
        )
        
        #expect(response.shouldDrawRing == false)
    }
    
    @Test("Ring gating: no ring when hasNonZeroIncludedLimit is nil")
    func noRingWhenIncludedLimitNil() throws {
        let response = GrokBotUsageResponse(
            usagePercent: 50.0,
            currentPeriodStart: nil,
            usesPooledEnterpriseAllowance: false,
            includedLimitZero: false,
            hasNonZeroIncludedLimit: nil
        )
        
        #expect(response.shouldDrawRing == false)
    }
    
    @Test("Usage percent rounding")
    func usagePercentRounding() throws {
        let response1 = GrokBotUsageResponse(
            usagePercent: 42.4,
            currentPeriodStart: nil,
            usesPooledEnterpriseAllowance: false,
            includedLimitZero: false,
            hasNonZeroIncludedLimit: true
        )
        #expect(response1.usagePercentInt == 42)
        
        let response2 = GrokBotUsageResponse(
            usagePercent: 42.5,
            currentPeriodStart: nil,
            usesPooledEnterpriseAllowance: false,
            includedLimitZero: false,
            hasNonZeroIncludedLimit: true
        )
        #expect(response2.usagePercentInt == 43)
        
        let response3 = GrokBotUsageResponse(
            usagePercent: 99.9,
            currentPeriodStart: nil,
            usesPooledEnterpriseAllowance: false,
            includedLimitZero: false,
            hasNonZeroIncludedLimit: true
        )
        #expect(response3.usagePercentInt == 100)
    }
    
    @Test("Cached Grok Bot usage encoding/decoding")
    func cachedUsageEncodingDecoding() throws {
        let usage = GrokBotUsageResponse(
            usagePercent: 75.0,
            currentPeriodStart: "2026-09-15T00:00:00Z",
            usesPooledEnterpriseAllowance: false,
            includedLimitZero: false,
            hasNonZeroIncludedLimit: true
        )
        let cached = CachedGrokBotUsage(usage: usage, fetchDate: Date())
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(cached)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CachedGrokBotUsage.self, from: data)
        
        #expect(decoded.usage.usagePercent == 75.0)
        #expect(decoded.usage.currentPeriodStart == "2026-09-15T00:00:00Z")
    }
}
