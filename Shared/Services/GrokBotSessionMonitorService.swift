import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.emersonspiff.grokboteater.app", category: "GrokBotSessionMonitor")

final class GrokBotSessionMonitorService: @unchecked Sendable {
    private let sessionsSubject = CurrentValueSubject<[GrokBotSession], Never>([])
    var sessionsPublisher: AnyPublisher<[GrokBotSession], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }
    
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.emersonspiff.grokboteater.grokbot-session-monitor", qos: .utility)
    private var scanInterval: TimeInterval
    private var activityWindowSeconds: TimeInterval
    private let grokBotSupportDir: URL?
    
    private var grokBotAppSupportDir: URL {
        if let override = grokBotSupportDir { return override }
        let home: String
        if let pw = getpwuid(getuid()) {
            home = String(cString: pw.pointee.pw_dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Grok Bot")
    }
    
    init(
        scanInterval: TimeInterval = 3.0,
        activityWindowSeconds: TimeInterval = 180,
        grokBotSupportDirOverride: URL? = nil
    ) {
        self.scanInterval = scanInterval
        self.activityWindowSeconds = activityWindowSeconds
        self.grokBotSupportDir = grokBotSupportDirOverride
    }
    
    func startMonitoring() {
        queue.async { [weak self] in self?.startTimerLocked() }
    }
    
    func stopMonitoring() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.sessionsSubject.send([])
        }
    }
    
    private func startTimerLocked() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: scanInterval)
        timer.setEventHandler { [weak self] in
            self?.scan()
        }
        timer.resume()
        self.timer = timer
    }
    
    func setScanInterval(_ interval: TimeInterval) {
        queue.async { [weak self] in
            guard let self, interval != self.scanInterval else { return }
            self.scanInterval = interval
            if self.timer != nil { self.startTimerLocked() }
        }
    }
    
    func setActivityWindow(_ seconds: TimeInterval) {
        queue.async { [weak self] in
            self?.activityWindowSeconds = seconds
        }
    }
    
    func scan() {
        let fm = FileManager.default
        let supportDir = grokBotAppSupportDir
        
        guard fm.fileExists(atPath: supportDir.path) else {
            sessionsSubject.send([])
            return
        }
        
        // Read session marker for heartbeat check
        let markerPath = supportDir.appendingPathComponent("sand-session-marker.json")
        let isGrokBotRunning = isAppRunning(markerPath: markerPath)
        
        // Read roster
        guard let roster = readRoster(supportDir: supportDir) else {
            sessionsSubject.send([])
            return
        }
        
        // Get local work process count
        let localWorkCount = countLocalWorkProcesses()
        
        // Build sessions
        let now = Date()
        logger.info("Grok Bot scan: roster has \(roster.count) entries, \(roster.filter { !$0.isGroup && !$0.isHiddenFromSidebar }.count) non-group visible entries")
        
        let sessions = roster
            .filter { !$0.isGroup && !$0.isHiddenFromSidebar }
            .compactMap { entry -> GrokBotSession? in
                let lastActivity = Date(timeIntervalSince1970: Double(entry.lastActivityAt) / 1000.0)
                
                // Filter by activity window
                guard now.timeIntervalSince(lastActivity) < activityWindowSeconds else {
                    return nil
                }
                
                // Check transcript for working state
                let transcript = readTranscript(supportDir: supportDir, agentId: entry.id)
                let isStreaming = transcript?.entries.last?.isStreaming == true
                let isWaitingOnUser = entry.awaitingUserResponse != nil
                
                // Determine state
                let state: GrokBotSessionState
                if isStreaming || (transcript != nil && isLastEntryUserMessage(transcript!)) {
                    state = .working
                } else if isWaitingOnUser {
                    state = .waitingOnUser
                } else if localWorkCount > 0 {
                    state = .runningLocally
                } else {
                    // Idle, but check if it's "done" (recently finished with unread output)
                    let hasUnread = entry.unreadCount > 0
                    let recentlyActive = Date().timeIntervalSince(lastActivity) < 600 // 10 minutes
                    if hasUnread && recentlyActive {
                        state = .done
                    } else {
                        state = .idle
                    }
                }
                
                let lastTranscriptTimestamp = transcript?.entries.last.map { entry in
                    Date(timeIntervalSince1970: Double(entry.timestampMs) / 1000.0)
                }
                
                return GrokBotSession(
                    id: entry.id,
                    name: entry.name,
                    title: entry.title,
                    state: state,
                    lastActivityAt: lastActivity,
                    awaitingUserResponse: isWaitingOnUser,
                    unreadCount: entry.unreadCount,
                    isHiddenFromSidebar: entry.isHiddenFromSidebar,
                    isStreaming: isStreaming,
                    hasLocalWork: localWorkCount > 0,
                    lastTranscriptTimestamp: lastTranscriptTimestamp
                )
            }
        
        logger.info("Grok Bot scan complete: \(sessions.count) active sessions found")
        sessionsSubject.send(sessions)
    }
    
    private func isAppRunning(markerPath: URL) -> Bool {
        guard let data = try? Data(contentsOf: markerPath),
              let marker = try? JSONDecoder().decode(GrokBotSessionMarker.self, from: data) else {
            return false
        }
        
        let now = Date().timeIntervalSince1970 * 1000
        let aliveAge = now - Double(marker.aliveAtMs)
        
        guard aliveAge < 30000 else { return false }
        
        return ProcessResolver.isProcessAlive(pid: Int32(marker.pid))
    }
    
    private func readRoster(supportDir: URL) -> [GrokBotRosterEntry]? {
        let persistenceDir = supportDir.appendingPathComponent("sand-client-persistence")
        
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: persistenceDir,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        
        for file in files {
            guard file.pathExtension == "blob" else { continue }
            
            let filename = file.deletingPathExtension().lastPathComponent
            guard let decodedKey = decodeBase32(filename),
                  decodedKey.hasSuffix(".roster.last-roster") else {
                continue
            }
            
            guard let data = try? Data(contentsOf: file) else {
                logger.warning("Failed to read roster blob: \(file.path)")
                continue
            }
            
            guard let blob = try? JSONDecoder().decode(GrokBotPersistenceBlob.self, from: data) else {
                logger.warning("Failed to decode roster blob JSON: \(file.path)")
                continue
            }
            
            guard case .roster(let entries) = blob.value else {
                logger.warning("Roster blob value is not roster type: \(file.path)")
                continue
            }
            
            return entries
        }
        
        return nil
    }
    
    private func readTranscript(supportDir: URL, agentId: String) -> GrokBotTranscriptReplica? {
        let persistenceDir = supportDir.appendingPathComponent("sand-client-persistence")
        
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: persistenceDir,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        
        let targetSuffix = ".transcript.replicas.\(agentId)"
        
        for file in files {
            guard file.pathExtension == "blob" else { continue }
            
            let filename = file.deletingPathExtension().lastPathComponent
            guard let decodedKey = decodeBase32(filename),
                  decodedKey.hasSuffix(targetSuffix) else {
                continue
            }
            
            guard let data = try? Data(contentsOf: file) else {
                logger.warning("Failed to read transcript blob for agent \(agentId): \(file.path)")
                continue
            }
            
            guard let blob = try? JSONDecoder().decode(GrokBotPersistenceBlob.self, from: data) else {
                logger.warning("Failed to decode transcript blob JSON for agent \(agentId): \(file.path)")
                continue
            }
            
            guard case .transcript(let replica) = blob.value else {
                logger.warning("Transcript blob value is not transcript type for agent \(agentId): \(file.path)")
                continue
            }
            
            return replica
        }
        
        return nil
    }
    
    private func isLastEntryUserMessage(_ transcript: GrokBotTranscriptReplica) -> Bool {
        guard let last = transcript.entries.last else { return false }
        return last.kind == "send-message" && last.role != "assistant"
    }
    
    private func countLocalWorkProcesses() -> Int {
        let processes = ProcessResolver.findGrokBotProcesses()
        
        guard let mainProc = processes.first(where: { $0.isMainGrokBot }) else {
            return 0
        }
        
        let nodeHelper = processes.first { proc in
            proc.parentPid == mainProc.pid && proc.args.contains("--utility-sub-type=node.mojom.NodeService")
        }
        
        guard let helper = nodeHelper else { return 0 }
        
        return processes.filter { $0.parentPid == helper.pid }.count
    }
    
    private func decodeBase32(_ input: String) -> String? {
        let uppercased = input.uppercased()
        let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = 0
        var value = 0
        var output = Data()
        
        for char in uppercased {
            guard let index = base32Alphabet.firstIndex(of: char) else {
                continue
            }
            value = (value << 5) | base32Alphabet.distance(from: base32Alphabet.startIndex, to: index)
            bits += 5
            
            if bits >= 8 {
                output.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        
        return String(data: output, encoding: .utf8)
    }
}
