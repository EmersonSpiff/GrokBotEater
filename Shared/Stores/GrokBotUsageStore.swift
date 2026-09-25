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
    /// ISO start of the current Grok Bot billing period (from last response / cache).
    @Published var currentPeriodStart: String?

    /// True when the plan includes Grok Bot and we should draw a ring.
    /// Respects shouldDrawRing from the API response.
    @Published var shouldShowRing = false

    /// End of the current weekly window (period start + 7 days), if known.
    var nextResetDate: Date? {
        guard let start = Self.parsePeriodStart(currentPeriodStart) else { return nil }
        return Calendar.current.date(byAdding: .day, value: 7, to: start)
    }
    
    /// Current usage snapshot for notifications and test alerts.
    var currentSnapshot: MetricSnapshot? {
        guard hasGrokBot, !isLoading else { return nil }
        return MetricSnapshot(
            pct: usagePercent,
            resetsAt: nextResetDate,
            windowDuration: 7 * 24 * 3600
        )
    }
    
    /// Human-readable status for onboarding/settings
    @Published var statusMessage: String = "Not connected"
    
    private(set) var lastResponse: GrokBotUsageResponse?
    private let apiClient: GrokBotAPIClientProtocol
    private let cookieReader: CursorCookieReaderProtocol
    let sharedFileService: SharedFileServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let historyService: GrokBotHistoryService
    
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    
    var refreshIntervalSeconds: TimeInterval = 300 // 5 minutes, match Claude
    
    /// Closure that returns the current notification toggles bundle. Wired by
    /// `StatusBarController` at bootstrap once SettingsStore is available so
    /// the store can fire notifications based on the latest user-facing toggles
    /// without owning a direct SettingsStore reference.
    var notifTogglesProvider: (() -> NotificationToggles?)?
    
    init(
        apiClient: GrokBotAPIClientProtocol = GrokBotAPIClient(),
        cookieReader: CursorCookieReaderProtocol = CursorCookieReader(),
        sharedFileService: SharedFileServiceProtocol = SharedFileService(),
        notificationService: NotificationServiceProtocol = NotificationService(),
        historyService: GrokBotHistoryService = GrokBotHistoryService()
    ) {
        self.apiClient = apiClient
        self.cookieReader = cookieReader
        self.sharedFileService = sharedFileService
        self.notificationService = notificationService
        self.historyService = historyService
        
        loadCached()
    }
    
    private func loadCached() {
        // Re-derive Daily / Pacing from the last weekly snapshot so a fresh install
        // does not leave dials stuck until the next API refresh.
        guard let snap = sharedFileService.grokBotSnapshot,
              snap.hasGrokBot,
              snap.shouldDrawRing else { return }
        usagePercent = snap.usagePercent
        shouldShowRing = snap.shouldDrawRing
        hasGrokBot = snap.hasGrokBot
        currentPeriodStart = snap.currentPeriodStart
        lastUpdate = snap.lastSync
        recomputePacingAndPublish(weeklyPercent: snap.usagePercent, periodStart: snap.currentPeriodStart)
    }

    /// Derive Daily / Pacing from weekly % + period start and write the shared snapshot.
    private func recomputePacingAndPublish(weeklyPercent: Int, periodStart: String?) {
        let now = Date()
        let todayKey = GrokBotPacingCalculator.dayKey(for: now)

        // New billing period (plan upgrade / weekly reset) must drop the old day sample.
        let previousPeriod = sharedFileService.grokBotSnapshot?.currentPeriodStart
        let periodChanged = previousPeriod != nil && periodStart != nil && previousPeriod != periodStart

        var dailySample = sharedFileService.grokBotDailySample
        if periodChanged || dailySample == nil || dailySample?.dayKey != todayKey {
            dailySample = GrokBotDailySample(
                dayKey: todayKey,
                weeklyAtDayStart: weeklyPercent,
                recordedAt: now
            )
            sharedFileService.updateGrokBotDailySample(dailySample!)
        }

        let pacingSchedule = sharedFileService.pacingSchedule
        let pacing = GrokBotPacingCalculator.calculate(
            weeklyPercent: weeklyPercent,
            periodStart: periodStart,
            dailySample: dailySample,
            now: now,
            margin: 10,
            activeDays: pacingSchedule.effectiveActiveDays,
            activeHours: pacingSchedule.effectiveHours
        )

        let snapshot = GrokBotSharedSnapshot(
            usagePercent: weeklyPercent,
            hasGrokBot: hasGrokBot,
            shouldDrawRing: shouldShowRing,
            currentPeriodStart: periodStart,
            lastSync: lastUpdate ?? now,
            dailyPercent: pacing?.dailyPercent,
            pacingDelta: pacing?.pacingDelta,
            pacingZone: pacing?.pacingZone.rawValue,
            pacingMessage: pacing?.pacingMessage
        )
        sharedFileService.updateGrokBotSnapshot(snapshot)
        WidgetReloader.scheduleReload()
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
        hasGrokBot = true
        currentPeriodStart = response.currentPeriodStart
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
        
        recomputePacingAndPublish(weeklyPercent: usagePercent, periodStart: currentPeriodStart)
        logger.info("Grok Bot refresh succeeded: \(self.usagePercent)% used, shouldDrawRing=\(self.shouldShowRing), daily=\(self.sharedFileService.grokBotSnapshot?.dailyPercent ?? -1)")
        
        // Record history snapshot
        let snapshot = sharedFileService.grokBotSnapshot
        historyService.recordSnapshot(
            weeklyPercent: usagePercent,
            activeAgentCount: 0, // Will be updated when SessionStore is available
            dailyPercent: snapshot?.dailyPercent,
            pacingDelta: snapshot?.pacingDelta
        )
        
        evaluateNotifications()
    }
    
    private func evaluateNotifications() {
        guard let toggles = notifTogglesProvider?() else { return }
        
        // Weekly usage threshold alerts
        notificationService.evaluateGrokBot(
            usagePercent: usagePercent,
            resetDate: nextResetDate,
            toggles: toggles
        )
        
        // Daily budget alerts
        if let resetDate = nextResetDate, let snapshot = sharedFileService.grokBotSnapshot {
            let now = Date()
            
            // Get today's usage from daily pacing (default 0 if not available)
            let todayUsagePercent = Double(snapshot.dailyPercent ?? 0)
            
            notificationService.evaluateGrokBotDailyBudget(
                weeklyUsedPercent: usagePercent,
                resetDate: resetDate,
                todayUsagePercent: todayUsagePercent,
                now: now,
                toggles: toggles
            )
        }
        
        // Pace alerts
        if let resetDate = nextResetDate, let snapshot = sharedFileService.grokBotSnapshot, let periodStartString = snapshot.currentPeriodStart, let periodStart = Self.parsePeriodStart(periodStartString) {
            let now = Date()
            let totalDuration = resetDate.timeIntervalSince(periodStart)
            let elapsed = now.timeIntervalSince(periodStart)
            let elapsedPercent = totalDuration > 0 ? elapsed / totalDuration : 0
            
            // Calculate daily usage needed to reach 1.0x pace by reset
            let daysRemaining = max(0.1, resetDate.timeIntervalSinceNow / 86400.0)
            let targetUsageByReset = elapsedPercent * 100
            let remainingToTarget = max(0, targetUsageByReset - Double(usagePercent))
            let dailyUsageToReachPace = remainingToTarget / daysRemaining
            
            notificationService.evaluateGrokBotPace(
                weeklyUsedPercent: usagePercent,
                elapsedPercent: elapsedPercent,
                resetDate: resetDate,
                dailyUsageToReachPace: dailyUsageToReachPace,
                now: now,
                toggles: toggles
            )
        }
    }

    private static func parsePeriodStart(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
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
