import Foundation

enum GrokBotPacingCalculator {
    /// Calculate daily and pacing metrics for Grok Bot weekly usage.
    /// Returns (dailyPercent, pacingDelta, pacingZone, pacingMessage).
    ///
    /// Weekly % itself always comes from the Cursor API — this only derives dials.
    ///
    /// **Daily calculation** (signup-agnostic):
    /// - Expected so far = elapsedFraction × 100 from THIS user’s periodStart
    /// - Floor elapsed at 2 hours of the window so early refresh doesn’t explode
    /// - Daily dial = (actualWeekly / expectedSoFar) × 100 (100% = even pace)
    ///
    /// **Pacing calculation**: Ahead/behind vs. even burn across the period.
    /// - Expected = elapsed fraction × 100 (respects workweek active time)
    /// - Delta = actual - expected
    /// - Zone: chill / onTrack / warning / hot based on margin
    static func calculate(
        weeklyPercent: Int,
        periodStart: String?,
        dailySample: GrokBotDailySample?,
        now: Date = Date(),
        margin: Double = 10,
        activeDays: Set<Int> = PacingSchedule.allDays,
        activeHours: (start: Int, end: Int)? = nil
    ) -> (dailyPercent: Int, pacingDelta: Double, pacingZone: PacingZone, pacingMessage: String)? {
        guard let periodStartDate = parsePeriodStart(periodStart) else { return nil }
        
        let periodDuration: TimeInterval = 7 * 24 * 3600
        let resetDate = periodStartDate.addingTimeInterval(periodDuration)
        
        guard now >= periodStartDate, now <= resetDate else { return nil }
        
        // MARK: - Elapsed fraction of the weekly window
        
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
        
        // MARK: - Daily (even-pace ratio from THIS user’s periodStart → reset)
        // Signup-agnostic: only periodStart differs. Floor expected at 2h of the
        // window so a brand-new period doesn’t report ∞×.
        let minElapsed = (2.0 * 3600.0) / periodDuration
        let expectedForDaily = max(clampedElapsed, minElapsed) * 100
        let dailyPercent = expectedForDaily > 0
            ? Int((Double(weeklyPercent) / expectedForDaily * 100).rounded())
            : 0
        _ = dailySample
        
        // MARK: - Pacing (true elapsed vs actual; same clock as Daily)
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
        
        return (dailyPercent, pacingDelta, zone, message)
    }
    

    /// Inclusive local calendar days from period-start day through `to`'s day.
    /// Mon start + Tue now → 2 (so day 2 of 7 matches ~28% fair share).
    static func inclusiveLocalCalendarDaysElapsed(
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let days = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(1, days + 1)
    }

    /// Generate the local day key (yyyy-MM-dd) for a given date.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
    
    /// Check if a day key matches the current local day.
    private static func isDayKeyCurrent(_ key: String, now: Date, calendar: Calendar = .current) -> Bool {
        return key == dayKey(for: now, calendar: calendar)
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
