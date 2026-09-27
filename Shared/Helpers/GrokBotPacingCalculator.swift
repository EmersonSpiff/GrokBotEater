import Foundation

enum GrokBotPacingCalculator {
    /// Calculate daily and pacing metrics for Grok Bot weekly usage.
    /// Returns (dailyPercent, pacingDelta, pacingZone, pacingMessage).
    ///
    /// Weekly % itself always comes from the Cursor API — this only derives dials.
    ///
    /// **Daily calculation** (share of today's budget, see `GrokBotDailyBudget`):
    /// - Today's usage = weeklyNow − weeklyAtDayStart (start-of-day baseline)
    /// - Today's share = (100 − weeklyAtDayStart) ÷ daysRemaining, where
    ///   daysRemaining = (reset − dayStart) ÷ 24h and dayStart is the later of
    ///   local midnight and the current period start
    /// - Daily dial = today's usage ÷ today's share × 100 (floored at 0; >100 = over budget)
    /// - Uses `weeklyPercentExact` (the decimal API value) when provided
    ///
    /// **Pacing calculation**: Ahead/behind vs. even burn across the period.
    /// - Expected = elapsed fraction × 100 (respects workweek active time)
    /// - Delta = actual - expected
    /// - Zone: chill / onTrack / warning / hot based on margin
    static func calculate(
        weeklyPercent: Int,
        weeklyPercentExact: Double? = nil,
        periodStart: String?,
        dailySample: GrokBotDailySample?,
        now: Date = Date(),
        margin: Double = 10,
        activeDays: Set<Int> = PacingSchedule.allDays,
        activeHours: (start: Int, end: Int)? = nil,
        calendar: Calendar = .current
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
        
        // MARK: - Daily (today's usage ÷ today's share of the remaining budget)
        let weeklyNow = weeklyPercentExact ?? Double(weeklyPercent)
        let resolved = GrokBotDailyBudget.resolveSample(
            existing: dailySample,
            weeklyNow: weeklyNow,
            periodStart: periodStart,
            now: now,
            calendar: calendar
        )
        let dayStart = resolved.sample.dayStart
            ?? GrokBotDailyBudget.dayStart(now: now, periodStart: periodStartDate, calendar: calendar)
        let dailyRaw = GrokBotDailyBudget.percentOfTodayShare(
            weeklyNow: weeklyNow,
            weeklyAtDayStart: resolved.sample.weeklyAtDayStart,
            dayStart: dayStart,
            resetsAt: resetDate
        )
        let dailyPercent = max(0, Int(dailyRaw.rounded()))
        
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
    
    static func parsePeriodStart(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

// MARK: - Daily budget (shared by the Daily dial and the daily-budget alert)

/// Start-of-day baseline and today's-share math. Used by
/// `GrokBotPacingCalculator` (Daily dial) and
/// `NotificationService.evaluateGrokBotDailyBudget` so both agree.
enum GrokBotDailyBudget {
    static let dayDuration: TimeInterval = 24 * 3600

    /// Weekly usage can only drop within a day when the window resets.
    /// Tolerance covers legacy baselines stored as rounded Ints.
    static let resetDropTolerance: Double = 0.5

    /// Start of "today" for budgeting: the later of local midnight and the
    /// current period start (a period that began today starts the day there).
    static func dayStart(now: Date, periodStart: Date?, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: now)
        guard let periodStart, periodStart > midnight, periodStart <= now else { return midnight }
        return periodStart
    }

    /// Baseline to record when (re)baselining. A period that began today
    /// started at 0% used, so its baseline is 0 even if the first refresh
    /// lands later; otherwise it's the current weekly usage.
    static func freshBaseline(weeklyNow: Double, now: Date, periodStart: Date?, calendar: Calendar = .current) -> Double {
        let midnight = calendar.startOfDay(for: now)
        if let periodStart, periodStart >= midnight, periodStart <= now { return 0 }
        return weeklyNow
    }

    /// Whether a stored baseline still applies. `storedWeekly == nil` means
    /// unset; a stored 0 is a real baseline. Invalid when the day start moved
    /// (new day or new period) or usage dropped below it (window reset).
    static func isBaselineValid(
        storedWeekly: Double?,
        storedDayStart: Date?,
        currentDayStart: Date,
        weeklyNow: Double
    ) -> Bool {
        guard let storedWeekly, let storedDayStart else { return false }
        guard abs(storedDayStart.timeIntervalSince(currentDayStart)) < 1 else { return false }
        if weeklyNow < storedWeekly - resetDropTolerance { return false }
        return true
    }

    static func daysRemaining(dayStart: Date, resetsAt: Date) -> Double {
        max(0.1, resetsAt.timeIntervalSince(dayStart) / dayDuration)
    }

    static func todayUsage(weeklyNow: Double, weeklyAtDayStart: Double) -> Double {
        max(0, weeklyNow - weeklyAtDayStart)
    }

    static func todayShare(weeklyAtDayStart: Double, dayStart: Date, resetsAt: Date) -> Double {
        max(0, 100 - weeklyAtDayStart) / daysRemaining(dayStart: dayStart, resetsAt: resetsAt)
    }

    /// Today's usage as a percentage of today's share (≥ 0; > 100 = over budget).
    static func percentOfTodayShare(weeklyNow: Double, weeklyAtDayStart: Double, dayStart: Date, resetsAt: Date) -> Double {
        let share = todayShare(weeklyAtDayStart: weeklyAtDayStart, dayStart: dayStart, resetsAt: resetsAt)
        guard share > 0 else { return 0 }
        return todayUsage(weeklyNow: weeklyNow, weeklyAtDayStart: weeklyAtDayStart) / share * 100
    }

    /// Keep `existing` if it is still today's baseline for this period, else
    /// return a fresh one. `rebaselined` tells the caller to persist it.
    static func resolveSample(
        existing: GrokBotDailySample?,
        weeklyNow: Double,
        periodStart: String?,
        now: Date,
        calendar: Calendar = .current
    ) -> (sample: GrokBotDailySample, rebaselined: Bool) {
        let periodStartDate = GrokBotPacingCalculator.parsePeriodStart(periodStart)
        let currentDayStart = dayStart(now: now, periodStart: periodStartDate, calendar: calendar)
        let todayKey = GrokBotPacingCalculator.dayKey(for: now, calendar: calendar)

        if let existing,
           existing.periodStart == nil || periodStart == nil || existing.periodStart == periodStart {
            let storedDayStart = existing.dayStart
                ?? legacyDayStart(existing, todayKey: todayKey, currentDayStart: currentDayStart, now: now, calendar: calendar)
            if isBaselineValid(
                storedWeekly: existing.weeklyAtDayStart,
                storedDayStart: storedDayStart,
                currentDayStart: currentDayStart,
                weeklyNow: weeklyNow
            ) {
                return (existing, false)
            }
        }

        let fresh = GrokBotDailySample(
            dayKey: todayKey,
            weeklyAtDayStart: freshBaseline(weeklyNow: weeklyNow, now: now, periodStart: periodStartDate, calendar: calendar),
            recordedAt: now,
            dayStart: currentDayStart,
            periodStart: periodStart
        )
        return (fresh, true)
    }

    /// Samples written before `dayStart` was stored: trust them only for a
    /// plain midnight day start. On a day a period started, older builds
    /// baselined to the post-reset usage, so re-baseline instead.
    private static func legacyDayStart(
        _ sample: GrokBotDailySample,
        todayKey: String,
        currentDayStart: Date,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let midnight = calendar.startOfDay(for: now)
        guard sample.dayKey == todayKey,
              currentDayStart == midnight,
              sample.recordedAt >= midnight else { return nil }
        return midnight
    }
}
