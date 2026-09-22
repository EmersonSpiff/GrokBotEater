import SwiftUI
import WidgetKit

/// Small + medium Grok Bot weekly usage widget.
/// Reads only the snapshot the main app writes to shared.json (no network).
struct GrokBotWidgetView: View {
    let entry: GrokBotUsageEntry

    @Environment(\.widgetFamily) var family
    private var theme: ThemeColors { WidgetTheme.theme }
    private var thresholds: UsageThresholds { WidgetTheme.thresholds }

    /// TokenEater-style weekly reset label: "Mon 14:08"
    private var weeklyResetSubtitle: String {
        guard let reset = Self.resetDate(fromPeriodStart: entry.currentPeriodStart) else {
            return String(localized: "widget.grokBot.weekly")
        }
        return Self.resetDateFormatter.string(from: reset)
    }

    private static let resetDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()


    /// Matches GrokBotUsageStore default / Settings floor (300s).
    private static let appRefreshInterval: TimeInterval = 300

    private static func nextAppRefreshDate(lastSync: Date?) -> Date? {
        guard let lastSync else {
            return Date().addingTimeInterval(appRefreshInterval)
        }
        let next = lastSync.addingTimeInterval(appRefreshInterval)
        return next > Date() ? next : Date().addingTimeInterval(15)
    }

