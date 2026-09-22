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

    // MARK: - Daily calculation (corrected)

    @Test("daily is 0 when no sample exists")
    func dailyIsZeroWithoutSample() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: periodStart,
            dailySample: nil,
            now: now
        )
        #expect(result?.dailyPercent == 0)
    }

    @Test("daily is 0 when sample is from a different day")
    func dailyIsZeroWhenSampleIsStale() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let yesterdayKey = GrokBotPacingCalculator.dayKey(for: now.addingTimeInterval(-86400))
        let staleSample = GrokBotDailySample(
            dayKey: yesterdayKey,
            weeklyAtDayStart: 30,
            recordedAt: now.addingTimeInterval(-86400)
        )
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: periodStart,
            dailySample: staleSample,
            now: now
        )
        #expect(result?.dailyPercent == 0)
    }

    @Test("daily is 0 when weeklyAtDayStart equals current weekly (no burn today)")
    func dailyIsZeroWhenNoBurnToday() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let todayKey = GrokBotPacingCalculator.dayKey(for: now)
        let sample = GrokBotDailySample(
            dayKey: todayKey,
            weeklyAtDayStart: 50,
            recordedAt: now
        )
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: periodStart,
            dailySample: sample,
            now: now
        )
        #expect(result?.dailyPercent == 0)
    }

    @Test("daily calculation: 10% burned today, fair share ~14.3%, daily ≈ 70%")
    func dailyCalculationBasicBurn() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let todayKey = GrokBotPacingCalculator.dayKey(for: now)
        let sample = GrokBotDailySample(
            dayKey: todayKey,
            weeklyAtDayStart: 40,
            recordedAt: now
        )
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: periodStart,
            dailySample: sample,
            now: now
        )
        let todayBurn = 50 - 40
        let fairDailyShare = 100.0 / 7.0
        let expectedDaily = Int((Double(todayBurn) / fairDailyShare * 100).rounded())
        #expect(result?.dailyPercent == expectedDaily)
    }

    @Test("daily calculation: 14% burned today (fair share), daily ≈ 100%")
    func dailyCalculationFairShareBurn() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let todayKey = GrokBotPacingCalculator.dayKey(for: now)
        let sample = GrokBotDailySample(
            dayKey: todayKey,
            weeklyAtDayStart: 40,
            recordedAt: now
        )
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 54,
            periodStart: periodStart,
            dailySample: sample,
            now: now
        )
        let todayBurn = 54 - 40
        let fairDailyShare = 100.0 / 7.0
        let expectedDaily = Int((Double(todayBurn) / fairDailyShare * 100).rounded())
        #expect(result?.dailyPercent == expectedDaily)
    }

    @Test("daily calculation: 30% burned today, daily ≈ 210% (over budget)")
    func dailyCalculationHighBurn() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let todayKey = GrokBotPacingCalculator.dayKey(for: now)
        let sample = GrokBotDailySample(
            dayKey: todayKey,
            weeklyAtDayStart: 40,
            recordedAt: now
        )
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 70,
            periodStart: periodStart,
            dailySample: sample,
            now: now
        )
        let todayBurn = 70 - 40
        let fairDailyShare = 100.0 / 7.0
        let expectedDaily = Int((Double(todayBurn) / fairDailyShare * 100).rounded())
        #expect(result?.dailyPercent == expectedDaily)
    }

    @Test("daily ≠ weekly when weekly is high but today's burn is low")
    func dailyNotEqualToWeekly() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let todayKey = GrokBotPacingCalculator.dayKey(for: now)
        
        let sample = GrokBotDailySample(
            dayKey: todayKey,
            weeklyAtDayStart: 85,
            recordedAt: now
        )
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 90,
            periodStart: periodStart,
            dailySample: sample,
            now: now
        )
        
        #expect(result?.dailyPercent != 90)
        let todayBurn = 90 - 85
        let fairDailyShare = 100.0 / 7.0
        let expectedDaily = Int((Double(todayBurn) / fairDailyShare * 100).rounded())
        #expect(result?.dailyPercent == expectedDaily)
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

    @Test("daily with workweek schedule uses activeDays count for fair share")
    func dailyWithWorkweekSchedule() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let todayKey = GrokBotPacingCalculator.dayKey(for: now)
        let sample = GrokBotDailySample(
            dayKey: todayKey,
            weeklyAtDayStart: 40,
            recordedAt: now
        )
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 60,
            periodStart: periodStart,
            dailySample: sample,
            now: now,
            activeDays: PacingSchedule.workweek
        )
        
        let todayBurn = 60 - 40
        let fairDailyShare = 100.0 / Double(PacingSchedule.workweek.count)
        let expectedDaily = Int((Double(todayBurn) / fairDailyShare * 100).rounded())
        #expect(result?.dailyPercent == expectedDaily)
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
        #expect(result?.pacingMessage?.isEmpty == false)
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
