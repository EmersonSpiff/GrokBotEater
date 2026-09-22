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
    
    let dailyPercent: Int?
    let pacingDelta: Double?
    let pacingZone: String?
    let pacingMessage: String?

    init(
        date: Date,
        usagePercent: Int = 0,
        hasGrokBot: Bool = false,
        shouldDrawRing: Bool = false,
        currentPeriodStart: String? = nil,
        lastSync: Date? = nil,
        error: String? = nil,
        dailyPercent: Int? = nil,
        pacingDelta: Double? = nil,
        pacingZone: String? = nil,
        pacingMessage: String? = nil
    ) {
        self.date = date
        self.usagePercent = usagePercent
        self.hasGrokBot = hasGrokBot
        self.shouldDrawRing = shouldDrawRing
        self.currentPeriodStart = currentPeriodStart
        self.lastSync = lastSync
        self.error = error
        self.dailyPercent = dailyPercent
        self.pacingDelta = pacingDelta
        self.pacingZone = pacingZone
        self.pacingMessage = pacingMessage
    }

    static var placeholder: GrokBotUsageEntry {
        GrokBotUsageEntry(
            date: Date(),
            usagePercent: 42,
            hasGrokBot: true,
            shouldDrawRing: true,
            lastSync: Date(),
            dailyPercent: 10,
            pacingDelta: 2.5,
            pacingZone: "onTrack",
            pacingMessage: "Steady pace"
        )
    }

    static var empty: GrokBotUsageEntry {
        GrokBotUsageEntry(
            date: Date(),
            error: String(localized: "widget.grokBot.empty")
        )
    }
}
