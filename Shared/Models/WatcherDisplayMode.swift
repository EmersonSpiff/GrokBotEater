import Foundation

enum WatcherDisplayMode: String, CaseIterable {
    case branchPriority
    case projectAndBranch

    var label: String {
        switch self {
        case .branchPriority: return "Most recent first"
        case .projectAndBranch: return "Waiting first"
        }
    }
    
    var icon: String {
        switch self {
        case .branchPriority: return "clock"
        case .projectAndBranch: return "hand.raised.fill"
        }
    }
}
