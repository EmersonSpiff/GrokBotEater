import Foundation

/// Overlay-domain slice of the user settings. Extracted from SettingsStore as
/// part of the fat-store split, same pattern as `PacingSettingsStore` and
/// `NotificationSettingsStore`. Owns the Agent Watchers overlay configuration
/// (enable, dock effect, scale, side, trigger zone) plus the watcher rendering
/// preferences and the single performance toggle. Each property persists itself
/// to UserDefaults. No shared-file mirror: the widget doesn't render the overlay.
///
/// Property names keep their historic `overlay*` / `watcher*` prefixes so the
/// backwards-compatible forwards on SettingsStore stay 1:1 and the prefix keeps
/// its meaning at call sites.
@MainActor
final class OverlaySettingsStore: ObservableObject {
    @Published var overlayEnabled: Bool {
        didSet { UserDefaults.standard.set(overlayEnabled, forKey: "overlayEnabled") }
    }
    @Published var overlayDockEffect: Bool {
        didSet { UserDefaults.standard.set(overlayDockEffect, forKey: "overlayDockEffect") }
    }
    @Published var overlayScale: Double {
        didSet { UserDefaults.standard.set(overlayScale, forKey: "overlayScale") }
    }
    @Published var overlayLeftSide: Bool {
        didSet { UserDefaults.standard.set(overlayLeftSide, forKey: "overlayLeftSide") }
    }
    @Published var overlayTriggerZone: OverlayTriggerZone {
        didSet { UserDefaults.standard.set(overlayTriggerZone.rawValue, forKey: "overlayTriggerZone") }
    }
    @Published var watchersDetailedMode: Bool {
        didSet { UserDefaults.standard.set(watchersDetailedMode, forKey: "watchersDetailedMode") }
    }
    @Published var watcherStyle: WatcherStyle {
        didSet { UserDefaults.standard.set(watcherStyle.rawValue, forKey: "watcherStyle") }
    }
    @Published var watcherDisplayMode: WatcherDisplayMode {
        didSet { UserDefaults.standard.set(watcherDisplayMode.rawValue, forKey: "watcherDisplayMode") }
    }
    @Published var watcherScanInterval: WatcherScanInterval {
        didSet { UserDefaults.standard.set(watcherScanInterval.rawValue, forKey: "watcherScanInterval") }
    }
    @Published var watcherVisibility: WatcherVisibility {
        didSet { UserDefaults.standard.set(watcherVisibility.rawValue, forKey: "watcherVisibility") }
    }
    @Published var watcherIdleTimeout: WatcherIdleTimeout {
        didSet { UserDefaults.standard.set(watcherIdleTimeout.rawValue, forKey: "watcherIdleTimeout") }
    }

    // Performance
    @Published var watcherAnimationsEnabled: Bool {
        didSet { UserDefaults.standard.set(watcherAnimationsEnabled, forKey: "watcherAnimationsEnabled") }
    }
    
    // Display selection
    @Published var overlayDisplayTarget: OverlayDisplayTarget {
        didSet { UserDefaults.standard.set(overlayDisplayTarget.rawValue, forKey: "overlayDisplayTarget") }
    }
    @Published var overlaySpecificDisplay: OverlayDisplayReference? {
        didSet {
            if let ref = overlaySpecificDisplay,
               let data = try? JSONEncoder().encode(ref) {
                UserDefaults.standard.set(data, forKey: "overlaySpecificDisplay")
            } else {
                UserDefaults.standard.removeObject(forKey: "overlaySpecificDisplay")
            }
        }
    }
    
    // Local work assignment
    @Published var watcherLocalWorkBotIds: Set<String> {
        didSet {
            let array = Array(watcherLocalWorkBotIds)
            UserDefaults.standard.set(array, forKey: "watcherLocalWorkBotIds")
        }
    }
    
    init() {
        // Defaults below apply only on first launch (no value yet in
        // UserDefaults) - per the `as? T ?? default` reads.
        self.overlayEnabled = UserDefaults.standard.object(forKey: "overlayEnabled") as? Bool ?? false
        self.overlayDockEffect = UserDefaults.standard.object(forKey: "overlayDockEffect") as? Bool ?? true
        self.overlayScale = UserDefaults.standard.object(forKey: "overlayScale") as? Double ?? 1.1
        self.overlayLeftSide = UserDefaults.standard.bool(forKey: "overlayLeftSide")
        self.overlayTriggerZone = OverlayTriggerZone(
            rawValue: UserDefaults.standard.string(forKey: "overlayTriggerZone") ?? OverlayTriggerZone.defaultZone.rawValue
        ) ?? .defaultZone
        self.watchersDetailedMode = UserDefaults.standard.object(forKey: "watchersDetailedMode") as? Bool ?? true
        self.watcherStyle = WatcherStyle(
            rawValue: UserDefaults.standard.string(forKey: "watcherStyle") ?? "frost"
        ) ?? .frost
        self.watcherDisplayMode = WatcherDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "watcherDisplayMode") ?? "branchPriority"
        ) ?? .branchPriority
        self.watcherScanInterval = (UserDefaults.standard.object(forKey: "watcherScanInterval") as? Int)
            .flatMap(WatcherScanInterval.init(rawValue:)) ?? .twoSeconds
        self.watcherVisibility = (UserDefaults.standard.object(forKey: "watcherVisibility") as? Int)
            .flatMap(WatcherVisibility.init(rawValue:)) ?? .thirtyMinutes
        self.watcherIdleTimeout = (UserDefaults.standard.object(forKey: "watcherIdleTimeout") as? Int)
            .flatMap(WatcherIdleTimeout.init(rawValue:)) ?? .ten
        self.watcherAnimationsEnabled = UserDefaults.standard.object(forKey: "watcherAnimationsEnabled") as? Bool ?? true
        self.overlayDisplayTarget = OverlayDisplayTarget(
            rawValue: UserDefaults.standard.string(forKey: "overlayDisplayTarget") ?? OverlayDisplayTarget.followMenuBar.rawValue
        ) ?? .followMenuBar
        self.overlaySpecificDisplay = UserDefaults.standard.data(forKey: "overlaySpecificDisplay")
            .flatMap { try? JSONDecoder().decode(OverlayDisplayReference.self, from: $0) }
        self.watcherLocalWorkBotIds = Set(UserDefaults.standard.stringArray(forKey: "watcherLocalWorkBotIds") ?? [])
    }
}
