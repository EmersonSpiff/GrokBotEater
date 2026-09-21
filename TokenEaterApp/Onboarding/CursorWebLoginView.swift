import SwiftUI
import WebKit

/// In-app WKWebView sheet that loads cursor.com login and captures
/// the `WorkosCursorSessionToken` cookie into `GrokBotSessionStore`.
struct CursorWebLoginView: View {
    var onComplete: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var statusMessage = String(localized: "onboarding.weblogin.status.waiting")
    @State private var checkTrigger = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("onboarding.weblogin.title")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer()
                Button("onboarding.weblogin.check") {
                    checkTrigger += 1
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.brandPrimary)
                Button("onboarding.weblogin.cancel") {
                    onComplete(false)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            CursorLoginWebView(
                statusMessage: $statusMessage,
                checkTrigger: checkTrigger,
                onCookieCaptured: { cookie in
                    GrokBotSessionStore.shared.save(cookie: cookie)
                    statusMessage = String(localized: "onboarding.weblogin.status.captured")
                    onComplete(true)
                    dismiss()
                }
            )
            .frame(minWidth: 640, minHeight: 480)

            Divider()

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(DS.Palette.bgElevated)
        .frame(minWidth: 680, minHeight: 560)
    }
}

// MARK: - WKWebView bridge

private struct CursorLoginWebView: NSViewRepresentable {
    @Binding var statusMessage: String
    var checkTrigger: Int
    var onCookieCaptured: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(statusMessage: $statusMessage, onCookieCaptured: onCookieCaptured)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Persistent store so authenticator.cursor.sh redirects keep session cookies.
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.startPolling()

        let url = URL(string: "https://cursor.com/login")!
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onCookieCaptured = onCookieCaptured
        if checkTrigger != context.coordinator.lastCheckTrigger {
            context.coordinator.lastCheckTrigger = checkTrigger
            context.coordinator.inspectCookies()
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stopPolling()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var statusMessage: Binding<String>
        var onCookieCaptured: (String) -> Void
        weak var webView: WKWebView?
        private var pollTimer: Timer?
        private var didCapture = false
        var lastCheckTrigger: Int = 0

        init(statusMessage: Binding<String>, onCookieCaptured: @escaping (String) -> Void) {
            self.statusMessage = statusMessage
            self.onCookieCaptured = onCookieCaptured
        }

        func startPolling() {
            stopPolling()
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.inspectCookies()
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }

        func stopPolling() {
            pollTimer?.invalidate()
            pollTimer = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            statusMessage.wrappedValue = String(localized: "onboarding.weblogin.status.waiting")
            inspectCookies()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Follow target=_blank into the same view (authenticator redirects).
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func inspectCookies() {
            guard !didCapture, let store = webView?.configuration.websiteDataStore.httpCookieStore else {
                return
            }
            store.getAllCookies { [weak self] cookies in
                guard let self, !self.didCapture else { return }
                let preferredNames = ["WorkosCursorSessionToken", "CursorAppLogin"]
                let match = preferredNames.lazy.compactMap { name in
                    cookies.first { cookie in
                        cookie.name == name
                            && (cookie.domain == "cursor.com"
                                || cookie.domain == ".cursor.com"
                                || cookie.domain.hasSuffix("cursor.com"))
                            && !cookie.value.isEmpty
                    }
                }.first
                guard let match else { return }
                self.didCapture = true
                self.stopPolling()
                DispatchQueue.main.async {
                    self.onCookieCaptured(match.value)
                }
            }
        }
    }
}
