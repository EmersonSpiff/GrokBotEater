import Foundation

enum GrokBotPacingCalculator {
    /// Calculate daily and pacing metrics for Grok Bot weekly usage.
    /// Returns (dailyPercent, pacingDelta, pacingZone, pacingMessage).
    static func calculate(
        weeklyPercent: Int,
        periodStart: String?,
        now: Date = Date(),
        margin: Double = 10,
        activeDays: Set<Int> = PacingSchedule.allDays,
        activeHours: (start: Int, end: Int)? = nil
    ) -> (dailyPercent: Int, pacingDelta: Double, pacingZone: PacingZone, pacingMessage: String)? {
        guard let periodStartDate = parsePeriodStart(periodStart) else { return nil }
        
        let periodDuration: TimeInterval = 7 * 24 * 3600
        let resetDate = periodStartDate.addingTimeInterval(periodDuration)
        
        guard now >= periodStartDate, now <= resetDate else { return nil }
        
        let isFullWindow = activeDays.count >= 7 && activeHours == nil
        let clampedElapsed: Double
        
        if isFullWindow {
            let elapsed = now.timeIntervalSince(periodStartDate) / periodDuration
            clampedElapsed = min(max(elapsed, 0), 1)
        } else {
            let total = PacingCalculator.activeSeconds(
                from: periodStartDate, to: resetDate,
                activeDays: activeDays, hours: activeHours
            )
            let elapsedEnd = min(max(now, periodStartDate), resetDate)
            let elapsed = PacingCalculator.activeSeconds(
                from: periodStartDate, to: elapsedEnd,
                activeDays: activeDays, hours: activeHours
            )
            clampedElapsed = total > 0 ? min(max(elapsed / total, 0), 1) : 0
        }
        
        let expectedUsage = clampedElapsed * 100
        let pacingDelta = Double(weeklyPercent) - expectedUsage
        
        let zone: PacingZone
        if pacingDelta < -margin {
            zone = .chill
        } else if pacingDelta <= margin {
            zone = .onTrack
        } else if pacingDelta <= margin * 2 {
            zone = .warning
        } else {
            zone = .hot
        }
        
        let messageKey = messageKey(for: zone, delta: pacingDelta)
        let message = String(localized: String.LocalizationValue(messageKey))
        
        let fairDailyBudget = 100.0 / 7.0
        let dailyUsed = Double(weeklyPercent) * (1.0 / 7.0)
        let dailyPercent = Int((dailyUsed / fairDailyBudget * 100).rounded())
        
        return (dailyPercent, pacingDelta, zone, message)
    }
    
    private static let weeklyMessages: [PacingZone: [String]] = [
        .chill:   ["pacing.grokBot.chill.1", "pacing.grokBot.chill.2", "pacing.grokBot.chill.3"],
        .onTrack: ["pacing.grokBot.ontrack.1", "pacing.grokBot.ontrack.2", "pacing.grokBot.ontrack.3"],
        .warning: ["pacing.grokBot.warning.1", "pacing.grokBot.warning.2", "pacing.grokBot.warning.3"],
        .hot:     ["pacing.grokBot.hot.1", "pacing.grokBot.hot.2", "pacing.grokBot.hot.3"],
    ]
    
    private static func messageKey(for zone: PacingZone, delta: Double) -> String {
        let pool = weeklyMessages[zone] ?? []
        guard !pool.isEmpty else { return "" }
        let index = abs(Int(delta)) % pool.count
        return pool[index]
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
}
