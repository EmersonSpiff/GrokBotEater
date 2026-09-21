import Foundation

/// Single source of truth mapping an element kind to its live values.
///
/// Before the composable popover, every layout call site hardcoded its own
/// `(pct, resetDate, windowDuration)` tuple; centralising the mapping
/// guarantees every cell feeds `GaugeColorResolver` the same inputs, so Smart
/// Color / threshold coloring can never silently diverge between styles.
@MainActor
enum PopoverMetricResolver {
    struct UsageSnapshot {
        let label: String
        let pct: Int
        let resetDate: Date?
        /// Formatted countdown ("2h 15m"). Empty when the metric has no
        /// reset window (Extra Credits) or no data yet.
        let resetText: String
        /// 0 = no rolling window -> threshold coloring (Extra Credits).
        let windowDuration: TimeInterval
    }

    static func usageSnapshot(
        for kind: PopoverElementKind,
        usage: UsageStore,
        grokBot: GrokBotUsageStore
    ) -> UsageSnapshot? {
        switch kind {
        case .grokBot:
            let resetDate = grokBot.nextResetDate
            return UsageSnapshot(
                label: String(localized: "metric.grokBot"),
                pct: grokBot.usagePercent,
                resetDate: resetDate,
                resetText: resetDate != nil
                    ? ResetCountdownFormatter.weekly(from: resetDate).relative
                    : "",
                windowDuration: resetDate != nil ? 7 * 86_400 : 0
            )
        case .session:
            return UsageSnapshot(
                label: String(localized: "metric.session"),
                pct: usage.fiveHourPct,
                resetDate: usage.lastUsage?.fiveHour?.resetsAtDate,
                resetText: usage.fiveHourReset,
                windowDuration: 5 * 3600
            )
        case .weekly:
            return UsageSnapshot(
                label: String(localized: "metric.weekly"),
                pct: usage.sevenDayPct,
                resetDate: usage.lastUsage?.sevenDay?.resetsAtDate,
                resetText: usage.sevenDayReset,
                windowDuration: 7 * 86_400
            )
        case .sonnet:
            return weeklySnapshot(
                label: String(localized: "metric.sonnet"),
                pct: usage.sonnetPct,
                resetDate: usage.lastUsage?.sevenDaySonnet?.resetsAtDate
            )
        case .fable:
            return weeklySnapshot(
                label: String(localized: "metric.fable"),
                pct: usage.fablePct,
                resetDate: usage.lastUsage?.sevenDayFable?.resetsAtDate
            )
        case .extraCredits:
            // No reset window -> GaugeColorResolver falls back to threshold
            // coloring (windowDuration == 0), same contract as before.
            return UsageSnapshot(
                label: String(localized: "metric.extraCredits"),
                pct: usage.extraCreditsPct,
                resetDate: nil,
                resetText: "",
                windowDuration: 0
            )
        default:
            return nil
        }
    }

    static func pacing(for kind: PopoverElementKind, usage: UsageStore) -> PacingResult? {
        switch kind {
        case .sessionPacing: return usage.fiveHourPacing
        case .weeklyPacing: return usage.pacingResult
        case .fablePacing: return usage.fablePacing
        default: return nil
        }
    }

    /// Presence gating: elements whose data doesn't exist on this account (or
    /// right now) render nothing and their row recompacts, matching the old
    /// satellite behavior.
    ///
    /// Grok Bot-first: Claude usage / pacing / plan badge never show. Utilities
    /// and actions stay available.
    static func isAvailable(
        _ kind: PopoverElementKind,
        usage: UsageStore,
        grokBot: GrokBotUsageStore
    ) -> Bool {
        switch kind {
        case .grokBot:
            return grokBot.hasGrokBot || grokBot.lastUpdate != nil || grokBot.usagePercent > 0
        case .session, .weekly, .sonnet, .fable, .extraCredits,
             .sessionPacing, .weeklyPacing, .fablePacing:
            return false
        case .planBadge:
            return false
        case .watchers, .timestamp, .openButton, .quitButton, .refreshButton:
            return true
        }
    }

    private static func weeklySnapshot(label: String, pct: Int, resetDate: Date?) -> UsageSnapshot {
        UsageSnapshot(
            label: label,
            pct: pct,
            resetDate: resetDate,
            resetText: resetDate != nil ? ResetCountdownFormatter.weekly(from: resetDate).relative : "",
            windowDuration: 7 * 86_400
        )
    }
}
