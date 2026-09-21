import SwiftUI

/// Single-page onboarding. Brand header + body split: left = cards (Grok Bot
/// session, Connect, Notifications), right = hero with description, progress,
/// and the Finish CTA. Watchers are intentionally omitted — Claude session
/// overlay does not apply to Grok Bot.
///
/// The chrome (rounded background, modal radius) is provided by the parent
/// `MainAppView.onboardingContent`; this view stays transparent on top.
struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 16) {
            brandBar
            bodyContent
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .sheet(isPresented: $viewModel.showCursorLogin) {
            CursorWebLoginView { success in
                viewModel.handleWebLoginFinished(success: success)
            }
        }
    }

    private var brandBar: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text("GrokBotEater")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.textSecondary)

            Spacer()
        }
    }

    private var bodyContent: some View {
        HStack(alignment: .top, spacing: 22) {
            cardsGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            OnboardingHero(viewModel: viewModel)
                .frame(width: 280)
        }
    }

    private var cardsGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                GrokBotCard(viewModel: viewModel)
                ConnectCard(viewModel: viewModel)
            }
            GridRow {
                NotificationsCard(viewModel: viewModel)
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
    }
}
