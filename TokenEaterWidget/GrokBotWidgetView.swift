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
        let color = theme.gaugeColor(for: min(Double(pct), 100), thresholds: thresholds)
        let gradient = theme.gaugeGradient(for: min(Double(pct), 100), thresholds: thresholds)
        
        let loopCount = max(1, Int(ceil(Double(pct) / 100)))
        let remainder = Double(pct).truncatingRemainder(dividingBy: 100)
        let currentLoopFraction = remainder == 0 && pct > 0 ? 1.0 : remainder / 100

        return VStack(spacing: 0) {
            WidgetHeader("widget.grokBot.eater")
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .stroke(.white.opacity(WidgetTokens.trackOpacity), lineWidth: WidgetTokens.ringSmall)
                
                ForEach(0..<loopCount, id: \.self) { loopIndex in
                    let isCurrentLoop = loopIndex == loopCount - 1
                    let fraction = isCurrentLoop ? currentLoopFraction : 1.0
                    let intensity = 1.0 - (Double(loopIndex) * 0.15)
                    
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            gradient.opacity(max(0.4, intensity)),
                            style: StrokeStyle(lineWidth: WidgetTokens.ringSmall, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: color.opacity(0.32), radius: 5)
                }
                
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

    private var baseGradient: LinearGradient {
        theme.gaugeGradient(for: min(utilization, 100), thresholds: thresholds)
    }
    
    private var baseColor: Color {
        theme.gaugeColor(for: min(utilization, 100), thresholds: thresholds)
    }
    
    private func loopCount() -> Int {
        max(1, Int(ceil(utilization / 100)))
    }
    
    private func currentLoopFraction() -> Double {
        let remainder = utilization.truncatingRemainder(dividingBy: 100)
        return remainder == 0 && utilization > 0 ? 1.0 : remainder / 100
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 4.5)

                ForEach(0..<loopCount(), id: \.self) { loopIndex in
                    let isCurrentLoop = loopIndex == loopCount() - 1
                    let fraction = isCurrentLoop ? currentLoopFraction() : 1.0
                    let intensity = 1.0 - (Double(loopIndex) * 0.15)
                    
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            baseGradient.opacity(max(0.4, intensity)),
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }

                Text(formatPercentage(utilization))
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
    
    private func formatPercentage(_ value: Double) -> String {
        if value > 100 {
            let multiplier = value / 100
            return String(format: "%.1f×", multiplier)
        }
        return "\(Int(value))%"
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
    
    private func loopCount() -> Int {
        let absDelta = abs(delta)
        return max(1, Int(ceil(absDelta / 100)))
    }
    
    private func currentLoopFraction() -> Double {
        let absDelta = abs(delta)
        let remainder = absDelta.truncatingRemainder(dividingBy: 100)
        let fraction = remainder == 0 && absDelta > 0 ? 1.0 : remainder / 100
        return min(fraction * 0.7, 0.7)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 4.5)

                ForEach(0..<loopCount(), id: \.self) { loopIndex in
                    let isCurrentLoop = loopIndex == loopCount() - 1
                    let fraction = isCurrentLoop ? currentLoopFraction() : 0.7
                    let intensity = 1.0 - (Double(loopIndex) * 0.15)
                    
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            ringGradient.opacity(max(0.4, intensity)),
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }

                let sign = delta >= 0 ? "+" : ""
                Text(formatDelta(delta))
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
    
    private func formatDelta(_ value: Double) -> String {
        let absValue = abs(value)
        let sign = value >= 0 ? "+" : "-"
        
        if absValue > 100 {
            let multiplier = absValue / 100
            return String(format: "%@%.1f×", sign, multiplier)
        }
        return "\(sign)\(Int(absValue))%"
    }
}
