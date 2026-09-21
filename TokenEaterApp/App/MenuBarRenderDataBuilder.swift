import Foundation

@MainActor
extension MenuBarRenderer.RenderData {
    /// Builds render data from the live stores. Shared by the status bar
    /// (`StatusBarController`) and the menu bar editor's live preview, so both
    /// render the exact same pixels for the current composition.
    static func live(
        usage: UsageStore,
        grokBotUsage: GrokBotUsageStore,
        theme: ThemeStore,
        settings: SettingsStore,
        vendor: VendorStatusStore
    ) -> MenuBarRenderer.RenderData {
        MenuBarRenderer.RenderData(
            composition: settings.menuBarComposition,
            fiveHourPct: usage.fiveHourPct,
            sevenDayPct: usage.sevenDayPct,
            sonnetPct: usage.sonnetPct,
            grokBotPct: grokBotUsage.usagePercent,
            hasGrokBot: grokBotUsage.hasGrokBot,
            weeklyPacingDelta: Int(usage.pacingResult?.delta ?? 0),
            weeklyPacingZone: usage.pacingResult?.zone ?? .onTrack,
            hasWeeklyPacing: usage.pacingResult != nil,
            sessionPacingDelta: Int(usage.fiveHourPacing?.delta ?? 0),
            sessionPacingZone: usage.fiveHourPacing?.zone ?? .onTrack,
            hasSessionPacing: usage.fiveHourPacing != nil,
            fablePacingDelta: Int(usage.fablePacing?.delta ?? 0),
            fablePacingZone: usage.fablePacing?.zone ?? .onTrack,
            hasFablePacing: usage.fablePacing != nil,
            // Claude UsageStore refresh is disabled (Keychain spam); treat Grok Bot as configured.
            hasConfig: grokBotUsage.hasGrokBot || grokBotUsage.lastUpdate != nil || grokBotUsage.usagePercent > 0,
            // Prefer Grok Bot error state so a missing Claude token does not collapse the menu bar.
            hasError: grokBotUsage.errorState.hasError,
            isAwaitingRefresh: grokBotUsage.isLoading,
            themeColors: theme.current,
            thresholds: theme.thresholds,
            menuBarMonochrome: theme.menuBarMonochrome,
            fiveHourReset: usage.fiveHourReset,
            fiveHourResetAbsolute: usage.fiveHourResetAbsolute,
            fiveHourResetDate: usage.lastUsage?.fiveHour?.resetsAtDate,
            sevenDayResetDate: usage.lastUsage?.sevenDay?.resetsAtDate,
            sonnetResetDate: usage.lastUsage?.sevenDaySonnet?.resetsAtDate,
            hasFiveHourBucket: usage.lastUsage?.fiveHour != nil,
            resetTextColorHex: settings.resetTextColorHex,
            sessionPeriodColorHex: settings.sessionPeriodColorHex,
            smartResetColor: settings.smartColorEnabled,
            smartColorProfile: settings.smartColorProfile,
            pacingMargin: Double(settings.pacingMargin),
            fablePct: usage.fablePct,
            hasFable: usage.hasFable,
            fableResetDate: usage.lastUsage?.sevenDayFable?.resetsAtDate,
            outageActive: settings.statusShowMenuBarBadge && vendor.isDegraded,
            outageHealth: vendor.worstHealth,
            nextPollSeconds: vendor.nextPollDate.map { max(0, Int(ceil($0.timeIntervalSinceNow))) },
            extraCreditsPct: usage.extraCreditsPct,
            hasExtraCredits: usage.hasExtraCredits
        )
    }
}
