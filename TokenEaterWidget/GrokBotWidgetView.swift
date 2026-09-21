import SwiftUI
import WidgetKit

/// Small + medium Grok Bot weekly usage widget.
/// Reads only the snapshot the main app writes to shared.json (no network).
struct GrokBotWidgetView: View {
    let entry: GrokBotUsageEntry

    @Environment(\.widgetFamily) var family
    private var theme: ThemeColors { WidgetTheme.theme }
    private var thresholds: UsageThresholds { WidgetTheme.thresholds }

    var body: some View {
        Group {
            if let error = entry.error, !entry.shouldDrawRing {
                emptyContent(error)
            } else if entry.shouldDrawRing {
                switch family {
                case .systemMedium:
                    mediumContent
                default:
                    smallContent
                }
            } else {
                emptyContent(String(localized: "widget.grokBot.unavailable"))
            }
        }
        .widgetURL(URL(string: "grokboteater://open"))
        .modifier(WidgetBackgroundModifier())
    }

    private var smallContent: some View {
        let pct = entry.usagePercent
        let color = theme.gaugeColor(for: Double(pct), thresholds: thresholds)
        let gradient = theme.gaugeGradient(for: Double(pct), thresholds: thresholds)

        return VStack(spacing: 0) {
            WidgetHeader("widget.grokBot")
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .stroke(.white.opacity(WidgetTokens.trackOpacity), lineWidth: WidgetTokens.ringSmall)
                Circle()
                    .trim(from: 0, to: min(Double(pct), 100) / 100)
                    .stroke(gradient, style: StrokeStyle(lineWidth: WidgetTokens.ringSmall, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.32), radius: 5)
                HeroPercent(pct)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            Spacer(minLength: 8)
            Text("widget.grokBot.weekly")
                .font(WidgetTokens.micro)
                .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.secondary))
        }
    }

    private var mediumContent: some View {
        let pct = entry.usagePercent
        let color = theme.gaugeColor(for: Double(pct), thresholds: thresholds)
        let gradient = theme.gaugeGradient(
            for: Double(pct), thresholds: thresholds, startPoint: .leading, endPoint: .trailing
        )

        return VStack(alignment: .leading, spacing: 10) {
            WidgetHeader("widget.grokBot") {
                if let last = entry.lastSync {
                    Text(last, style: .relative)
                        .font(WidgetTokens.micro)
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
                }
            }

            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(WidgetTokens.trackOpacity), lineWidth: WidgetTokens.ringMedium)
                    Circle()
                        .trim(from: 0, to: min(Double(pct), 100) / 100)
                        .stroke(gradient, style: StrokeStyle(lineWidth: WidgetTokens.ringMedium, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: color.opacity(0.32), radius: 4)
                    HeroPercent(pct, font: WidgetTokens.heroMedium)
                }
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 4) {
                    Text("widget.grokBot.appName")
                        .font(WidgetTokens.body)
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.primary))
                    Text("widget.grokBot.weekly")
                        .font(WidgetTokens.micro)
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.secondary))
                    if let period = entry.currentPeriodStart, !period.isEmpty {
                        Text(period)
                            .font(WidgetTokens.microMono)
                            .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func emptyContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader("widget.grokBot")
            Spacer(minLength: 4)
            Text(message)
                .font(WidgetTokens.body)
                .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.secondary))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
