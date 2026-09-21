import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.emersonspiff.grokboteater.app", category: "GrokBotUsageStore")

@MainActor
final class GrokBotUsageStore: ObservableObject {
    @Published var usagePercent: Int = 0
    @Published var lastUpdate: Date?
    @Published var isLoading = false
    @Published var errorState: GrokBotErrorState = .none
    @Published var hasGrokBot = false
    
    /// True when the plan includes Grok Bot and we should draw a ring.
    /// Respects shouldDrawRing from the API response.
    @Published var shouldShowRing = false
    
    /// Human-readable status for onboarding/settings
    @Published var statusMessage: String = "Not connected"
    
    private(set) var lastResponse: GrokBotUsageResponse?
    private let apiClient: GrokBotAPIClientProtocol
    private let cookieReader: CursorCookieReaderProtocol
    private let sharedFileService: SharedFileServiceProtocol
    
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    

    /// Parsed `nextResetTimestampUtc` from the last successful response.
    var nextResetDate: Date? {
        guard let raw = lastResponse?.nextResetTimestampUtc else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    var refreshIntervalSeconds: TimeInterval = 300 // 5 minutes
    
    init(
        apiClient: GrokBotAPIClientProtocol = GrokBotAPIClient(),
        cookieReader: CursorCookieReaderProtocol = CursorCookieReader(),
        sharedFileService: SharedFileServiceProtocol = SharedFileService()
    ) {
        self.apiClient = apiClient
        self.cookieReader = cookieReader
        self.sharedFileService = sharedFileService
        
        loadCached()
    }
    
    private func loadCached() {
        // For now, no Grok Bot caching to shared file yet
        // Will add in a follow-up when SharedFileService extends to multi-provider
    }
    
    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        
        // Interval check
        if !force, let last = lastUpdate,
           Date().timeIntervalSince(last) < refreshIntervalSeconds {
            return
        }
        
        // Read cookie
        guard let cookie = cookieReader.readCookie() else {
            errorState = .cookieUnavailable
            statusMessage = "Cursor session not found. Log in to cursor.com"
            hasGrokBot = false
            shouldShowRing = false
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response = try await apiClient.fetchUsage(cookie: cookie)
            applySuccess(response: response)
        } catch let error as GrokBotAPIError {
            handleError(error)
        } catch {
            errorState = .networkError
            statusMessage = "Network error: \(error.localizedDescription)"
        }
    }
    
    func reloadConfig() {
        let hasCookie = cookieReader.readCookie() != nil
        if !hasCookie {
            errorState = .cookieUnavailable
            statusMessage = "Cursor session not found"
        }
        
        refreshTask?.cancel()
        refreshTask = Task {
            await refresh(force: true)
        }
    }
    
    func startAutoRefresh(interval: TimeInterval = 300) {
        refreshIntervalSeconds = interval
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            // Wait first - reloadConfig already triggers an initial refresh
            try? await Task.sleep(for: .seconds(interval))
            
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(force: false)
                let delay = self.refreshIntervalSeconds
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }
    
    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
    }
    
    func testConnection() async -> ConnectionTestResult {
        guard let cookie = cookieReader.readCookie() else {
            return ConnectionTestResult(
                success: false,
                message: "Cursor session cookie not found. Log in to cursor.com"
            )
        }
        
        return await apiClient.testConnection(cookie: cookie)
    }
    
    private func applySuccess(response: GrokBotUsageResponse) {
        lastResponse = response
        usagePercent = response.usagePercentInt
        shouldShowRing = response.shouldDrawRing
        hasGrokBot = response.shouldDrawRing // Only show as "has" if we can draw a ring
        lastUpdate = Date()
        errorState = .none
        
        if response.shouldDrawRing {
            statusMessage = "Grok Bot: \(usagePercent)% used"
        } else if response.usesPooledEnterpriseAllowance == true {
            statusMessage = "Grok Bot: Enterprise pooled (no personal ring)"
        } else if response.includedLimitZero == true {
            statusMessage = "Grok Bot: Not included in plan"
        } else if response.hasNonZeroIncludedLimit == false {
            statusMessage = "Grok Bot: No included limit"
        } else {
            statusMessage = "Grok Bot: Usage data unavailable"
        }
        
        logger.info("Grok Bot refresh succeeded: \(self.usagePercent)% used, shouldDrawRing=\(self.shouldShowRing)")
        WidgetReloader.scheduleReload()
    }
    
    private func handleError(_ error: GrokBotAPIError) {
        switch error {
        case .noCookie:
            errorState = .cookieUnavailable
            statusMessage = "Cursor session not found"
        case .cookieExpired:
            errorState = .cookieExpired
            statusMessage = "Cursor session expired. Log in again at cursor.com"
        case .rateLimited:
            errorState = .rateLimited
            statusMessage = "Rate limited by Grok Bot API"
        case .invalidResponse, .httpError, .networkError:
            errorState = .networkError
            statusMessage = error.localizedDescription ?? "Network error"
        }
        hasGrokBot = false
        shouldShowRing = false
    }
}

enum GrokBotErrorState: Equatable {
    case none
    case cookieUnavailable
    case cookieExpired
    case rateLimited
    case networkError
    
    var hasError: Bool {
        self != .none
    }
}
