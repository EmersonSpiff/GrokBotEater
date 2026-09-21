import Testing
import Foundation
@testable import GrokBotEaterApp

@Suite("Grok Bot shared snapshot")
struct GrokBotSharedSnapshotTests {

    @Test("snapshot init from response copies ring gates")
    func initFromResponse() {
        let response = GrokBotUsageResponse(
            usagePercent: 37.4,
            currentPeriodStart: "2026-09-15T00:00:00.000Z",
            usesPooledEnterpriseAllowance: false,
            includedLimitZero: false,
            hasNonZeroIncludedLimit: true
        )
        let snapshot = GrokBotSharedSnapshot(
            response: response,
            syncDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(snapshot.usagePercent == 37)
        #expect(snapshot.shouldDrawRing == true)
        #expect(snapshot.hasGrokBot == true)
        #expect(snapshot.currentPeriodStart == "2026-09-15T00:00:00.000Z")
    }

    @Test("store refresh writes snapshot to shared file")
    @MainActor
    func storeWritesSnapshot() async {
        let mockAPI = MockGrokBotAPIClient()
        mockAPI.fetchUsageResult = .success(
            GrokBotUsageResponse(
                usagePercent: 55,
                currentPeriodStart: nil,
                usesPooledEnterpriseAllowance: false,
                includedLimitZero: false,
                hasNonZeroIncludedLimit: true
            )
        )
        let mockCookie = MockCursorCookieReader()
        mockCookie.cookieToReturn = "test-cookie"
        let mockShared = MockSharedFileService()
        let store = GrokBotUsageStore(
            apiClient: mockAPI,
            cookieReader: mockCookie,
            sharedFileService: mockShared
        )
        await store.refresh(force: true)
        #expect(mockShared.updateGrokBotSnapshotCallCount == 1)
        #expect(mockShared.grokBotSnapshot?.usagePercent == 55)
        #expect(mockShared.grokBotSnapshot?.shouldDrawRing == true)
    }
}
