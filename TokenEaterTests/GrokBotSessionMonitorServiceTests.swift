import Testing
import Foundation
@testable import GrokBotEaterApp

@Suite("Grok Bot Session Monitor Service")
struct GrokBotSessionMonitorServiceTests {
    
    @Test("Transcript entry decodes assistant reply without role field")
    func decodeAssistantReplyNoRole() throws {
        // Assistant replies in real Grok Bot transcripts have kind "send-message" with no role field
        let json = """
        {
            "kind": "send-message",
            "timestampMs": 1727293200000,
            "requestId": "req-123",
            "message": {
                "type": "text"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let entry = try JSONDecoder().decode(GrokBotTranscriptEntry.self, from: data)
        
        #expect(entry.kind == "send-message")
        #expect(entry.role == nil)
        #expect(entry.timestampMs == 1727293200000)
        #expect(entry.requestId == "req-123")
        #expect(entry.isStreaming == nil)
        #expect(entry.message?.type == "text")
    }
    
    @Test("Transcript entry decodes user message with role field")
    func decodeUserMessageWithRole() throws {
        // User messages in real Grok Bot transcripts have kind "message" with role "user"
        let json = """
        {
            "kind": "message",
            "timestampMs": 1727293100000,
            "role": "user",
            "requestId": "req-122",
            "isStreaming": false
        }
        """
        
        let data = json.data(using: .utf8)!
        let entry = try JSONDecoder().decode(GrokBotTranscriptEntry.self, from: data)
        
        #expect(entry.kind == "message")
        #expect(entry.role == "user")
        #expect(entry.timestampMs == 1727293100000)
        #expect(entry.requestId == "req-122")
        #expect(entry.isStreaming == false)
    }
    
    @Test("Transcript entry decodes minimal entry without optional fields")
    func decodeMinimalEntry() throws {
        // Ensure optional fields can be omitted without decode failure
        let json = """
        {
            "kind": "status-update",
            "timestampMs": 1727293000000
        }
        """
        
        let data = json.data(using: .utf8)!
        let entry = try JSONDecoder().decode(GrokBotTranscriptEntry.self, from: data)
        
        #expect(entry.kind == "status-update")
        #expect(entry.timestampMs == 1727293000000)
        #expect(entry.role == nil)
        #expect(entry.requestId == nil)
        #expect(entry.isStreaming == nil)
        #expect(entry.message == nil)
    }
    
    @Test("Transcript replica decodes with mixed entry types")
    func decodeTranscriptReplicaWithMixedEntries() throws {
        // Real transcript with both user messages and assistant replies
        let json = """
        {
            "entries": [
                {
                    "kind": "message",
                    "timestampMs": 1727293100000,
                    "role": "user",
                    "requestId": "req-122"
                },
                {
                    "kind": "send-message",
                    "timestampMs": 1727293200000,
                    "requestId": "req-123",
                    "message": {
                        "type": "text"
                    }
                }
            ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let replica = try JSONDecoder().decode(GrokBotTranscriptReplica.self, from: data)
        
        #expect(replica.entries.count == 2)
        
        // First entry is user message
        #expect(replica.entries[0].kind == "message")
        #expect(replica.entries[0].role == "user")
        
        // Second entry is assistant reply
        #expect(replica.entries[1].kind == "send-message")
        #expect(replica.entries[1].role == nil)
    }
}
