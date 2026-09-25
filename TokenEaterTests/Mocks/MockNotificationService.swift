import Foundation
import UserNotifications

final class MockNotificationService: NotificationServiceProtocol {
    var permissionRequested = false
    var lastEvaluation: (
        fiveHour: MetricSnapshot,
        sevenDay: MetricSnapshot,
        sonnet: MetricSnapshot,
        fable: MetricSnapshot,
        sessionPacing: PacingZone?,
        weeklyPacing: PacingZone?,
        extraUsage: ExtraUsage?,
        toggles: NotificationToggles
    )?
    var lastTokenExpiredFire: Bool?
    var lastReminderSchedule: (
        sessionResetsAt: Date?,
        weeklyResetsAt: Date?,
        toggles: NotificationToggles
    )?
    var stubbedAuthStatus: UNAuthorizationStatus = .notDetermined
    var testSent = false
    var vendorHealthChecks: [(status: VendorStatus, toggles: NotificationToggles)] = []

    func setupDelegate() {}
    func requestPermission() { permissionRequested = true }
    func checkAuthorizationStatus() async -> UNAuthorizationStatus { stubbedAuthStatus }
    func sendTest() { testSent = true }

    func evaluate(
        fiveHour: MetricSnapshot,
        sevenDay: MetricSnapshot,
        sonnet: MetricSnapshot,
        fable: MetricSnapshot,
        sessionPacing: PacingZone?,
        weeklyPacing: PacingZone?,
        extraUsage: ExtraUsage?,
        toggles: NotificationToggles
    ) {
        lastEvaluation = (fiveHour, sevenDay, sonnet, fable, sessionPacing, weeklyPacing, extraUsage, toggles)
    }

    func notifyTokenExpired(toggle: Bool) {
        lastTokenExpiredFire = toggle
    }

    func scheduleResetReminders(
        sessionResetsAt: Date?,
        weeklyResetsAt: Date?,
        toggles: NotificationToggles
    ) {
        lastReminderSchedule = (sessionResetsAt, weeklyResetsAt, toggles)
    }

    func checkVendorHealth(_ status: VendorStatus, toggles: NotificationToggles) {
        vendorHealthChecks.append((status, toggles))
    }
    
    var lastGrokBotEvaluation: (usagePercent: Int, resetDate: Date?, toggles: NotificationToggles)?
    var lastGrokBotDailyBudgetEvaluation: (weeklyUsedPercent: Int, resetDate: Date?, now: Date, toggles: NotificationToggles)?
    var lastGrokBotPaceEvaluation: (weeklyUsedPercent: Int, elapsedPercent: Double, resetDate: Date?, dailyUsageToReachPace: Double, now: Date, toggles: NotificationToggles)?
    
    func evaluateGrokBot(usagePercent: Int, resetDate: Date?, toggles: NotificationToggles) {
        lastGrokBotEvaluation = (usagePercent, resetDate, toggles)
    }
    
    func evaluateGrokBotDailyBudget(
        weeklyUsedPercent: Int,
        resetDate: Date?,
        now: Date,
        toggles: NotificationToggles
    ) {
        lastGrokBotDailyBudgetEvaluation = (weeklyUsedPercent, resetDate, now, toggles)
    }
    
    func evaluateGrokBotPace(
        weeklyUsedPercent: Int,
        elapsedPercent: Double,
        resetDate: Date?,
        dailyUsageToReachPace: Double,
        now: Date,
        toggles: NotificationToggles
    ) {
        lastGrokBotPaceEvaluation = (weeklyUsedPercent, elapsedPercent, resetDate, dailyUsageToReachPace, now, toggles)
    }
}
