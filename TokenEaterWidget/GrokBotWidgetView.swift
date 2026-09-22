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
            WidgetHeader("widget.grokBot.eater")
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
        VStack(spacing: 0) {
            WidgetHeader("widget.grokBot.eater")
                .padding(.bottom, 14)

            HStack(spacing: 0) {
                if let dailyPct = entry.dailyPercent {
                    CircularGrokBotView(
                        label: String(localized: "widget.grokBot.daily"),
                        utilization: Double(dailyPct),
                        subtitle: String(localized: "widget.grokBot.daily.subtitle"),
                        theme: theme,
                        thresholds: thresholds
                    )
                }
                
                CircularGrokBotView(
                    label: String(localized: "widget.grokBot.weekly.label"),
                    utilization: Double(entry.usagePercent),
                    subtitle: String(localized: "widget.grokBot.weekly"),
                    theme: theme,
                    thresholds: thresholds
                )
                
                if let delta = entry.pacingDelta,
                   let zoneRaw = entry.pacingZone,
                   let zone = PacingZone(rawValue: zoneRaw),
                   let message = entry.pacingMessage {
                    CircularGrokBotPacingView(
                        delta: delta,
                        zone: zone,
                        message: message,
                        theme: theme
                    )
                }
            }

            Spacer(minLength: 6)

            HStack {
                if let last = entry.lastSync {
                    Text(last, style: .relative)
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(0.3))
                } else {
                    Text(entry.date, style: .relative)
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(0.3))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 2)
    }

    private func emptyContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader("widget.grokBot.eater")
            Spacer(minLength: 4)
            Text(message)
                .font(WidgetTokens.body)
                .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.secondary))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct CircularGrokBotView: View {
    let label: String
    let utilization: Double
    let subtitle: String
    var theme: ThemeColors
    var thresholds: UsageThresholds

    private var ringGradient: LinearGradient {
        theme.gaugeGradient(for: utilization, thresholds: thresholds)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 4.5)

                Circle()
                    .trim(from: 0, to: min(utilization, 100) / 100)
                    .stroke(ringGradient, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(Int(utilization))%")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: theme.widgetText))
            }
            .frame(width: 50, height: 50)

            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CircularGrokBotPacingView: View {
    let delta: Double
    let zone: PacingZone
    let message: String
    var theme: ThemeColors

    private var ringColor: Color {
        theme.pacingColor(for: zone)
    }

    private var ringGradient: LinearGradient {
        theme.pacingGradient(for: zone)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 4.5)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(ringGradient, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                let sign = delta >= 0 ? "+" : ""
                Text("\(sign)\(Int(delta))%")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ringColor)
            }
            .frame(width: 50, height: 50)

            VStack(spacing: 2) {
                Text("pacing.label")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.85))
                Text(message)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(ringColor.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
