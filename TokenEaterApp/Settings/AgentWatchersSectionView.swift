import SwiftUI

struct AgentWatchersSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var showTerminalSetup = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle(
                    "Grok Bot Agent Watchers",
                    subtitle: "Floating overlay for your live Grok Bot agents"
                )

                enableToggleCard
                styleGroup
                behaviorGroup
                legendGroup

                ResetSectionButton(
                    confirmTitle: String(localized: "settings.watchers.reset.confirm"),
                    onReset: resetWatcherDefaults
                )

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .sheet(isPresented: $showTerminalSetup) {
            TerminalSetupSheet(isPresented: $showTerminalSetup)
        }
    }

    private var enableToggleCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Grok Bot Agent Watchers")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("Track live Grok Bot agents in a floating overlay")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            Spacer()
            ClickChip(
                label: settingsStore.overlayEnabled ? "On" : "Off",
                icon: settingsStore.overlayEnabled ? "checkmark" : "eye.slash",
                isActive: settingsStore.overlayEnabled,
                accent: .blue,
                style: .compact
            ) {
                settingsStore.overlayEnabled.toggle()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Palette.bgElevated.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
                )
        )
    }

    // MARK: - Style group

    private var styleGroup: some View {
        groupSection(title: "settings.watchers.style", subtitle: "settings.watchers.style.hint") {
            HStack(spacing: 12) {
                stylePreviewCard(.frost)
                stylePreviewCard(.neon)
            }
        }
    }

    // MARK: - Behavior group

    private var behaviorGroup: some View {
        groupSection(title: "settings.watchers.behavior", subtitle: "settings.watchers.behavior.hint") {
            VStack(alignment: .leading, spacing: 14) {
                // Display mode -> chip pair
                groupLabel("Agent sort order")
                HStack(spacing: 8) {
                    ForEach(WatcherDisplayMode.allCases, id: \.self) { mode in
                        BinaryChoiceChip(
                            label: mode.label,
                            icon: mode.icon,
                            isActive: settingsStore.watcherDisplayMode == mode
                        ) {
                            settingsStore.watcherDisplayMode = mode
                        }
                    }
                }

                // Trigger zone -> 4 chips
                groupLabel("settings.watchers.trigger")
                    .padding(.top, 4)
                HStack(spacing: 6) {
                    ForEach(OverlayTriggerZone.allCases) { zone in
                        triggerZoneChip(zone)
                    }
                }

                // Scan rate -> chips (how often the watcher rescans)
                groupLabel("settings.watchers.scanrate")
                    .padding(.top, 4)
                HStack(spacing: 6) {
                    ForEach(WatcherScanInterval.allCases, id: \.self) { interval in
                        BinaryChoiceChip(
                            label: interval.label,
                            icon: "arrow.clockwise",
                            isActive: settingsStore.watcherScanInterval == interval
                        ) {
                            settingsStore.watcherScanInterval = interval
                        }
                    }
                }

                // Visibility -> chips (how long a session stays shown when idle)
                groupLabel("settings.watchers.visibility")
                    .padding(.top, 4)
                HStack(spacing: 6) {
                    ForEach(WatcherVisibility.allCases, id: \.self) { visibility in
                        BinaryChoiceChip(
                            label: visibility.label,
                            icon: "eye",
                            isActive: settingsStore.watcherVisibility == visibility
                        ) {
                            settingsStore.watcherVisibility = visibility
                        }
                    }
                }

                // Side + dock effect + animations -> chip row
                HStack(spacing: 8) {
                    ClickChip(
                        label: String(localized: "settings.watchers.dock"),
                        icon: "arrow.down.left.arrow.up.right.square",
                        isActive: settingsStore.overlayDockEffect,
                        accent: .blue
                    ) {
                        settingsStore.overlayDockEffect.toggle()
                    }
                    ClickChip(
                        label: String(localized: "settings.watchers.leftside"),
                        icon: "rectangle.lefthalf.filled",
                        isActive: settingsStore.overlayLeftSide,
                        accent: .blue
                    ) {
                        settingsStore.overlayLeftSide.toggle()
                    }
                    ClickChip(
                        label: String(localized: "settings.watchers.animations"),
                        icon: "wand.and.sparkles",
                        isActive: settingsStore.watcherAnimationsEnabled,
                        accent: .blue
                    ) {
                        settingsStore.watcherAnimationsEnabled.toggle()
                    }
                }
                .padding(.top, 4)

                // Size slider with reset hint
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        groupLabel("settings.watchers.size")
                        Spacer()
                        Text("\(Int(settingsStore.overlayScale * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.Palette.textSecondary)
                            .monospacedDigit()
                        if abs(settingsStore.overlayScale - 1.1) > 0.01 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    settingsStore.overlayScale = 1.1
                                }
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DS.Palette.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .help(Text(String(localized: "settings.watchers.size.reset")))
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "minus")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.Palette.textTertiary)
                        TokenEaterSlider(value: $settingsStore.overlay.overlayScale, in: 0.6...1.6, step: 0.05)
                        Image(systemName: "plus")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func triggerIcon(_ zone: OverlayTriggerZone) -> String {
        switch zone {
        case .minimal: return "rectangle.compress.vertical"
        case .narrow:  return "rectangle.center.inset.filled"
        case .medium:  return "square.split.bottomrightquarter"
        case .wide:    return "rectangle.expand.vertical"
        }
    }
    
    @ViewBuilder
    private func triggerZoneChip(_ zone: OverlayTriggerZone) -> some View {
        let needsRotation = zone == .minimal || zone == .wide
        BinaryChoiceChip(
            label: zone.localizedLabel,
            icon: triggerIcon(zone),
            isActive: settingsStore.overlayTriggerZone == zone,
            iconRotation: needsRotation ? 90 : 0
        ) {
            settingsStore.overlayTriggerZone = zone
        }
    }

    // MARK: - Legend group

    private var legendGroup: some View {
        groupSection(title: "settings.watchers.legend", subtitle: "settings.watchers.legend.hint") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    BinaryChoiceChip(
                        label: String(localized: "settings.watchers.legend.simple"),
                        icon: "circle.lefthalf.filled",
                        isActive: !settingsStore.watchersDetailedMode
                    ) {
                        settingsStore.watchersDetailedMode = false
                    }
                    BinaryChoiceChip(
                        label: String(localized: "settings.watchers.legend.detailed"),
                        icon: "circle.hexagongrid.fill",
                        isActive: settingsStore.watchersDetailedMode
                    ) {
                        settingsStore.watchersDetailedMode = true
                    }
                }

                Divider().opacity(0.12)

                if settingsStore.watchersDetailedMode {
                    grokBotStatusRow(symbol: "sparkles", color: Color(red: 0.3, green: 0.7, blue: 1.0), label: "Working", description: "Agent is generating a response")
                    grokBotStatusRow(symbol: "person.bubble", color: .orange, label: "Waiting on you", description: "Agent needs your input")
                    grokBotStatusRow(symbol: "desktopcomputer.and.macbook", color: .purple, label: "Running locally", description: "Local command in progress")
                    grokBotStatusRow(symbol: "moon.stars", color: .gray, label: "Idle", description: "No activity")
                    grokBotStatusRow(symbol: "checkmark.square", color: .green, label: "Done", description: "Finished with new output")
                } else {
                    grokBotStatusRow(symbol: "sparkles", color: Color(red: 0.95, green: 0.62, blue: 0.22), label: "Working", description: "Agent is active (working, running locally)")
                    grokBotStatusRow(symbol: "moon.stars", color: Color(red: 0.3, green: 0.78, blue: 0.52), label: "Idle", description: "Agent needs you, idle, or done")
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: settingsStore.watchersDetailedMode)
        }
    }

    // MARK: - Terminal setup row

    private var terminalSetupRow: some View {
        Button {
            showTerminalSetup = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.watchers.terminalSetup"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(String(localized: "settings.watchers.terminalSetup.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Group helpers

    @ViewBuilder
    private func groupSection<Content: View>(title: String.LocalizationValue, subtitle: String.LocalizationValue, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: title).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(DS.Palette.textSecondary)
                Text(String(localized: subtitle))
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func groupLabel(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key))
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(DS.Palette.textTertiary)
    }

    private func resetWatcherDefaults() {
        settingsStore.overlayEnabled = true
        settingsStore.overlayDockEffect = true
        settingsStore.overlayScale = 1.1
        settingsStore.overlayLeftSide = false
        settingsStore.overlayTriggerZone = .medium
        settingsStore.watchersDetailedMode = true
        settingsStore.watcherStyle = .frost
        settingsStore.watcherDisplayMode = .branchPriority
        settingsStore.watcherScanInterval = .twoSeconds
        settingsStore.watcherVisibility = .thirtyMinutes
        settingsStore.watcherAnimationsEnabled = true
    }

    // MARK: - Style preview cards

    /// Renders the actual `GrokBotAgentCard` (the same component that drives
    /// the live overlay) at proximity 1.0 with a forced style override. This
    /// guarantees pixel-parity with what the user sees on screen, AND the
    /// preview reactively updates when the user flips Display mode / Legend
    /// detail / animations - because GrokBotAgentCard reads those from
    /// settingsStore directly.
    private func stylePreviewCard(_ style: WatcherStyle) -> some View {
        let isSelected = settingsStore.watcherStyle == style
        return Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                settingsStore.watcherStyle = style
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                GrokBotAgentCard(
                    session: previewGrokBotSession,
                    proximity: 1.0,
                    scale: 0.92,
                    leftSide: false,
                    animationsEnabled: settingsStore.watcherAnimationsEnabled,
                    style: style,
                    detailedMode: settingsStore.overlay.watchersDetailedMode,
                    onTap: {}
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(false)

                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? .blue : .white.opacity(0.3))
                    Text(style.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    Spacer()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.black.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue.opacity(0.5) : Color.black.opacity(0.07), lineWidth: 1)
                    )
            )
            .scaleEffect(isSelected ? 1.0 : 0.99)
        }
        .buttonStyle(.plain)
    }

    /// Synthetic Grok Bot session driving the style preview tiles.
    private var previewGrokBotSession: GrokBotSession {
        let now = Date()
        return GrokBotSession(
            id: "settings-watcher-preview",
            name: "grok-bot-agent",
            title: nil,
            state: .working,
            lastActivityAt: now,
            awaitingUserResponse: false,
            unreadCount: 0,
            isHiddenFromSidebar: false,
            isStreaming: true,
            hasLocalWork: false,
            lastTranscriptTimestamp: now
        )
    }

    // MARK: - Status legend row

    private func statusRow(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            statusIndicator(color: color)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(DS.Palette.textPrimary)
        }
    }

    @ViewBuilder
    private func statusIndicator(color: Color) -> some View {
        switch settingsStore.watcherStyle {
        case .frost:
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
        case .neon:
            let neonVariant = color
            RoundedRectangle(cornerRadius: 2)
                .fill(.black.opacity(0.6))
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(neonVariant.opacity(0.8), lineWidth: 1.5)
                )
                .shadow(color: neonVariant.opacity(0.4), radius: 3)
        }
    }
    
    private func grokBotStatusRow(symbol: String, color: Color, label: String, description: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Terminal setup sheet

/// Modal that gathers all per-terminal helpers (tmux / wezterm / kitty) under
/// a single tabbed sheet so the main settings page doesn't carry three almost-
/// identical card blocks. Each tab shows a short description, the snippet to
/// drop in the user's config, and a copy button.
private struct TerminalSetupSheet: View {
    @Binding var isPresented: Bool

    enum Tab: String, CaseIterable, Identifiable {
        case tmux, wezterm, kitty
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .tmux:    return "tmux"
            case .wezterm: return "WezTerm"
            case .kitty:   return "Kitty"
            }
        }

        var icon: String {
            switch self {
            case .tmux:    return "rectangle.split.3x1"
            case .wezterm: return "rectangle.grid.2x2"
            case .kitty:   return "pawprint.fill"
            }
        }
    }

    @State private var activeTab: Tab = .tmux
    @State private var copied: Tab? = nil

    private let tmuxSnippet = """
    set-option -g update-environment "TERM_PROGRAM"
    """
    private let weztermSnippet = """
    wezterm.on('gui-startup', function()
      local script = os.getenv('HOME') .. '/Library/Application Support/com.emersonspiff.grokboteater.shared/wezterm-watcher.sh'
      local f = io.open(script, 'r')
      if f then f:close(); io.popen('nohup bash "' .. script .. '" >/dev/null 2>&1 &') end
    end)
    """
    private let kittySnippet = "allow_remote_control yes"

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 8) {
                ForEach(Tab.allCases) { tab in
                    BinaryChoiceChip(
                        label: tab.displayName,
                        icon: tab.icon,
                        isActive: activeTab == tab
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            activeTab = tab
                            copied = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            content
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
        }
        .frame(width: 520)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.55))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings.watchers.terminalSetup"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(String(localized: "settings.watchers.terminalSetup.sheet.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: hintKey))
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                Text(activeSnippet)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    // Pin the snippet container to the height of the longest
                    // snippet (wezterm, ~5 lines). Switching tabs no longer
                    // changes the sheet height, so tab hit-targets stay put.
                    .frame(minHeight: 110, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.black.opacity(0.45))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                    )
                    .textSelection(.enabled)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(activeSnippet.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
                    copied = activeTab
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copied == activeTab { copied = nil }
                    }
                } label: {
                    Image(systemName: copied == activeTab ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var activeSnippet: String {
        switch activeTab {
        case .tmux:    return tmuxSnippet
        case .wezterm: return weztermSnippet
        case .kitty:   return kittySnippet
        }
    }

    private var hintKey: String.LocalizationValue {
        switch activeTab {
        case .tmux:    return "settings.watchers.tmux.hint"
        case .wezterm: return "settings.watchers.wezterm.hint"
        case .kitty:   return "settings.watchers.kitty.hint"
        }
    }
}
