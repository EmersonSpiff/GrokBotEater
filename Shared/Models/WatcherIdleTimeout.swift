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
        String(localized: "settings.watchers.idletimeout.\(rawValue)min")
    }
}
