import Testing
import Foundation

private let settingsKeys = ["overlayEnabled", "hasCompletedOnboarding"]

private func cleanDefaults() {
    for key in settingsKeys {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private func sampleUsage(
    percent: Double? = 42,
    hasLimit: Bool? = true
) -> GrokBotUsageResponse {
    GrokBotUsageResponse(
        usagePercent: percent,
        currentPeriodStart: nil,
        usesPooledEnterpriseAllowance: false,
        includedLimitZero: false,
        hasNonZeroIncludedLimit: hasLimit
    )
}

@Suite("OnboardingViewModel", .serialized)
@MainActor
struct OnboardingViewModelTests {

    private func makeViewModel(
        cookieReader: CursorCookieReaderProtocol = MockCursorCookieReader(),
        grokBotAPI: GrokBotAPIClientProtocol = MockGrokBotAPIClient(),
        notificationService: NotificationServiceProtocol = MockNotificationService()
    ) -> OnboardingViewModel {
        cleanDefaults()
        return OnboardingViewModel(
            cookieReader: cookieReader,
            grokBotAPI: grokBotAPI,
            notificationService: notificationService
        )
    }

    @Test("canFinish is false when both gates are pending")
    func gatingBothPending() {
        let vm = makeViewModel()
        vm.grokBotStatus = .checking
        vm.connectionStatus = .idle
        #expect(vm.canFinish == false)
    }

    @Test("canFinish is false when only Grok Bot session is detected")
    func gatingOnlyGrokBot() {
        let vm = makeViewModel()
        vm.grokBotStatus = .detected
        vm.connectionStatus = .idle
        #expect(vm.canFinish == false)
    }

    @Test("canFinish is false when only Connect succeeded")
    func gatingOnlyConnect() {
        let vm = makeViewModel()
        vm.grokBotStatus = .notFound
        vm.connectionStatus = .success(sampleUsage())
        #expect(vm.canFinish == false)
    }

    @Test("canFinish is true when Grok Bot session detected + Connect success")
    func gatingBothSuccess() {
        let vm = makeViewModel()
        vm.grokBotStatus = .detected
        vm.connectionStatus = .success(sampleUsage())
        #expect(vm.canFinish == true)
    }

    @Test("canFinish is true when Grok Bot session detected + Connect rateLimited")
    func gatingRateLimitedCountsAsConnected() {
        let vm = makeViewModel()
        vm.grokBotStatus = .detected
        vm.connectionStatus = .rateLimited
        #expect(vm.canFinish == true)
    }

    @Test("canFinish is false when Connect failed")
    func gatingFailedDoesNotCount() {
        let vm = makeViewModel()
        vm.grokBotStatus = .detected
        vm.connectionStatus = .failed("nope")
        #expect(vm.canFinish == false)
    }

    @Test("readyCount counts 3-card grid (session, connect, notifications)")
    func readyCountSemantics() {
        let vm = makeViewModel()
        vm.grokBotStatus = .detected
        vm.connectionStatus = .idle
        vm.notificationStatus = .authorized
        // grokBot + notifications = 2 ready out of 3
        #expect(vm.readyCount == 2)
        #expect(vm.totalSteps == 3)
    }
}
