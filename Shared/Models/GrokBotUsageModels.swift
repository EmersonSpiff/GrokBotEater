import Foundation

// MARK: - Grok Bot Usage Response

/// Response from `POST https://cursor.com/api/dashboard/get-sand-usage-status`.
/// Grok Bot weekly usage tracking for Cursor plans that include it.
struct GrokBotUsageResponse: Codable, Equatable {
    /// Usage as a percentage (0–100) of the included weekly limit.
    /// Absent when the limit is not readable. Do NOT treat absent as 0.
    let usagePercent: Double?
    
    /// Start of the current billing period (ISO 8601).
    let currentPeriodStart: String?
    
    /// End of the current weekly Grok Bot window (ISO 8601).
    let nextResetTimestampUtc: String?
    
    /// True when the plan uses pooled enterprise allowance (no personal ring).
    let usesPooledEnterpriseAllowance: Bool?
    
    /// True when the included limit is zero (plan doesn't include Grok Bot).
    let includedLimitZero: Bool?
    
    /// True when there is a non-zero included limit.
    let hasNonZeroIncludedLimit: Bool?
    
    enum CodingKeys: String, CodingKey {
        case usagePercent = "usagePercent"
        case currentPeriodStart = "currentPeriodStart"
        case nextResetTimestampUtc = "nextResetTimestampUtc"
        case usesPooledEnterpriseAllowance = "usesPooledEnterpriseAllowance"
        case includedLimitZero = "includedLimitZero"
        case hasNonZeroIncludedLimit = "hasNonZeroIncludedLimit"
    }
    
    /// Determine if we should draw a usage ring for this response.
    /// Ring is shown only when:
    /// - usagePercent is present
    /// - hasNonZeroIncludedLimit is true
    /// - includedLimitZero is not true
    /// - usesPooledEnterpriseAllowance is not true
    var shouldDrawRing: Bool {
        guard let _ = usagePercent else { return false }
        guard hasNonZeroIncludedLimit == true else { return false }
        guard includedLimitZero != true else { return false }
        guard usesPooledEnterpriseAllowance != true else { return false }
        return true
    }
    
    /// Usage percentage as a whole number (0-100). Returns 0 when absent.
    var usagePercentInt: Int {
        guard let percent = usagePercent else { return 0 }
        return Int(percent.rounded())
    }
}

// MARK: - Cached Grok Bot Usage (for offline support)

struct CachedGrokBotUsage: Codable {
    let usage: GrokBotUsageResponse
    let fetchDate: Date
}
