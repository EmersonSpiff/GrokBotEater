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
    case waitingForBrowser(uuid: String, verifier: String, task: Task<Void, Never>)
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
    private let sharedFileService: SharedFileServiceProtocol

    init(
        cookieReader: CursorCookieReaderProtocol = CursorCookieReader(),
        grokBotAPI: GrokBotAPIClientProtocol = GrokBotAPIClient(),
        notificationService: NotificationServiceProtocol = NotificationService(),
        settingsStore: SettingsStore? = nil,
        sessionStore: GrokBotSessionStore = .shared,
        sharedFileService: SharedFileServiceProtocol = SharedFileService()
    ) {
        self.cookieReader = cookieReader
        self.grokBotAPI = grokBotAPI
        self.notificationService = notificationService
        self.sessionStore = sessionStore
        self.sharedFileService = sharedFileService
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

    /// Connect: try saved/scraped cookie → fetchUsage; otherwise start browser auth.
    /// If `forceBrowserAuth` is true, skips cookie detection and goes straight to browser flow.
    func connect(forceBrowserAuth: Bool = false) {
        connectionStatus = .connecting
        showCursorLogin = false

        let reader = cookieReader
        let api = grokBotAPI
        let isSignedOut = sharedFileService.isSignedOut
        
        Task {
            // Skip auto-detection if forcing browser auth or if user is signed out
            let cookie = (forceBrowserAuth || isSignedOut) ? nil : await Self.cookieOffMain(reader)

            guard let cookie else {
                // No cookie at all — start browser authentication flow.
                startBrowserAuth()
                return
            }

            let outcome = await Self.fetchOutcome(api: api, cookie: cookie)
            switch outcome {
            case .success(let usage):
                connectionStatus = .success(usage)
                grokBotStatus = .detected
                // Clear signed-out flag on successful connection
                sharedFileService.setSignedOut(false)
            case .rateLimited:
                connectionStatus = .rateLimited
                grokBotStatus = .detected
                // Clear signed-out flag on successful connection
                sharedFileService.setSignedOut(false)
            case .cookieRejected:
                // Stale Keychain / scraped cookie — clear and start browser auth.
                sessionStore.clear()
                startBrowserAuth()
            case .failed(let message):
                connectionStatus = .failed(message)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    /// Starts the browser-based PKCE authentication flow.
    private func startBrowserAuth() {
        guard let (url, uuid, verifier) = CursorBrowserAuthService.createLoginURL() else {
            connectionStatus = .failed(String(localized: "onboarding.browser.auth.error.setup"))
            return
        }
        
        // Open the URL in the user's default browser
        NSWorkspace.shared.open(url)
        
        // Start polling in the background
        let pollTask = Task { @MainActor in
            await self.pollForBrowserAuth(uuid: uuid, verifier: verifier)
        }
        
        connectionStatus = .waitingForBrowser(uuid: uuid, verifier: verifier, task: pollTask)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Polls for browser authentication completion.
    private func pollForBrowserAuth(uuid: String, verifier: String) async {
        do {
            let tokens = try await CursorBrowserAuthService.pollForTokens(
                uuid: uuid,
                verifier: verifier
            ) { progress in
                // Progress updates could be shown in UI if desired
                logger.debug("Browser auth progress: \(progress)")
            }
            
            // Convert tokens to session cookie and save
            guard let sessionCookie = CursorBrowserAuthService.convertToSessionCookie(tokens: tokens) else {
                throw CursorBrowserAuthService.AuthError.invalidResponse
            }
            sessionStore.save(cookie: sessionCookie)
            
            // Clear signed-out flag after successful browser authentication
            sharedFileService.setSignedOut(false)
            
            // Now test the connection with the new cookie
            grokBotStatus = .detected
            connectionStatus = .connecting
            
            let api = grokBotAPI
            let outcome = await Self.fetchOutcome(api: api, cookie: sessionCookie)
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
        } catch let error as CursorBrowserAuthService.AuthError {
            connectionStatus = .failed(error.localizedDescription ?? String(localized: "onboarding.browser.auth.error.unknown"))
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Cancels the browser authentication flow.
    func cancelBrowserAuth() {
        if case .waitingForBrowser(_, _, let task) = connectionStatus {
            task.cancel()
            connectionStatus = .idle
        }
    }
    
    /// Opens the fallback in-app web view login.
    func openFallbackWebLogin() {
        if case .waitingForBrowser(_, _, let task) = connectionStatus {
            task.cancel()
        }
        connectionStatus = .idle
        showCursorLogin = true
        NSApp.activate(ignoringOtherApps: true)
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
            
            // Clear signed-out flag after successful fallback login
            sharedFileService.setSignedOut(false)
            
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
