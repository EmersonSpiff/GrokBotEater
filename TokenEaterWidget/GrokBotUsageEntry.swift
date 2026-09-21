import WidgetKit
import Foundation

struct GrokBotUsageEntry: TimelineEntry {
    let date: Date
    let usagePercent: Int
    let hasGrokBot: Bool
    let shouldDrawRing: Bool
    let currentPeriodStart: String?
    let lastSync: Date?
    let error: String?

    init(
        date: Date,
        usagePercent: Int = 0,
        hasGrokBot: Bool = false,
        shouldDrawRing: Bool = false,
        currentPeriodStart: String? = nil,
        lastSync: Date? = nil,
        error: String? = nil
    ) {
        self.date = date
        self.usagePercent = usagePercent
        self.hasGrokBot = hasGrokBot
        self.shouldDrawRing = shouldDrawRing
        self.currentPeriodStart = currentPeriodStart
        self.lastSync = lastSync
        self.error = error
    }

    static var placeholder: GrokBotUsageEntry {
        GrokBotUsageEntry(
            date: Date(),
            usagePercent: 42,
            hasGrokBot: true,
            shouldDrawRing: true,
            lastSync: Date()
        )
    }

    static var empty: GrokBotUsageEntry {
        GrokBotUsageEntry(
            date: Date(),
            error: String(localized: "widget.grokBot.empty")
        )
    }
}
