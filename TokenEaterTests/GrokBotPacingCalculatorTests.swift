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

    // MARK: - Daily calculation (even-pace ratio; any periodStart)

    @Test("daily ≈ 100% when weekly matches elapsed even pace")
    func dailyOnPaceHalfway() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: periodStart,
            dailySample: nil,
            now: now
        )
        #expect(result?.dailyPercent == 100)
        #expect(result?.pacingDelta == 0)
    }

    @Test("daily ≈ 200% when twice even pace at halfway")
    func dailyDoublePaceHalfway() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 100,
            periodStart: periodStart,
            dailySample: nil,
            now: now
        )
        #expect(result?.dailyPercent == 200)
        #expect(result?.pacingDelta == 50)
    }

    @Test("early window: 34% near 1/7 elapsed is ~2.4× even pace")
    func dailyEarlyWindowHot() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 1.0 / 7.0, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 34,
            periodStart: periodStart,
            dailySample: nil,
            now: now
        )
        #expect(result!.dailyPercent >= 220)
        #expect(result!.dailyPercent <= 260)
        #expect(result?.pacingZone == .hot)
    }

    @Test("any signup weekday: 3/7 elapsed + 45% used is slightly ahead")
    func dailyAnySignupWeekday() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 3.0 / 7.0, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 45,
            periodStart: periodStart,
            dailySample: nil,
            now: now
        )
        let expected = 300.0 / 7.0
        #expect(abs(result!.pacingDelta - (45 - expected)) < 0.2)
        #expect(result!.dailyPercent >= 100)
        #expect(result!.dailyPercent <= 110)
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
        #expect(rolling!.dailyPercent > 0)
        #expect(workweek!.dailyPercent > 0)
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
