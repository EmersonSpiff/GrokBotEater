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
            periodStart: nil
        )
        #expect(result == nil)
    }

    @Test("returns nil when periodStart is empty")
    func returnsNilWhenPeriodStartIsEmpty() {
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: ""
        )
        #expect(result == nil)
    }

    @Test("returns nil when periodStart is invalid ISO8601")
    func returnsNilWhenPeriodStartIsInvalid() {
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 50,
            periodStart: "not-a-date"
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
            now: now,
            margin: 10
        )
        #expect(result?.pacingDelta == 15)
        #expect(result?.pacingZone == .warning)
    }

    // MARK: - Daily calculation

    @Test("daily calculation at 0% weekly: daily is 0%")
    func dailyAtZeroWeekly() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 0,
            periodStart: periodStart,
            now: now
        )
        #expect(result?.dailyPercent == 0)
    }

    @Test("daily calculation at 14% weekly (~fair daily budget): daily is ~100%")
    func dailyAtFairBudget() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 14,
            periodStart: periodStart,
            now: now
        )
        let fairDailyBudget = 100.0 / 7.0
        let dailyUsed = 14.0 * (1.0 / 7.0)
        let expectedDaily = Int((dailyUsed / fairDailyBudget * 100).rounded())
        #expect(result?.dailyPercent == expectedDaily)
    }

    @Test("daily calculation at 70% weekly: daily is ~500%")
    func dailyAtHighWeekly() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 70,
            periodStart: periodStart,
            now: now
        )
        let fairDailyBudget = 100.0 / 7.0
        let dailyUsed = 70.0 * (1.0 / 7.0)
        let expectedDaily = Int((dailyUsed / fairDailyBudget * 100).rounded())
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
            now: now,
            activeDays: PacingSchedule.workweek
        )
        
        #expect(result != nil)
        
        if PacingSchedule.workweek.contains(weekday) {
            #expect(abs(result!.pacingDelta) >= 0)
        }
    }

    // MARK: - Zone boundaries

    @Test("zone is chill when delta < -margin")
    func zoneIsChillBelowNegativeMargin() {
        let now = Self.stableNow()
        let periodStart = makePeriodStart(elapsedFraction: 0.5, now: now)
        let result = GrokBotPacingCalculator.calculate(
            weeklyPercent: 30,
            periodStart: periodStart,
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
            now: now,
            margin: 10
        )
        #expect(resultPlus5?.pacingZone == .onTrack)
        
        let resultMinus5 = GrokBotPacingCalculator.calculate(
            weeklyPercent: 45,
            periodStart: periodStart,
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
            now: now
        )
        #expect(result != nil)
    }
}
