import WidgetKit
import SwiftUI

/// Primary Grok Bot weekly usage widget (small + medium).
struct GrokBotUsageWidget: Widget {
    let kind: String = "GrokBotUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GrokBotWidgetProvider()) { entry in
            GrokBotWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.grokBot.title"))
        .description(String(localized: "widget.grokBot.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TokenEaterWidgetBundle: WidgetBundle {
    var body: some Widget {
        GrokBotUsageWidget()
    }
}
