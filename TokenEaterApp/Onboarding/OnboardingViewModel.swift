import SwiftUI
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.emersonspiff.grokboteater.app", category: "Onboarding")

enum GrokBotSessionStatus {
    case checking
    case detected
    case notFound
}

enum ConnectionStatus {
    case idle
    case connecting
    case success(GrokBotUsageResponse)
    case rateLimited
    case failed(String)
}

enum NotificationStatus {
    case unknown
    case authorized
    case denied
    case notYetAsked
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var grokBotStatus: GrokBotSessionStatus = .checking
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var notificationStatus: NotificationStatus = .unknown

    /// Bridges `SettingsStore.overlayEnabled` for settings continuity.
    /// Watchers are not part of Grok Bot onboarding; default stays off.
    @Published var watcherEnabled: Bool

    /// Cards in the onboarding grid: Grok Bot session, Connect, Notifications.
    let totalSteps: Int = 3

    private let cookieReader: CursorCookieReaderProtocol
    private let grokBotAPI: GrokBotAPIClientProtocol
    private let notificationService: NotificationServiceProtocol
    private let settingsStore: SettingsStore

    init(
        cookieReader: CursorCookieReaderProtocol = CursorCookieReader(),
        grokBotAPI: GrokBotAPIClientProtocol = GrokBotAPIClient(),
        notificationService: NotificationServiceProtocol = NotificationService(),
        settingsStore: SettingsStore? = nil
    ) {
        self.cookieReader = cookieReader
        self.grokBotAPI = grokBotAPI
        self.notificationService = notificationService
        let store = settingsStore ?? SettingsStore(
            notificationService: notificationService
        )
        self.settingsStore = store
        self.watcherEnabled = store.overlayEnabled
    }

    /// Whether a Cursor session cookie is already readable (no network call).
    var needsBootstrap: Bool {
        // Off-main reads happen in checkGrokBotSession / connect; this is a
        // cheap hint only used for copy. Prefer not blocking the main thread.
        false
    }

    /// Finish requires Grok Bot session detected AND Connect success/rateLimited.
    var canFinish: Bool {
        guard grokBotStatus == .detected else { return false }
        switch connectionStatus {
        case .success, .rateLimited:
            return true
        default:
            return false
        }
    }

    /// How many of the 3 cards are in a "ready" state.
    var readyCount: Int {
        var count = 0
        if grokBotStatus == .detected { count += 1 }
        if notificationStatus == .authorized { count += 1 }
        switch connectionStatus {
        case .success, .rateLimited:
            count += 1
        default:
            break
        }
        return count
    }

    func setWatcherEnabled(_ enabled: Bool) {
        watcherEnabled = enabled
        settingsStore.overlayEnabled = enabled
    }

    func checkGrokBotSession() {
        grokBotStatus = .checking
        let reader = cookieReader
        DispatchQueue.global(qos: .userInitiated).async {
            let hasCookie = reader.readCookie() != nil
            DispatchQueue.main.async { [weak self] in
                self?.grokBotStatus = hasCookie ? .detected : .notFound
            }
        }
    }

    func checkNotificationStatus() {
        Task {
            let status = await notificationService.checkAuthorizationStatus()
            switch status {
            case .authorized, .provisional, .ephemeral:
                notificationStatus = .authorized
            case .denied:
                notificationStatus = .denied
            case .notDetermined:
                notificationStatus = .notYetAsked
            @unknown default:
                notificationStatus = .unknown
            }
        }
    }

    func requestNotifications() {
        notificationService.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkNotificationStatus()
        }
    }

    func sendTestNotification() {
        notificationService.sendTest()
    }

    func connect() {
        connectionStatus = .connecting

        let reader = cookieReader
        let api = grokBotAPI
        Task {
            let cookie = await Self.cookieOffMain(reader)

            guard let cookie else {
                connectionStatus = .failed(String(localized: "onboarding.connection.failed.notoken"))
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            do {
                let usage = try await api.fetchUsage(cookie: cookie)
                connectionStatus = .success(usage)
            } catch let error as GrokBotAPIError {
                if case .rateLimited = error {
                    connectionStatus = .rateLimited
                } else {
                    connectionStatus = .failed(error.localizedDescription)
                }
            } catch {
                connectionStatus = .failed(error.localizedDescription)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Reads the Cursor session cookie off the main thread (SQLite / file I/O).
    private static func cookieOffMain(_ reader: CursorCookieReaderProtocol) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: reader.readCookie())
            }
        }
    }

    func completeOnboarding() {
        WidgetReloader.scheduleReload()
    }
}
