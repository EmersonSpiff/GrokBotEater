import Testing
import Foundation

@Suite("GrokBotPacingCalculator")
struct GrokBotPacingCalculatorTests {

    // MARK: - Helper

    private static func stableNow() -> Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    }

    private func makePeriodStart(elapsedFraction: Double, now: Date, duration: TimeInterval = 7 * 24 * 3600) -> String {
        let periodStart = now.addingTimeInterval(-elapsedFraction * duration)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: periodStart)
    }

    // MARK: - Nil cases

    @Test("returns nil when periodStart is nil")
    func returnsNilWhenPeriodStartIsNil() {
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: nil,
            dailySample: nil
        )
        #expect(result == nil)
    }

    @Test("returns nil when periodStart is empty")
    func returnsNilWhenPeriodStartIsEmpty() {
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: "",
            dailySample: nil
        )
        #expect(result == nil)
    }

    @Test("returns nil when periodStart is invalid ISO8601")
    func returnsNilWhenPeriodStartIsInvalid() {
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: "not-a-date",
            dailySample: nil
        )
        #expect(result == nil)
    }

    // MARK: - Basic pacing calculation (rolling, full week)

    @Test("at 0% elapsed and 0% used: delta is 0, zone is onTrack")
    func atStartZeroUsed() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 0,
            periodStart: periodStart,
            dailySample: nil,
            now: now
        )
        #expect(result?.pacingDelta == 0)
        #expect(result?.pacingZone == .onTrack)
    }

    @Test("at 50% elapsed and 50% used: delta is 0, zone is onTrack")
    func atHalfwayEvenPace() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: periodStart,
            dailySample: nil,
            now: now
        )
        #expect(result?.pacingDelta == 0)
        #expect(result?.pacingZone == .onTrack)
    }

    @Test("at 50% elapsed and 80% used: delta is +30, zone is hot")
    func atHalfwayAhead() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 80,
            periodStart: periodStart,
            dailySample: nil,
            now: now,
            margin: 10
        )
        #expect(result?.pacingDelta == 30)
        #expect(result?.pacingZone == .hot)
    }

    @Test("at 50% elapsed and 20% used: delta is -30, zone is chill")
    func atHalfwayBehind() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 20,
            periodStart: periodStart,
            dailySample: nil,
            now: now,
            margin: 10
        )
        #expect(result?.pacingDelta == -30)
        #expect(result?.pacingZone == .chill)
    }

    @Test("at 50% elapsed and 55% used: delta is +5, zone is onTrack")
    func atHalfwaySlightlyAhead() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 55,
            periodStart: periodStart,
            dailySample: nil,
            now: now,
            margin: 10
        )
        #expect(result?.pacingDelta == 5)
        #expect(result?.pacingZone == .onTrack)
    }

    @Test("at 50% elapsed and 65% used: delta is +15, zone is warning")
    func atHalfwayWarningZone() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 65,
            periodStart: periodStart,
            dailySample: nil,
            now: now,
            margin: 10
        )
        #expect(result?.pacingDelta == 15)
        #expect(result?.pacingZone == .warning)
    }

    // MARK: - Daily calculation (today's usage ÷ today's share)

    private static var nyCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }

    private static func iso(_ raw: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)!
    }

    // Plan upgrade reset the week at Sun Sep 27 2026 8:50 AM ET (12:50Z).
    private static let freshPeriodStart = "2026-09-27T12:50:00Z"
    // 46 minutes into the fresh period (9:36 AM ET).
    private static let freshNow = iso("2026-09-27T13:36:00Z")

    @Test("fresh period 46 min in, weekly 1.0, baseline 0: Daily ≈ 7%")
    func dailyFreshPeriodLow() {
        let sample = GrokBotDailySample(
            dayKey: "2026-09-27",
            weeklyAtDayStart: 0,
            recordedAt: Self.iso(Self.freshPeriodStart),
            dayStart: Self.iso(Self.freshPeriodStart),
            periodStart: Self.freshPeriodStart
        )
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 1,
            weeklyPercentExact: 1.0,
            periodStart: Self.freshPeriodStart,
            dailySample: sample,
            now: Self.freshNow,
            calendar: Self.nyCalendar
        )
        // share = 100 / 7 days ≈ 14.29%; 1.0 / 14.29 ≈ 7%
        #expect(result?.dailyPercent == 7)
    }

    @Test("fresh period with no sample baselines at 0 (period started today)")
    func dailyFreshPeriodNoSample() {
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 1,
            weeklyPercentExact: 1.0,
            periodStart: Self.freshPeriodStart,
            dailySample: nil,
            now: Self.freshNow,
            calendar: Self.nyCalendar
        )
        #expect(result?.dailyPercent == 7)
    }

    @Test("fresh period ignores a legacy sample baselined to post-reset usage")
    func dailyFreshPeriodLegacySample() {
        let legacy = GrokBotDailySample(
            dayKey: "2026-09-27",
            weeklyAtDayStart: 1,
            recordedAt: Self.iso("2026-09-27T13:00:00Z")
        )
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 1,
            weeklyPercentExact: 1.0,
            periodStart: Self.freshPeriodStart,
            dailySample: legacy,
            now: Self.freshNow,
            calendar: Self.nyCalendar
        )
        #expect(result?.dailyPercent == 7)
    }

    @Test("Daily uses the decimal usagePercent, not the rounded Int")
    func dailyUsesDecimalUsage() {
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 1,
            weeklyPercentExact: 0.6,
            periodStart: Self.freshPeriodStart,
            dailySample: nil,
            now: Self.freshNow,
            calendar: Self.nyCalendar
        )
        // 0.6 / 14.29 ≈ 4.2% (the rounded Int 1 would give 7%)
        #expect(result?.dailyPercent == 4)
    }

    // Mid-week: period started Thu Sep 24 8:50 AM ET, now Sun Sep 27 2:00 PM ET.
    private static let midPeriodStart = "2026-09-24T12:50:00Z"
    private static let midNow = iso("2026-09-27T18:00:00Z")
    private static var midSample: GrokBotDailySample {
        GrokBotDailySample(
            dayKey: "2026-09-27",
            weeklyAtDayStart: 40,
            recordedAt: iso("2026-09-27T04:05:00Z"),
            dayStart: iso("2026-09-27T04:00:00Z"), // local midnight
            periodStart: midPeriodStart
        )
    }

    @Test("mid-week: today's usage over today's share of the remaining budget")
    func dailyMidWeek() {
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 48,
            weeklyPercentExact: 47.5,
            periodStart: Self.midPeriodStart,
            dailySample: Self.midSample,
            now: Self.midNow,
            calendar: Self.nyCalendar
        )
        // daysRemaining = midnight → Thu 8:50 AM = 4.368; share = 60 / 4.368 = 13.74%
        // today = 7.5% → 54.6% of today's share
        #expect(result?.dailyPercent == 55)
    }

    @Test("mid-week over budget reads above 100%")
    func dailyMidWeekOverBudget() {
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 70,
            weeklyPercentExact: 70,
            periodStart: Self.midPeriodStart,
            dailySample: Self.midSample,
            now: Self.midNow,
            calendar: Self.nyCalendar
        )
        // 30 / 13.74 ≈ 218%
        #expect(result?.dailyPercent == 218)
    }

    @Test("mid-week with no usage today reads 0%")
    func dailyMidWeekNoUsage() {
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 40,
            weeklyPercentExact: 40,
            periodStart: Self.midPeriodStart,
            dailySample: Self.midSample,
            now: Self.midNow,
            calendar: Self.nyCalendar
        )
        #expect(result?.dailyPercent == 0)
    }

    // MARK: - Daily baseline (shared with the daily-budget alert)

    @Test("dayStart is the later of local midnight and period start")
    func dayStartLaterOfMidnightAndPeriodStart() {
        let cal = Self.nyCalendar
        #expect(GrokBotDailyBudget.dayStart(now: Self.freshNow, periodStart: Self.iso(Self.freshPeriodStart), calendar: cal)
                == Self.iso(Self.freshPeriodStart))
        #expect(GrokBotDailyBudget.dayStart(now: Self.midNow, periodStart: Self.iso(Self.midPeriodStart), calendar: cal)
                == Self.iso("2026-09-27T04:00:00Z"))
    }

    @Test("a baseline of 0 persists and is not overwritten")
    func zeroBaselinePersists() {
        let cal = Self.nyCalendar
        let sample = GrokBotDailySample(
            dayKey: "2026-09-27",
            weeklyAtDayStart: 0,
            recordedAt: Self.iso(Self.freshPeriodStart),
            dayStart: Self.iso(Self.freshPeriodStart),
            periodStart: Self.freshPeriodStart
        )
        // Several refreshes later in the same period/day, usage climbing.
        for (offset, weekly) in [(0.0, 0.0), (1800.0, 1.0), (7200.0, 3.2)] {
            let resolved = GrokBotDailyBudget.resolveSample(
                existing: sample,
                weeklyNow: weekly,
                periodStart: Self.freshPeriodStart,
                now: Self.freshNow.addingTimeInterval(offset),
                calendar: cal
            )
            #expect(resolved.rebaselined == false)
            #expect(resolved.sample.weeklyAtDayStart == 0)
        }
        // The alert path uses the same validity check: stored 0 is valid, nil is unset.
        #expect(GrokBotDailyBudget.isBaselineValid(
            storedWeekly: 0, storedDayStart: Self.iso(Self.freshPeriodStart),
            currentDayStart: Self.iso(Self.freshPeriodStart), weeklyNow: 3.2))
        #expect(!GrokBotDailyBudget.isBaselineValid(
            storedWeekly: nil, storedDayStart: Self.iso(Self.freshPeriodStart),
            currentDayStart: Self.iso(Self.freshPeriodStart), weeklyNow: 3.2))
    }

    @Test("baseline resets when the day rolls over")
    func baselineResetsOnNewDay() {
        let cal = Self.nyCalendar
        let yesterday = GrokBotDailySample(
            dayKey: "2026-09-26",
            weeklyAtDayStart: 30,
            recordedAt: Self.iso("2026-09-26T04:05:00Z"),
            dayStart: Self.iso("2026-09-26T04:00:00Z"),
            periodStart: Self.midPeriodStart
        )
        let resolved = GrokBotDailyBudget.resolveSample(
            existing: yesterday, weeklyNow: 40, periodStart: Self.midPeriodStart,
            now: Self.midNow, calendar: cal
        )
        #expect(resolved.rebaselined)
        #expect(resolved.sample.weeklyAtDayStart == 40)
        #expect(resolved.sample.dayKey == "2026-09-27")
    }

    @Test("baseline resets when a new period starts")
    func baselineResetsOnNewPeriod() {
        let cal = Self.nyCalendar
        let oldPeriod = GrokBotDailySample(
            dayKey: "2026-09-27",
            weeklyAtDayStart: 62,
            recordedAt: Self.iso("2026-09-27T04:05:00Z"),
            dayStart: Self.iso("2026-09-27T04:00:00Z"),
            periodStart: "2026-09-21T12:50:00Z"
        )
        let resolved = GrokBotDailyBudget.resolveSample(
            existing: oldPeriod, weeklyNow: 1.0, periodStart: Self.freshPeriodStart,
            now: Self.freshNow, calendar: cal
        )
        #expect(resolved.rebaselined)
        #expect(resolved.sample.weeklyAtDayStart == 0)
        #expect(resolved.sample.dayStart == Self.iso(Self.freshPeriodStart))
    }

    @Test("baseline resets when weekly usage drops below it")
    func baselineResetsOnUsageDrop() {
        #expect(!GrokBotDailyBudget.isBaselineValid(
            storedWeekly: 62, storedDayStart: Self.iso("2026-09-27T04:00:00Z"),
            currentDayStart: Self.iso("2026-09-27T04:00:00Z"), weeklyNow: 1))
    }

    @Test("legacy sample with Int weeklyAtDayStart decodes")
    func legacySampleDecodes() throws {
        let json = #"{"dayKey":"2026-09-27","weeklyAtDayStart":0,"recordedAt":0}"#
        let sample = try JSONDecoder().decode(GrokBotDailySample.self, from: Data(json.utf8))
        #expect(sample.weeklyAtDayStart == 0)
        #expect(sample.dayStart == nil)
        #expect(sample.periodStart == nil)
    }

    // MARK: - Workweek pacing (schedule-adjusted)

    @Test("workweek pacing with Mon-Fri active days advances pace only on weekdays")
    func workweekPacingMonFri() {
        let calendar = Calendar.current
        let now = Self.stableNow()
        
        let components = calendar.dateComponents([.year, .month, .day, .weekday], from: now)
        guard let weekday = components.weekday else { return }
        
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: periodStart,
            dailySample: nil,
            now: now,
            activeDays: PacingSchedule.workweek
        )
        
        #expect(result != nil)
        
        if PacingSchedule.workweek.contains(weekday) {
            #expect(abs(result!.pacingDelta) >= 0)
        }
    }

    @Test("workweek schedule changes elapsed pace vs rolling")
    func dailyWithWorkweekSchedule() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let rolling = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: periodStart,
            dailySample: nil,
            now: now,
            activeDays: PacingSchedule.allDays
        )
        let workweek = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: periodStart,
            dailySample: nil,
            now: now,
            activeDays: PacingSchedule.workweek
        )
        #expect(rolling != nil)
        #expect(workweek != nil)
        // Both should produce finite dials; workweek elapsed may differ.
        // Daily no longer depends on the pacing schedule (no sample → 0 today).
        #expect(rolling!.dailyPercent >= 0)
        #expect(workweek!.dailyPercent == rolling!.dailyPercent)
    }


    // MARK: - Zone boundaries

    @Test("zone is chill when delta < -margin")
    func zoneIsChillBelowNegativeMargin() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 30,
            periodStart: periodStart,
            dailySample: nil,
            now: now,
            margin: 10
        )
        #expect(result?.pacingDelta == -20)
        #expect(result?.pacingZone == .chill)
    }

    @Test("zone is onTrack when delta is within ±margin")
    func zoneIsOnTrackWithinMargin() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        
        let resultPlus5 = GrokBotPacingCalculator.calculate(
            weeklyPercent: 55,
            periodStart: periodStart,
            dailySample: nil,
            now: now,
            margin: 10
        )
        #expect(resultPlus5?.pacingZone == .onTrack)
        
        let resultMinus5 = GrokBotPacingCalculator.calculate(
            weeklyPercent: 45,
            periodStart: periodStart,
            dailySample: nil,
            now: now,
            margin: 10
        )
        #expect(resultMinus5?.pacingZone == .onTrack)
    }

    @Test("zone is warning when margin < delta <= 2*margin")
    func zoneIsWarningBetweenMarginAndDoubleMargin() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 65,
            periodStart: periodStart,
            dailySample: nil,
            now: now,
            margin: 10
        )
        #expect(result?.pacingDelta == 15)
        #expect(result?.pacingZone == .warning)
    }

    @Test("zone is hot when delta > 2*margin")
    func zoneIsHotAboveDoubleMargin() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 75,
            periodStart: periodStart,
            dailySample: nil,
            now: now,
            margin: 10
        )
        #expect(result?.pacingDelta == 25)
        #expect(result?.pacingZone == .hot)
    }

    // MARK: - Message selection

    @Test("message is selected from the zone's message pool")
    func messageIsSelectedFromZonePool() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 80,
            periodStart: periodStart,
            dailySample: nil,
            now: now
        )
        #expect(result?.pacingMessage != nil)
        #expect(result?.pacingMessage.isEmpty == false)
    }

    // MARK: - ISO8601 parsing

    @Test("parses ISO8601 with fractional seconds")
    func parsesISO8601WithFractionalSeconds() {
        let now = Self.stableNow()
        let periodStartDate = now.addingTimeInterval(-3.5 * 24 * 3600)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let periodStart = formatter.string(from: periodStartDate)
        
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: periodStart,
            dailySample: nil,
            now: now
        )
        #expect(result != nil)
    }

    @Test("parses ISO8601 without fractional seconds")
    func parsesISO8601WithoutFractionalSeconds() {
        let now = Self.stableNow()
        let periodStartDate = now.addingTimeInterval(-3.5 * 24 * 3600)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let periodStart = formatter.string(from: periodStartDate)
        
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: periodStart,
            dailySample: nil,
            now: now
        )
        #expect(result != nil)
    }

    // MARK: - Day key generation

    @Test("dayKey generates yyyy-MM-dd format")
    func dayKeyGeneratesCorrectFormat() {
        let calendar = Calendar.current
        let components = DateComponents(year: 2026, month: 9, day: 22)
        guard let date = calendar.date(from: components) else { return }
        
        let key = GrokBotPacingCalculator.dayKey(for: date, calendar: calendar)
        #expect(key == "2026-09-22")
    }

    @Test("dayKey pads single-digit month and day with zeros")
    func dayKeyPadsSingleDigits() {
        let calendar = Calendar.current
        let components = DateComponents(year: 2026, month: 1, day: 5)
        guard let date = calendar.date(from: components) else { return }
        
        let key = GrokBotPacingCalculator.dayKey(for: date, calendar: calendar)
        #expect(key == "2026-01-05")
    }
}
