import WidgetKit
import SwiftUI

/// Primary Grok Bot weekly usage widget (small + medium).
struct GrokBotUsageWidget: Widget {
    let kind: String = "GrokBotEaterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GrokBotWidgetProvider()) { entry in
            GrokBotWidgetView(entry: entry)
        }
        .configurationDisplayName("Grok Bot Eater")
        .description("Daily, weekly, and pacing dials for your Cursor Grok Bot sand usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TokenEaterWidgetBundle: WidgetBundle {
    var body: some Widget {
        GrokBotUsageWidget()
    }
}
