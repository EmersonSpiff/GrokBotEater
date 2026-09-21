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
    /// Presents the in-app cursor.com WKWebView login sheet.
    @Published var showCursorLogin = false

    /// Bridges `SettingsStore.overlayEnabled` for settings continuity.
    /// Watchers are not part of Grok Bot onboarding; default stays off.
    @Published var watcherEnabled: Bool

    /// Cards in the onboarding grid: Grok Bot session, Connect, Notifications.
    let totalSteps: Int = 3

    private let cookieReader: CursorCookieReaderProtocol
    private let grokBotAPI: GrokBotAPIClientProtocol
    private let notificationService: NotificationServiceProtocol
    private let settingsStore: SettingsStore
    private let sessionStore: GrokBotSessionStore

    init(
        cookieReader: CursorCookieReaderProtocol = CursorCookieReader(),
        grokBotAPI: GrokBotAPIClientProtocol = GrokBotAPIClient(),
        notificationService: NotificationServiceProtocol = NotificationService(),
        settingsStore: SettingsStore? = nil,
        sessionStore: GrokBotSessionStore = .shared
    ) {
        self.cookieReader = cookieReader
        self.grokBotAPI = grokBotAPI
        self.notificationService = notificationService
        self.sessionStore = sessionStore
        let store = settingsStore ?? SettingsStore(
            notificationService: notificationService
        )
        self.settingsStore = store
        self.watcherEnabled = store.overlayEnabled
    }

    /// Whether a Cursor session cookie is already readable (no network call).
    var needsBootstrap: Bool {
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
            // Includes Keychain web session first, then disk scrape.
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

    /// Connect: try saved/scraped cookie → fetchUsage; otherwise open web login.
    func connect() {
        connectionStatus = .connecting
        showCursorLogin = false

        let reader = cookieReader
        let api = grokBotAPI
        Task {
            let cookie = await Self.cookieOffMain(reader)

            guard let cookie else {
                // No cookie at all — open in-app cursor.com login.
                connectionStatus = .idle
                showCursorLogin = true
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let outcome = await Self.fetchOutcome(api: api, cookie: cookie)
            switch outcome {
            case .success(let usage):
                connectionStatus = .success(usage)
                grokBotStatus = .detected
            case .rateLimited:
                connectionStatus = .rateLimited
                grokBotStatus = .detected
            case .cookieRejected:
                // Stale Keychain / scraped cookie — clear and prompt web login.
                sessionStore.clear()
                connectionStatus = .idle
                showCursorLogin = true
            case .failed(let message):
                connectionStatus = .failed(message)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Called when the web login sheet finishes (success or cancel).
    func handleWebLoginFinished(success: Bool) {
        showCursorLogin = false
        guard success else {
            connectionStatus = .idle
            return
        }
        // Cookie was saved to Keychain by CursorWebLoginView — retry Connect.
        grokBotStatus = .detected
        connectionStatus = .connecting

        let reader = cookieReader
        let api = grokBotAPI
        Task {
            let cookie = await Self.cookieOffMain(reader)
            guard let cookie else {
                connectionStatus = .failed(String(localized: "onboarding.connection.failed.notoken"))
                return
            }
            let outcome = await Self.fetchOutcome(api: api, cookie: cookie)
            switch outcome {
            case .success(let usage):
                connectionStatus = .success(usage)
            case .rateLimited:
                connectionStatus = .rateLimited
            case .cookieRejected:
                sessionStore.clear()
                connectionStatus = .failed(String(localized: "onboarding.connection.failed.notoken"))
                grokBotStatus = .notFound
            case .failed(let message):
                connectionStatus = .failed(message)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private enum FetchOutcome {
        case success(GrokBotUsageResponse)
        case rateLimited
        case cookieRejected
        case failed(String)
    }

    private static func fetchOutcome(
        api: GrokBotAPIClientProtocol,
        cookie: String
    ) async -> FetchOutcome {
        do {
            let usage = try await api.fetchUsage(cookie: cookie)
            return .success(usage)
        } catch let error as GrokBotAPIError {
            switch error {
            case .rateLimited:
                return .rateLimited
            case .cookieExpired:
                return .cookieRejected
            default:
                return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Reads the Cursor session cookie off the main thread (SQLite / Keychain I/O).
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
