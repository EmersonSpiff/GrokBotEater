import SwiftUI
import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    var usageStore: UsageStore!
    var grokBotUsageStore: GrokBotUsageStore!
    var themeStore: ThemeStore!
    var settingsStore: SettingsStore!
    var updateStore: UpdateStore!
    var sessionStore: SessionStore!
    var grokBotAgentSessionStore: GrokBotAgentSessionStore!
    var vendorStatusStore: VendorStatusStore!

    private var statusBarController: StatusBarController?
    private var overlayWindowController: OverlayWindowController?
    private var monitorCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        NotificationCenter.default.post(name: .openDashboard, object: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clean up the v4.x LaunchAgent helper on first launch after upgrade.
        // Idempotent + gated by a UserDefaults flag, so this is effectively a
        // no-op for fresh installs and for subsequent launches of upgraded users.
        LegacyHelperCleanupService().runIfNeeded()

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        statusBarController = StatusBarController(
            usageStore: usageStore,
            grokBotUsageStore: grokBotUsageStore,
            themeStore: themeStore,
            settingsStore: settingsStore,
            updateStore: updateStore,
            sessionStore: sessionStore,
            grokBotAgentSessionStore: grokBotAgentSessionStore,
            vendorStatusStore: vendorStatusStore
        )
        // Start monitoring Grok Bot agents when overlay is enabled
        if settingsStore.overlayEnabled {
            grokBotAgentSessionStore.startMonitoring()
            grokBotAgentSessionStore.setScanInterval(settingsStore.watcherScanInterval.seconds)
            grokBotAgentSessionStore.setActivityWindow(settingsStore.watcherVisibility.seconds)
        }
        // Stop Claude monitoring
        sessionStore.stopMonitoring()
        overlayWindowController = OverlayWindowController(
            sessionStore: sessionStore,
            grokBotAgentSessionStore: grokBotAgentSessionStore,
            settingsStore: settingsStore
        )

        updateStore.checkBrewMigration()
        updateStore.checkForUpdates()
    }
}

@main
struct TokenEaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let usageStore: UsageStore
    private let grokBotUsageStore: GrokBotUsageStore
    private let themeStore: ThemeStore
    private let settingsStore: SettingsStore
    private let updateStore: UpdateStore
    private let sessionStore: SessionStore
    private let grokBotAgentSessionStore: GrokBotAgentSessionStore
    private let vendorStatusStore: VendorStatusStore

    init() {
        // NSRunningApplication only enumerates the current login session, so this
        // refuses a second launch by the same user without blocking a separate
        // macOS user's own instance (e.g. under Fast User Switching).
        if let bundleID = Bundle.main.bundleIdentifier {
            let currentPID = ProcessInfo.processInfo.processIdentifier
            if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0.processIdentifier != currentPID }) {
                existing.activate()
                exit(0)
            }
        }

        // Migrate v4.x sandbox-container UserDefaults into the real path BEFORE
        // any store is constructed - store inits read UserDefaults.standard, so
        // missing this step would make every upgrading user land on onboarding.
        LegacyHelperCleanupService().migratePrefsIfNeeded()

        self.usageStore = UsageStore()
        self.grokBotUsageStore = GrokBotUsageStore()
        self.themeStore = ThemeStore()
        self.settingsStore = SettingsStore()
        self.updateStore = UpdateStore()
        self.sessionStore = SessionStore()
        self.grokBotAgentSessionStore = GrokBotAgentSessionStore()
        self.vendorStatusStore = VendorStatusStore()

        NotificationService().setupDelegate()
        appDelegate.usageStore = usageStore
        appDelegate.grokBotUsageStore = grokBotUsageStore
        appDelegate.themeStore = themeStore
        appDelegate.settingsStore = settingsStore
        appDelegate.updateStore = updateStore
        appDelegate.sessionStore = sessionStore
        appDelegate.grokBotAgentSessionStore = grokBotAgentSessionStore
        appDelegate.vendorStatusStore = vendorStatusStore
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

