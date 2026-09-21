import SwiftUI

/// Required card - tests the Grok Bot usage API with the Cursor session
/// cookie. Idle scene explains reading the Cursor login; Authorize fires
/// `GrokBotAPIClient.fetchUsage`.
struct ConnectCard: View {
    @ObservedObject var viewModel: OnboardingViewModel

    private let accent = DS.Palette.brandPrimary

    var body: some View {
        OnboardingCard(
            kind: .required,
            tilt: .right,
            title: "onboarding.card.connect.title",
            statusText: statusText,
            statusColor: statusColor,
            accent: accent,
            scene: { scene },
            control: { control }
        )
    }

    @ViewBuilder
    private var scene: some View {
        switch viewModel.connectionStatus {
        case .idle:
            idleScene

        case .connecting:
            VStack(spacing: 8) {
                ProgressView().tint(DS.Palette.textPrimary)
                Text("onboarding.card.connect.connecting")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .success, .rateLimited:
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(DS.Palette.brandPrimary.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DS.Palette.brandPrimary)
                }
                .shadow(color: DS.Palette.brandPrimary.opacity(0.4), radius: 14)
                Text("onboarding.card.connect.success.scene")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(DS.Palette.semanticError.opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DS.Palette.semanticError)
                }
                Text("onboarding.card.connect.failed.scene")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textSecondary)
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Idle scene - Cursor session / Grok Bot usage check, not Keychain.
    private var idleScene: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(accent)
            }
            .shadow(color: accent.opacity(0.4), radius: 14)

            Text("onboarding.card.connect.idle.scene")
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var control: some View {
        switch viewModel.connectionStatus {
        case .idle:
            actionButton(label: "onboarding.card.connect.authorize") {
                viewModel.connect()
            }
        case .failed:
            actionButton(label: "onboarding.card.connect.retry") {
                viewModel.connectionStatus = .idle
            }
        case .connecting, .success, .rateLimited:
            EmptyView()
        }
    }

    private func actionButton(label: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(LinearGradient(
                        colors: [DS.Palette.brandPrimary, DS.Palette.brandPressed],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                )
                .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 1))
                .shadow(color: DS.Palette.brandPrimary.opacity(0.4), radius: 7)
        }
        .buttonStyle(.plain)
    }

    private var statusText: LocalizedStringResource {
        switch viewModel.connectionStatus {
        case .idle:        return "onboarding.card.connect.status.idle"
        case .connecting:  return "onboarding.card.connect.status.connecting"
        case .success, .rateLimited:
            return "onboarding.card.connect.status.success"
        case .failed:      return "onboarding.card.connect.status.failed"
        }
    }

    private var statusColor: Color {
        switch viewModel.connectionStatus {
        case .idle, .connecting: return DS.Palette.brandPrimary
        case .success, .rateLimited: return DS.Palette.brandPrimary
        case .failed: return DS.Palette.semanticError
        }
    }
}
