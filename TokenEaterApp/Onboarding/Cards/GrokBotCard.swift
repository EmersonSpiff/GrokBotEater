import SwiftUI

/// First card - gates onboarding on a readable Cursor session cookie
/// (`CursorAppLogin`) used by the Grok Bot usage API. Auto-checks on appear;
/// shows a ready state or a short “open Cursor / sign in / retry” guide.
struct GrokBotCard: View {
    @ObservedObject var viewModel: OnboardingViewModel

    private let accent = Color(red: 0.30, green: 0.81, blue: 0.50) // green

    var body: some View {
        OnboardingCard(
            kind: .required,
            tilt: .left,
            title: "onboarding.card.grokbot.title",
            statusText: statusText,
            statusColor: statusColor,
            accent: accent,
            scene: { scene },
            control: { control }
        )
        .onAppear { viewModel.checkGrokBotSession() }
    }

    @ViewBuilder
    private var scene: some View {
        switch viewModel.grokBotStatus {
        case .checking:
            VStack(spacing: 8) {
                ProgressView().tint(DS.Palette.textPrimary)
                Text("onboarding.card.grokbot.checking")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .detected:
            readyScene
                .padding(10)

        case .notFound:
            loginGuide
                .padding(10)
        }
    }

    private var readyScene: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .shadow(color: accent.opacity(0.35), radius: 12)

            Text("onboarding.card.grokbot.ready.scene")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Palette.textPrimary)
                .multilineTextAlignment(.center)

            Text("onboarding.card.grokbot.ready.detail")
                .font(.system(size: 9))
                .foregroundStyle(DS.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loginGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepRow(1, key: "onboarding.card.grokbot.notfound.step1")
            stepRow(2, key: "onboarding.card.grokbot.notfound.step2")
            stepRow(3, key: "onboarding.card.grokbot.notfound.step3")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func stepRow(_ n: Int, key: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("\(n)")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.29))
                .frame(width: 14, height: 14)
                .background(Circle().fill(Color(red: 1.0, green: 0.62, blue: 0.04).opacity(0.18)))
            Text(key)
                .font(.system(size: 9))
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var control: some View {
        if viewModel.grokBotStatus == .notFound {
            Button {
                viewModel.checkGrokBotSession()
            } label: {
                Text("onboarding.card.grokbot.retry")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else {
            EmptyView()
        }
    }

    private var statusText: LocalizedStringResource {
        switch viewModel.grokBotStatus {
        case .checking: return "onboarding.card.grokbot.status.checking"
        case .detected: return "onboarding.card.grokbot.status.detected"
        case .notFound: return "onboarding.card.grokbot.status.notfound"
        }
    }

    private var statusColor: Color {
        switch viewModel.grokBotStatus {
        case .checking: return Color.black.opacity(0.3)
        case .detected: return accent
        case .notFound: return Color(red: 1.0, green: 0.62, blue: 0.04)
        }
    }
}
