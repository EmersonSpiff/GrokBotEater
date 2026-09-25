import SwiftUI
import UserNotifications

/// Settings sub-section dedicated to notifications. Hosts the authorization
/// status row + test button at the top, then a card per category (usage
/// thresholds / pacing / reset reminders / extra credits / health) with one
/// toggle per event.
struct NotificationsSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var grokBotUsageStore: GrokBotUsageStore

    @State private var notifTestCooldown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                sectionTitle(
                    String(localized: "sidebar.notifications"),
                    subtitle: String(localized: "sidebar.notifications.subtitle")
                )
                Spacer()
                ClickChip(
                    label: String(localized: "settings.notifications.master"),
                    icon: settingsStore.notificationsEnabled ? "checkmark" : "bell.slash",
                    isActive: settingsStore.notificationsEnabled,
                    accent: .blue,
                    style: .compact
                ) {
                    settingsStore.notificationsEnabled.toggle()
                }
            }

            authorizationCard
            usageCard
            pacingCard
            resetRemindersCard
            extraCreditsCard
            healthCard

            ResetSectionButton(
                confirmTitle: String(localized: "settings.notifications.reset.confirm"),
                onReset: resetToDefaults
            )
        }
        .padding(24)
        .task { await settingsStore.refreshNotificationStatus() }
    }

    private func resetToDefaults() {
        settingsStore.notificationsEnabled = true
        settingsStore.notifSendRecovery = true
        settingsStore.notifPacingHot = true
        settingsStore.notifPacingWarning = false
        settingsStore.notifResetReminderWeekly = false
        settingsStore.notifResetReminderWeeklyOffset = 60
        settingsStore.notifTokenExpired = false
        settingsStore.notifVendorDegraded = true
        settingsStore.notifVendorRestored = true
    }

    // MARK: - Authorization

    private var authorizationCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel(String(localized: "settings.notifications.status"))
                HStack {
                    statusLabel
                    Spacer()
                    if settingsStore.notificationStatus == .denied {
                        Button(String(localized: "settings.notifications.open")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings")!)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    } else if settingsStore.notificationStatus != .authorized {
                        Button(String(localized: "settings.notifications.enable")) {
                            settingsStore.requestNotificationPermission()
                            Task {
                                try? await Task.sleep(for: .seconds(1))
                                await settingsStore.refreshNotificationStatus()
                            }
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                    Button(String(localized: "settings.notifications.test")) {
                        if settingsStore.notificationStatus != .authorized {
                            settingsStore.requestNotificationPermission()
                        }
                        settingsStore.sendTestNotification()
                        notifTestCooldown = true
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            notifTestCooldown = false
                            await settingsStore.refreshNotificationStatus()
                        }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .disabled(notifTestCooldown)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch settingsStore.notificationStatus {
        case .authorized:
            Label(String(localized: "settings.notifications.on"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .denied:
            Label(String(localized: "settings.notifications.off"), systemImage: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        default:
            Label(String(localized: "settings.notifications.unknown"), systemImage: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }

    // MARK: - Usage notifications

    private var usageCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        cardLabel("Grok Bot Usage Alerts")
                        Text("Get notified when usage crosses thresholds (configured in Settings > Pacing)")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        guard !notifTestCooldown else { return }
                        testUsageAlert()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: notifTestCooldown ? "checkmark" : "bell.badge")
                                .font(.system(size: 10))
                            Text(notifTestCooldown ? "Sent" : "Test")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(notifTestCooldown ? .green : .blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(notifTestCooldown)
                }
                
                darkToggle("Track weekly Grok Bot usage", isOn: .constant(true))
                    .disabled(true)
                    .opacity(0.6)
                Text("Always on for Grok Bot (weekly billing cycle)")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 32)
                
                Divider().padding(.vertical, 2)
                
                darkToggle("Send recovery notification", isOn: $settingsStore.notification.sendRecovery)
                Text("Notify when usage drops back below the warning threshold after a weekly reset")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func testUsageAlert() {
        guard let snapshot = grokBotUsageStore.currentSnapshot else { return }
        
        let testPct = max(themeStore.warningThreshold, snapshot.pct)
        let resetDate = snapshot.resetsAt ?? Date().addingTimeInterval(3600 * 24 * 3)
        
        let notif = UNMutableNotificationContent()
        notif.title = testPct >= themeStore.criticalThreshold 
            ? String(localized: "notif.title.grokBot.red")
            : String(localized: "notif.title.grokBot.orange")
        notif.sound = .default
        
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: resetDate)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E"
        let dayStr = dateFormatter.string(from: resetDate)
        let dateTime = "\(dayStr) \(timeStr)"
        
        let bodyKey = testPct >= themeStore.criticalThreshold
            ? "notif.body.grokBot.red"
            : "notif.body.grokBot.orange"
        notif.body = String(format: NSLocalizedString(bodyKey, comment: ""), testPct, dateTime)
        
        let request = UNNotificationRequest(
            identifier: "test-usage-\(UUID().uuidString)",
            content: notif,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { _ in }
        
        notifTestCooldown = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            notifTestCooldown = false
        }
    }

    // MARK: - Pacing

    private var pacingCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel(String(localized: "settings.notifications.group.pacing"))
                Text(String(localized: "settings.notifications.group.pacing.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                darkToggle(String(localized: "settings.notifications.pacing.hot"), isOn: $settingsStore.notification.pacingHot)
                darkToggle(String(localized: "settings.notifications.pacing.warning"), isOn: $settingsStore.notification.pacingWarning)
            }
        }
    }

    // MARK: - Reset reminders

    private var resetRemindersCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel("Grok Bot Reset Reminders")
                Text("Get notified before your weekly Grok Bot usage resets")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                darkToggle("Weekly reset reminder", isOn: $settingsStore.notification.resetReminderWeekly)
                reminderOffsetPicker(
                    selection: $settingsStore.notification.resetReminderWeeklyOffset,
                    options: [30, 60, 120, 180, 360],
                    enabled: settingsStore.notifResetReminderWeekly
                )
            }
        }
    }

    @ViewBuilder
    private func reminderOffsetPicker(selection: Binding<Int>, options: [Int], enabled: Bool) -> some View {
        HStack(spacing: 6) {
            Text(String(localized: "settings.notifications.reset.offset.label"))
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.textPrimary.opacity(enabled  ? 0.6 : 0.25))
            Spacer()
            DSMenu(
                selection: selection,
                options: options,
                label: formatOffsetMinutes,
                enabled: enabled
            )
        }
        .padding(.leading, 12)
    }

    private func formatOffsetMinutes(_ minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 {
            let hours = minutes / 60
            return String(format: String(localized: "settings.notifications.reset.offset.hours"), hours)
        }
        return String(format: String(localized: "settings.notifications.reset.offset.minutes"), minutes)
    }

    // MARK: - Pool refills

    private var extraCreditsCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel("Usage Pool Refills")
                Text("Grok Bot usage is billed per-seat in weekly cycles. Extra credits concept does not apply.")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                darkToggle("Notify on pool expansion", isOn: .constant(false))
                    .disabled(true)
                    .opacity(0.4)
            }
        }
    }

    // MARK: - Health

    private var healthCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel("Cursor & Grok Bot Health")
                Text("Get notified about Cursor service status and login session issues")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                darkToggle("Cursor login session expired", isOn: $settingsStore.notification.tokenExpired)
                darkToggle("Cursor service degraded (status.cursor.com)", isOn: $settingsStore.notification.vendorDegraded)
                darkToggle("Cursor service restored", isOn: $settingsStore.notification.vendorRestored)
            }
        }
    }
}

