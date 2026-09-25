import Foundation

/// Identifies which display/screen the Agent Watchers overlay should appear on.
enum OverlayDisplayTarget: String, CaseIterable, Identifiable {
    case followMenuBar
    case mainDisplay
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .followMenuBar: return "Follow menu bar / active screen"
        case .mainDisplay: return "Main display"
        }
    }
}

/// Persistent reference to a specific physical display by CGDirectDisplayID + name fallback.
struct OverlayDisplayReference: Codable, Equatable {
    let displayID: UInt32
    let displayName: String
    
    init(displayID: UInt32, displayName: String) {
        self.displayID = displayID
        self.displayName = displayName
    }
}
