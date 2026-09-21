import SwiftUI

/// History space — Claude JSONL browser retired for GrokBotEater.
/// Placeholder until Grok Bot usage history exists.
struct HistoryView: View {
    @ObservedObject var store: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader

            comingSoonCard

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            // Do not scan ~/.claude — that path is Claude Code only.
        }
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "history.coming.title"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
            Text(String(localized: "history.coming.subtitle"))
                .font(.system(size: 13))
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }

    private var comingSoonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Palette.accentHistory)
                Text(String(localized: "history.coming.badge"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
            }
            Text(String(localized: "history.coming.body"))
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
