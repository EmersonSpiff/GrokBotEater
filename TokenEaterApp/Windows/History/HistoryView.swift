import SwiftUI

/// History space — Local Grok Bot usage tracking
struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @State private var chartData: [(date: Date, weeklyPercent: Int, activeAgents: Int)] = []
    private let historyService = GrokBotHistoryService()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader

                if !chartData.isEmpty {
                    weeklyUsageChart
                    activeAgentsChart
                } else {
                    emptyStateCard
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadChartData()
        }
    }
    
    private func loadChartData() {
        chartData = historyService.chartData(days: 7)
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Grok Bot History")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
            Text("Last 7 days • Local snapshots recorded hourly")
                .font(.system(size: 13))
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }

    private var weeklyUsageChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Usage")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
            
            GeometryReader { geo in
                let maxPercent = chartData.map { $0.weeklyPercent }.max() ?? 100
                let width = geo.size.width
                let barWidth = width / CGFloat(max(chartData.count, 1)) - 4
                
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(chartData.enumerated()), id: \.offset) { index, point in
                        VStack(spacing: 4) {
                            Text("\(point.weeklyPercent)%")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DS.Palette.textSecondary)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(
                                    colors: [DS.Palette.brandPrimary.opacity(0.7), DS.Palette.brandPrimary],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .frame(width: barWidth, height: max(4, geo.size.height * CGFloat(point.weeklyPercent) / CGFloat(maxPercent)))
                            
                            Text(point.date.formatted(.dateTime.month().day()))
                                .font(.system(size: 8))
                                .foregroundStyle(DS.Palette.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 120)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Palette.bgElevated.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Palette.glassBorder, lineWidth: 1)
                )
        )
    }
    
    private var activeAgentsChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Agents")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
            
            GeometryReader { geo in
                let maxAgents = max(chartData.map { $0.activeAgents }.max() ?? 1, 1)
                let width = geo.size.width
                let barWidth = width / CGFloat(max(chartData.count, 1)) - 4
                
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(chartData.enumerated()), id: \.offset) { index, point in
                        VStack(spacing: 4) {
                            Text("\(point.activeAgents)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DS.Palette.textSecondary)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(
                                    colors: [DS.Palette.accentHistory.opacity(0.7), DS.Palette.accentHistory],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .frame(width: barWidth, height: max(4, geo.size.height * CGFloat(point.activeAgents) / CGFloat(maxAgents)))
                            
                            Text(point.date.formatted(.dateTime.month().day()))
                                .font(.system(size: 8))
                                .foregroundStyle(DS.Palette.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 100)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Palette.bgElevated.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Palette.glassBorder, lineWidth: 1)
                )
        )
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Palette.accentHistory)
                Text("Building History")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
            }
            Text("GrokBotEater records hourly snapshots of your weekly usage and active agents. Check back soon to see your trends.")
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Palette.accentHistory.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Palette.accentHistory.opacity(0.25), lineWidth: 1)
                )
        )
    }
}
