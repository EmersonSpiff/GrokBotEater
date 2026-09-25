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
    let awaitingUserResponse: Bool
    let hasUnread: Bool
    let unreadCount: Int
    let notificationsEnabled: Bool
    let isHiddenFromSidebar: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name, title, harness, origin, isGroup, memberIds
        case createdAt, updatedAt, lastActivityAt, lastViewedAt
        case awaitingUserResponse, hasUnread, unreadCount
        case notificationsEnabled, isHiddenFromSidebar
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        title = try? container.decode(String.self, forKey: .title)
        harness = try container.decode(String.self, forKey: .harness)
        origin = try container.decode(String.self, forKey: .origin)
        isGroup = try container.decode(Bool.self, forKey: .isGroup)
        memberIds = try? container.decode([String].self, forKey: .memberIds)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        updatedAt = try container.decode(Int.self, forKey: .updatedAt)
        lastActivityAt = try container.decode(Int.self, forKey: .lastActivityAt)
        lastViewedAt = try container.decode(Int.self, forKey: .lastViewedAt)
        hasUnread = try container.decode(Bool.self, forKey: .hasUnread)
        unreadCount = try container.decode(Int.self, forKey: .unreadCount)
        notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        isHiddenFromSidebar = try container.decode(Bool.self, forKey: .isHiddenFromSidebar)
        
        // awaitingUserResponse can be String, object, or null - decode as Bool presence
        if let stringValue = try? container.decode(String.self, forKey: .awaitingUserResponse), !stringValue.isEmpty {
            awaitingUserResponse = true
        } else if let _ = try? container.decode([String: AnyCodable].self, forKey: .awaitingUserResponse) {
            awaitingUserResponse = true
        } else {
            awaitingUserResponse = false
        }
    }
}

private struct AnyCodable: Codable {
    init(from decoder: Decoder) throws {
        // Accept any JSON value
    }
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
    let epochHint: String?
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
    
    struct RosterWrapper: Codable {
        let rows: [GrokBotRosterEntry]
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var rowsArray = try container.nestedUnkeyedContainer(forKey: .rows)
            var entries: [GrokBotRosterEntry] = []
            while !rowsArray.isAtEnd {
                if let entry = try? rowsArray.decode(GrokBotRosterEntry.self) {
                    entries.append(entry)
                } else {
                    _ = try? rowsArray.decode(AnyCodable.self)
                }
            }
            self.rows = entries
        }
        
        enum CodingKeys: String, CodingKey {
            case rows
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try nested {"rows": [...]} structure first (roster blob)
        if let wrapper = try? container.decode(RosterWrapper.self) {
            self = .roster(wrapper.rows)
        }
        // Fallback to direct array (legacy format)
        else if let roster = try? container.decode([GrokBotRosterEntry].self) {
            self = .roster(roster)
        }
        // Try transcript
        else if let transcript = try? container.decode(GrokBotTranscriptReplica.self) {
            self = .transcript(transcript)
        }
        else {
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
