import Foundation

enum WatcherIdleTimeout: Int, CaseIterable, Identifiable {
    case three = 3
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30
    
    var id: Int { rawValue }
    
    var seconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }
    
    var label: String {
        switch self {
        case .three:
            return String(localized: "settings.watchers.idletimeout.3min")
        case .five:
            return String(localized: "settings.watchers.idletimeout.5min")
        case .ten:
            return String(localized: "settings.watchers.idletimeout.10min")
        case .fifteen:
            return String(localized: "settings.watchers.idletimeout.15min")
        case .thirty:
            return String(localized: "settings.watchers.idletimeout.30min")
        }
    }
}
