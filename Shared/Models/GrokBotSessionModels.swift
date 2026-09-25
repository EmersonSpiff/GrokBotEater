import Foundation

enum GrokBotSessionState: String, Sendable {
    case idle
    case working
    case waitingOnUser
    case runningLocally
}

struct GrokBotSession: Identifiable, Sendable {
    let id: String
    let name: String
    let title: String?
    var displayName: String { title ?? name }
    
    var state: GrokBotSessionState
    var lastActivityAt: Date
    var awaitingUserResponse: Bool
    var unreadCount: Int
    var isHiddenFromSidebar: Bool
    
    /// True when the agent is currently streaming a response
    var isStreaming: Bool
    
    /// True when there's an active local command running (child of Node helper)
    var hasLocalWork: Bool
    
    /// Most recent transcript entry timestamp, if available
    var lastTranscriptTimestamp: Date?
    
    var isStale: Bool { Date().timeIntervalSince(lastActivityAt) > 180 }
    var isDead: Bool { Date().timeIntervalSince(lastActivityAt) > 3600 }
}

struct GrokBotRosterEntry: Codable {
    let id: String
    let name: String
    let title: String?
    let harness: String
    let origin: String
    let isGroup: Bool
    let memberIds: [String]?
    let createdAt: Int
    let updatedAt: Int
    let lastActivityAt: Int
    let lastViewedAt: Int
    let awaitingUserResponse: String?
    let hasUnread: Bool
    let unreadCount: Int
    let notificationsEnabled: Bool
    let isHiddenFromSidebar: Bool
}

struct GrokBotSessionMarker: Codable {
    let pid: Int
    let appVersion: String
    let startedAtMs: Int
    let aliveAtMs: Int
    let crashSeen: Bool?
}

struct GrokBotTranscriptReplica: Codable {
    let entries: [GrokBotTranscriptEntry]
    let epochHint: Int?
    let acceptedSequenceHint: Int?
    let persistedAt: Int?
}

struct GrokBotTranscriptEntry: Codable {
    let kind: String
    let timestampMs: Int
    let requestId: String?
    let role: String?
    let isStreaming: Bool?
    let message: GrokBotTranscriptMessage?
}

struct GrokBotTranscriptMessage: Codable {
    let type: String?
}

struct GrokBotPersistenceBlob: Codable {
    let schemaVersion: Int
    let value: GrokBotPersistenceValue
}

enum GrokBotPersistenceValue: Codable {
    case roster([GrokBotRosterEntry])
    case transcript(GrokBotTranscriptReplica)
    case unknown
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let roster = try? container.decode([GrokBotRosterEntry].self) {
            self = .roster(roster)
        } else if let transcript = try? container.decode(GrokBotTranscriptReplica.self) {
            self = .transcript(transcript)
        } else {
            self = .unknown
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .roster(let entries):
            try container.encode(entries)
        case .transcript(let replica):
            try container.encode(replica)
        case .unknown:
            try container.encodeNil()
        }
    }
}
