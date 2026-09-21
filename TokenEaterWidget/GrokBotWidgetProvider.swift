import WidgetKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.emersonspiff.grokboteater.app.widget", category: "GrokBotProvider")

struct GrokBotWidgetProvider: TimelineProvider {
    private let sharedFile = SharedFileService()

    func placeholder(in context: Context) -> GrokBotUsageEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (GrokBotUsageEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
        } else {
            completion(fetchEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GrokBotUsageEntry>) -> Void) {
        let entry = fetchEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func fetchEntry() -> GrokBotUsageEntry {
        sharedFile.invalidateCache()
        guard let snapshot = sharedFile.grokBotSnapshot else {
            logger.info("No Grok Bot snapshot in shared file")
            return .empty
        }
        return GrokBotUsageEntry(
            date: Date(),
            usagePercent: snapshot.usagePercent,
            hasGrokBot: snapshot.hasGrokBot,
            shouldDrawRing: snapshot.shouldDrawRing,
            currentPeriodStart: snapshot.currentPeriodStart,
            lastSync: snapshot.lastSync
        )
    }
}
