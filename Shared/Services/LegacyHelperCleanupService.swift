import Foundation
import os.log

private let logger = Logger(subsystem: "com.emersonspiff.grokboteater.app", category: "LegacyHelperCleanup")

/// GrokBotEater fork: do not run TokenEater v4→v5 cleanup.
/// Touching `com.tokeneater.helper` / `com.tokeneater.app` would break a side-by-side TokenEater install.
final class LegacyHelperCleanupService: @unchecked Sendable {
    func migratePrefsIfNeeded() {
        // No-op — never import or mutate TokenEater preferences.
    }

    func runIfNeeded() {
        // No-op — never unload TokenEater LaunchAgents.
        logger.info("Skipping legacy TokenEater helper cleanup in GrokBotEater fork")
    }
}