    private static func resetDate(fromPeriodStart raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let start = fractional.date(from: raw) ?? plain.date(from: raw)
        guard let start else { return nil }
        return start.addingTimeInterval(7 * 24 * 3600)
    }


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
        // Force opaque dark chrome. Theme widgetText is white; if macOS falls back
        // to a light system background, white-on-white looks like an empty rectangle.
        .modifier(WidgetBackgroundModifier(backgroundColor: Color(hex: "#111111")))
    }

    private var smallContent: some View {
        let pct = entry.usagePercent
        let color = theme.gaugeColor(for: min(Double(pct), 100), thresholds: thresholds)
        let gradient = theme.gaugeGradient(for: min(Double(pct), 100), thresholds: thresholds)
        
        let loopCount = min(4, max(1, Int(ceil(Double(pct) / 100))))
        let remainder = Double(pct).truncatingRemainder(dividingBy: 100)
        let currentLoopFraction = remainder == 0 && pct > 0 ? 1.0 : remainder / 100

        return VStack(spacing: 0) {
            WidgetHeader("widget.grokBot.eater")
            Spacer(minLength: 4)
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
            Spacer(minLength: 4)
            Text("widget.grokBot.weekly")
                .font(WidgetTokens.micro)
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        thresholds: thresholds,
                        style: .dayCycles
                    )
                }
                
                CircularGrokBotView(
                    label: String(localized: "widget.grokBot.weekly.label"),
                    utilization: Double(entry.usagePercent),
                    subtitle: weeklyResetSubtitle,
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

            // Countdown to next local app refresh (not weekly Grok reset).
            HStack(spacing: 5) {
                if let next = Self.nextAppRefreshDate(lastSync: entry.lastSync) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.35))
                    Text(next, style: .timer)
                        .font(.system(size: 8, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.45))
                        .multilineTextAlignment(.leading)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    enum Style {
        /// Threshold colors only (Weekly).
        case standard
        /// Day-cycle burn: completed days fill the ring; current day paints
        /// forward from 12 o’clock; burn marker rides the leading edge;
        /// color seam (gradient) stays at the top between prior and current day.
        case dayCycles
    }

    let label: String
    let utilization: Double
    let subtitle: String
    var theme: ThemeColors
    var thresholds: UsageThresholds
    var style: Style = .standard

    /// Day-cycle palette hex (green → yellow → orange → red → burgundy).
    private var cycleHexes: [String] {
        [
            theme.gaugeNormal,   // day 1 — green
            "#EAB308",           // day 2 — yellow
            theme.gaugeWarning,  // day 3 — orange
            theme.gaugeCritical, // day 4 — red
            "#7F1D1D",           // day 5+ — burgundy
        ]
    }

    private var cycleColors: [Color] {
        cycleHexes.map { Color(hex: $0) }
    }

    /// Fully completed day-cycles (100 → 1, 250 → 2).
    private var fullDaysCompleted: Int {
        Int(floor(max(utilization, 0) / 100))
    }

    /// Progress through the in-progress day-cycle, 0…1 (0 at exact 100/200/…).
    private var currentFraction: Double {
        let u = max(utilization, 0) / 100
        return u - floor(u)
    }

    /// Color index for the arc currently being painted (0 = day 1).
    private var paintCycleIndex: Int {
        min(cycleHexes.count - 1, fullDaysCompleted)
    }

    /// Color index for the filled prior day (nil on day 1).
    private var priorCycleIndex: Int? {
        let d = fullDaysCompleted
        guard d >= 1 else { return nil }
        return min(cycleHexes.count - 1, d - 1)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 4.5)

                switch style {
                case .standard:
                    standardRings
                case .dayCycles:
                    dayCycleRings
                }

                Text(formatPercentage(utilization))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
            }
            .frame(width: 50, height: 50)

            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(Color.white.opacity(0.9))
                Text(subtitle)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Standard (Weekly)

    private var standardRings: some View {
        let loops = min(4, max(1, Int(ceil(max(utilization, 0) / 100))))
        return ZStack {
            ForEach(0..<loops, id: \.self) { loopIndex in
                let isCurrent = loopIndex == loops - 1
                let fraction = isCurrent ? currentFraction : 1.0
                let intensity = 1.0 - (Double(loopIndex) * 0.15)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        theme.gaugeGradient(for: min(utilization, 100), thresholds: thresholds)
                            .opacity(max(0.4, intensity)),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    // MARK: - Day-cycle burn

    private var dayCycleRings: some View {
        let fraction = currentFraction
        let paintHex = cycleHexes[paintCycleIndex]
        let paint = Color(hex: paintHex)
        let priorHex = priorCycleIndex.map { cycleHexes[$0] }
        let prior = priorHex.map { Color(hex: $0) }
        // ~90° total seam, centered on 12 o’clock (half left / half right).
        let seamSpan = 0.25
        let half = seamSpan / 2
        let segments = Self.centeredSeamSegments(
            priorHex: priorHex,
            paintHex: paintHex,
            fraction: fraction,
            half: half,
            steps: 12
        )

        return ZStack {
            if let prior {
                Circle()
                    .stroke(prior, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }

            // Day 1 (no prior): paint from top to marker.
            if prior == nil, fraction > 0.001 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(paint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            // Later days: solid paint only to the RIGHT of the centered seam.
            if prior != nil, fraction > half + 0.001 {
                Circle()
                    .trim(from: half, to: fraction)
                    .stroke(paint, style: StrokeStyle(lineWidth: 5, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }

            // Centered top seam (stepped colors — WidgetKit-safe).
            ForEach(segments) { seg in
                Circle()
                    .trim(from: seg.from, to: seg.to)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: 5.5, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }

            if utilization > 0.5 {
                Capsule()
                    .fill(Color.black)
                    .frame(width: 2.5, height: 8)
                    .shadow(color: .white.opacity(0.35), radius: 0.5)
                    .offset(y: -25)
                    .rotationEffect(.degrees(fraction * 360))
            }
        }
    }

    private struct SeamSegment: Identifiable {
        let id: Int
        let from: Double
        let to: Double
        let color: Color
    }

    /// Build prior→paint segments straddling 12 o’clock (negative = into prior / left).
    private static func centeredSeamSegments(
        priorHex: String?,
        paintHex: String,
        fraction: Double,
        half: Double,
        steps: Int
    ) -> [SeamSegment] {
        guard let priorHex, fraction > 0.001 else { return [] }
        let total = max(steps, 2)
        var out: [SeamSegment] = []
        var id = 0
        for step in 0..<total {
            let t0 = Double(step) / Double(total)
            let t1 = Double(step + 1) / Double(total)
            // Position along seam in [-half, +half]
            let p0 = -half + t0 * (half * 2)
            let p1 = -half + t1 * (half * 2)
            let mix = (t0 + t1) / 2 // center of step
            let color = lerpHex(priorHex, paintHex, mix)

            if p1 <= 0 {
                // Entirely on the prior side of top (trim near 1.0).
                let f = 1.0 + p0
                let e = 1.0 + p1
                if e > f { out.append(SeamSegment(id: id, from: f, to: e, color: color)); id += 1 }
            } else if p0 >= 0 {
                // Entirely on the paint side of top.
                let e = min(p1, fraction)
                if e > p0 { out.append(SeamSegment(id: id, from: p0, to: e, color: color)); id += 1 }
            } else {
                // Crosses the top: split into [p0,0] and [0,p1].
                let fBack = 1.0 + p0
                if fBack < 1.0 {
                    out.append(SeamSegment(id: id, from: fBack, to: 1.0, color: color)); id += 1
                }
                let eFwd = min(p1, fraction)
                if eFwd > 0 {
                    out.append(SeamSegment(id: id, from: 0, to: eFwd, color: color)); id += 1
                }
            }
        }
        return out
    }

    /// Mix two sRGB hex colors (no AngularGradient / NSColor — WidgetKit archives these reliably).
    private static func lerpHex(_ a: String, _ b: String, _ t: Double) -> Color {
        let t = min(1, max(0, t))
        func rgb(_ hex: String) -> (Double, Double, Double) {
            let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            var value: UInt64 = 0
            Scanner(string: h).scanHexInt64(&value)
            return (
                Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255
            )
        }
        let (ar, ag, ab) = rgb(a)
        let (br, bg, bb) = rgb(b)
        return Color(
            red: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t
        )
    }

    private func formatPercentage(_ value: Double) -> String {
        if value > 100 {
            return String(format: "%.1f×", value / 100)
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
        // Full ring = 100pts ahead/behind. No artificial 0.7 cap (that made +70 look half-empty).
        return remainder == 0 && absDelta > 0 ? 1.0 : remainder / 100
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
