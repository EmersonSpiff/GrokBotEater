import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.emersonspiff.grokboteater.app", category: "GrokBotSessionMonitor")

/// Maximum age (in seconds) for a pending user message to count as Working state.
/// Older user messages indicate stale transcripts and should not pin the Working state.
private let maxPendingMessageAge: TimeInterval = 180 // 3 minutes

final class GrokBotSessionMonitorService: @unchecked Sendable {
    private let sessionsSubject = CurrentValueSubject<[GrokBotSession], Never>([])
    var sessionsPublisher: AnyPublisher<[GrokBotSession], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }
    
    private let rosterSubject = CurrentValueSubject<[GrokBotRosterEntry], Never>([])
    var rosterPublisher: AnyPublisher<[GrokBotRosterEntry], Never> {
        rosterSubject.eraseToAnyPublisher()
    }
    
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.emersonspiff.grokboteater.grokbot-session-monitor", qos: .utility)
    private var scanInterval: TimeInterval
    private var activityWindowSeconds: TimeInterval
    private var localWorkBotIds: Set<String> = []
    private let grokBotSupportDir: URL?
    
    private let axService: GrokBotAXWorkingService
    private var axWorkingStates: [String: Bool] = [:]
    private var axIsAvailable: Bool = false
    private var axTreeIsLive: Bool = false
    private var axCancellables: Set<AnyCancellable> = []
    
    
    private var lastLocalExecCount: Int = 0
    private var hasLoggedFirstScan: Bool = false
    private var lastLoggedState: [String: GrokBotSessionState] = [:]
    
    /// Minimum Working hold: agent id → (Date, isAXBased). Keep .working state until this time.
    private var workingHoldUntil: [String: (until: Date, isAXBased: Bool)] = [:]
    
    /// Last seen assistant reply timestamp per agent (for detecting missed turns)
    private var lastSeenReplyAt: [String: Date] = [:]
    
    /// Track if we've initialized lastSeenReplyAt (to avoid flashing all bots on launch)
    private var hasInitializedReplyTracking: Bool = false
    
    /// Transcript cache: agentId → (modDate, fileSize, parsed transcript)
    private var transcriptCache: [String: (modDate: Date, size: Int64, transcript: GrokBotTranscriptReplica)] = [:]
    
    /// Cached Grok Bot helper PIDs (refreshed when main Grok Bot PID changes)
    private var cachedMainGrokBotPid: Int32 = 0
    private var cachedHelperPids: Set<Int32> = []
    
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
        activityWindowSeconds: TimeInterval = 600,
        grokBotSupportDirOverride: URL? = nil,
        axService: GrokBotAXWorkingService? = nil
    ) {
        self.scanInterval = scanInterval
        self.activityWindowSeconds = activityWindowSeconds
        self.grokBotSupportDir = grokBotSupportDirOverride
        self.axService = axService ?? GrokBotAXWorkingService(grokBotSupportDirOverride: grokBotSupportDirOverride)
    }
    
    func startMonitoring() {
        // Bind to AX service publishers
        axService.workingStatePublisher
            .sink { [weak self] states in
                self?.queue.async {
                    self?.axWorkingStates = states
                }
            }
            .store(in: &axCancellables)
        
        axService.isAvailablePublisher
            .sink { [weak self] available in
                self?.queue.async {
                    self?.axIsAvailable = available
                    // Clear AX-based working holds when AX becomes unavailable
                    if !available {
                        self?.workingHoldUntil = self?.workingHoldUntil.filter { !$0.value.isAXBased } ?? [:]
                    }
                }
            }
            .store(in: &axCancellables)
        
        axService.treeIsLivePublisher
            .sink { [weak self] isLive in
                self?.queue.async {
                    self?.axTreeIsLive = isLive
                }
            }
            .store(in: &axCancellables)
        
        axService.startMonitoring()
        queue.async { [weak self] in self?.startTimerLocked() }
    }
    
    func stopMonitoring() {
        axService.stopMonitoring()
        axCancellables.removeAll()
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.sessionsSubject.send([])
            self?.rosterSubject.send([])
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
    
    func setLocalWorkBotIds(_ ids: Set<String>) {
        queue.async { [weak self] in
            self?.localWorkBotIds = ids
        }
    }
    
    func scan() {
        let fm = FileManager.default
        let supportDir = grokBotAppSupportDir
        
        guard fm.fileExists(atPath: supportDir.path) else {
            sessionsSubject.send([])
            rosterSubject.send([])
            return
        }
        
        // Read session marker for heartbeat check
        let markerPath = supportDir.appendingPathComponent("sand-session-marker.json")
        let isGrokBotRunning = isAppRunning(markerPath: markerPath)
        
        // Read roster
        guard let roster = readRoster(supportDir: supportDir) else {
            sessionsSubject.send([])
            rosterSubject.send([])
            return
        }
        
        // Publish full roster (all non-group, non-hidden entries)
        let availableRoster = roster.filter { !$0.isGroup && !$0.isHiddenFromSidebar }
        rosterSubject.send(availableRoster)
        
        // Build sessions
        let now = Date()
        logger.info("Grok Bot scan: roster has \(roster.count) entries, \(roster.filter { !$0.isGroup && !$0.isHiddenFromSidebar }.count) non-group visible entries")
        
        // Count local exec commands (local-work detection)
        let localExecCount = countLocalExecCommands()
        if !hasLoggedFirstScan || localExecCount != lastLocalExecCount {
            logger.info("Grok Bot scan: \(localExecCount) local exec command(s) detected")
            lastLocalExecCount = localExecCount
            hasLoggedFirstScan = true
        }
        
        // Log AX working states and check for unmatched names
        if axIsAvailable && !axWorkingStates.isEmpty {
            let workingNames = axWorkingStates.filter { $0.value }.map { $0.key }.sorted()
            logger.info("AX merge: working=[\(workingNames.joined(separator: ", "), privacy: .public)]")
            
            // Warn about AX names that don't match any roster entry
            let rosterNamesLower = Set(roster.filter { !$0.isGroup && !$0.isHiddenFromSidebar }.map { $0.name.lowercased() })
            for axName in axWorkingStates.keys {
                if !rosterNamesLower.contains(axName) {
                    logger.warning("AX: bot '\(axName, privacy: .public)' from tree not found in roster")
                }
            }
        }
        
        // Build sessions with for loop to allow mutation of AX done tracking state
        var sessions: [GrokBotSession] = []
        
        // Prune expired working holds
        let expiredHolds = workingHoldUntil.filter { $0.value.until < now }.keys
        for agentId in expiredHolds {
            workingHoldUntil.removeValue(forKey: agentId)
        }
        
        for entry in roster.filter({ !$0.isGroup && !$0.isHiddenFromSidebar }) {
            let lastActivity = Date(timeIntervalSince1970: Double(entry.lastActivityAt) / 1000.0)
            let nameLower = entry.name.lowercased()
            
            // Check AX working state (primary source when available AND tree is live)
            let axWorking: Bool?
            if axIsAvailable && axTreeIsLive {
                // AX tree is live - trust it
                axWorking = axWorkingStates[nameLower] ?? false
            } else if axIsAvailable && !axTreeIsLive {
                // AX available but tree stale (minimized/hidden) - use file-based signals
                axWorking = nil
            } else {
                // AX unavailable
                axWorking = nil
            }
            
            // Determine file-based working state for tracking when tree is stale
            let transcript = readTranscript(supportDir: supportDir, agentId: entry.id)
            let isStreaming = transcript?.entries.last?.isStreaming == true
            let fileBasedWorking = isStreaming || (transcript != nil && isLastEntryUserMessage(transcript!))
            
            // Detect missed turns: check if we have a new assistant reply we haven't seen
            let latestReplyTimestamp = transcript?.entries.last(where: { $0.kind == "send-message" && $0.role == nil }).map {
                Date(timeIntervalSince1970: Double($0.timestampMs) / 1000.0)
            }
            
            var detectedMissedTurn = false
            if hasInitializedReplyTracking, let latestReply = latestReplyTimestamp {
                let previousReply = lastSeenReplyAt[entry.id]
                let wasNotWorking = lastLoggedState[entry.id] != .working
                
                if wasNotWorking, let previous = previousReply, latestReply > previous {
                    // New reply appeared and we didn't see the bot working - missed turn
                    detectedMissedTurn = true
                } else if previousReply == nil && latestReply <= now {
                    // First time seeing a reply for this bot - initialize without triggering
                    lastSeenReplyAt[entry.id] = latestReply
                }
            } else if let latestReply = latestReplyTimestamp {
                // First scan - initialize all reply tracking without triggering
                lastSeenReplyAt[entry.id] = latestReply
            }
            
            // After detecting/handling, update lastSeenReplyAt if we have a newer timestamp
            if let latestReply = latestReplyTimestamp {
                lastSeenReplyAt[entry.id] = max(lastSeenReplyAt[entry.id] ?? .distantPast, latestReply)
            }
            
            // Determine if working from real signals only
            let hasRealSignal = (axWorking == true) || (axWorking == nil && fileBasedWorking) || detectedMissedTurn
            
            // Set working hold ONLY on real signal (not when hold is already active)
            if hasRealSignal {
                let holdUntil = now.addingTimeInterval(8.0)
                let previousHold = workingHoldUntil[entry.id]?.until ?? .distantPast
                if holdUntil > previousHold {
                    let isAXBased = (axWorking == true)
                    workingHoldUntil[entry.id] = (until: holdUntil, isAXBased: isAXBased)
                    let reason: String
                    if detectedMissedTurn {
                        reason = "newReply"
                    } else if isAXBased {
                        reason = "ax"
                    } else {
                        reason = "file"
                    }
                    logger.info("working hold \(entry.name, privacy: .public): reason=\(reason, privacy: .public) until=\(holdUntil, privacy: .public)")
                }
            }
            
            // Determine isWorking: real signal OR active hold (unless waitingOnUser)
            let holdActive = (workingHoldUntil[entry.id]?.until ?? .distantPast) > now
            let isWorking = (hasRealSignal || holdActive) && !entry.awaitingUserResponse
            
            // If working, bypass activity window
            let effectiveActivityTime: Date
            let bypassedActivityWindow: Bool
            if isWorking {
                // Working - bump activity to now so it's always visible
                effectiveActivityTime = now
                bypassedActivityWindow = true
            } else {
                effectiveActivityTime = lastActivity
                bypassedActivityWindow = false
            }
            
            // Filter by activity window (unless working or done)
            if !bypassedActivityWindow {
                guard now.timeIntervalSince(effectiveActivityTime) < activityWindowSeconds else {
                    continue
                }
            }
            
            let isWaitingOnUser = entry.awaitingUserResponse
            
            // Determine state from combined isWorking (real signal or active hold)
            let state: GrokBotSessionState
            if isWorking {
                state = .working
            } else if isWaitingOnUser {
                state = .waitingOnUser
            } else if entry.unreadCount > 0 {
                state = .done
            } else {
                state = .idle
            }
            
            let lastTranscriptTimestamp = transcript?.entries.last.map { entry in
                Date(timeIntervalSince1970: Double(entry.timestampMs) / 1000.0)
            }
            
            let session = GrokBotSession(
                id: entry.id,
                name: entry.name,
                title: entry.title,
                state: state,
                lastActivityAt: effectiveActivityTime,
                awaitingUserResponse: isWaitingOnUser,
                unreadCount: entry.unreadCount,
                isHiddenFromSidebar: entry.isHiddenFromSidebar,
                isStreaming: isStreaming,
                hasLocalWork: false,
                lastTranscriptTimestamp: lastTranscriptTimestamp
            )
            
            sessions.append(session)
        }
        
        // Log matched sessions for AX-working bots
        if axIsAvailable && !axWorkingStates.isEmpty {
            let workingNames = Set(axWorkingStates.filter { $0.value }.map { $0.key })
            let matchedSessions = sessions.filter { workingNames.contains($0.name.lowercased()) }.map { $0.id }
            logger.info("AX merge: matched sessions=[\(matchedSessions.joined(separator: ", "), privacy: .public)]")
        }
        
        // Log state changes for debugging
        for session in sessions {
            let oldState = lastLoggedState[session.id]
            if oldState != session.state {
                let oldStr = oldState?.rawValue ?? "nil"
                logger.info("state \(session.name, privacy: .public): \(oldStr, privacy: .public) → \(session.state.rawValue, privacy: .public)")
                lastLoggedState[session.id] = session.state
            }
        }
        
        // Attribution: If local commands are running, attribute runningLocally to a bot.
        // If the user assigned bots (Settings > Agent Watchers > 'Bots that use this Mac'),
        // pick the most recently active assigned bot (no time limit). Otherwise, fall back
        // to the most recently active visible bot within the last 10 minutes.
        // macOS hides other processes' environment (KERN_PROCARGS2), so per-agent
        // attribution from process data alone is not possible.
        if localExecCount > 0 {
            var targetBot: GrokBotSession?
            
            if !localWorkBotIds.isEmpty {
                // Use assigned list: pick most recent assigned bot
                // Include bots outside the visibility window (they get a card while running locally)
                targetBot = roster
                    .filter { !$0.isGroup && !$0.isHiddenFromSidebar }
                    .filter { localWorkBotIds.contains($0.id) }
                    .map { entry -> (id: String, lastActivityAt: Date) in
                        let lastActivity = Date(timeIntervalSince1970: Double(entry.lastActivityAt) / 1000.0)
                        return (id: entry.id, lastActivityAt: lastActivity)
                    }
                    .max(by: { $0.lastActivityAt < $1.lastActivityAt })
                    .flatMap { mostRecent in
                        // Find or create session for this bot
                        if let existing = sessions.first(where: { $0.id == mostRecent.id }) {
                            return existing
                        } else {
                            // Bot is outside visibility window - create a session for it
                            guard let entry = roster.first(where: { $0.id == mostRecent.id }) else { return nil }
                            let lastActivity = Date(timeIntervalSince1970: Double(entry.lastActivityAt) / 1000.0)
                            let transcript = readTranscript(supportDir: supportDir, agentId: entry.id)
                            let lastTranscriptTimestamp = transcript?.entries.last.map { entry in
                                Date(timeIntervalSince1970: Double(entry.timestampMs) / 1000.0)
                            }
                            return GrokBotSession(
                                id: entry.id,
                                name: entry.name,
                                title: entry.title,
                                state: .idle,
                                lastActivityAt: lastActivity,
                                awaitingUserResponse: entry.awaitingUserResponse,
                                unreadCount: entry.unreadCount,
                                isHiddenFromSidebar: entry.isHiddenFromSidebar,
                                isStreaming: false,
                                hasLocalWork: false,
                                lastTranscriptTimestamp: lastTranscriptTimestamp
                            )
                        }
                    }
            } else {
                // Fall back to heuristic: most recent visible bot within 10 minutes
                targetBot = sessions
                    .filter({ $0.state != .working && $0.state != .waitingOnUser && $0.state != .done })
                    .filter({ now.timeIntervalSince($0.lastActivityAt) < 600 })
                    .max(by: { $0.lastActivityAt < $1.lastActivityAt })
            }
            
            if let target = targetBot {
                logger.info("Grok Bot scan: attributing runningLocally to '\(target.name, privacy: .public)'")
                
                // Ensure target is in sessions array (might have been created above)
                if !sessions.contains(where: { $0.id == target.id }) {
                    sessions.append(target)
                }
                
                // Update state: respect precedence (working, waitingOnUser, done)
                sessions = sessions.map { session in
                    guard session.id == target.id else { return session }
                    
                    var updated = session
                    updated.hasLocalWork = true
                    
                    // Only change state if not already working, waitingOnUser, or done
                    if session.state != .working && session.state != .waitingOnUser && session.state != .done {
                        updated.state = .runningLocally
                    }
                    
                    return updated
                }
            }
        }
        
        logger.info("Grok Bot scan complete: \(sessions.count) active sessions found")
        sessionsSubject.send(sessions)
        
        // Mark reply tracking as initialized after first scan
        if !hasInitializedReplyTracking {
            hasInitializedReplyTracking = true
        }
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
            
            // Check cache: if file unchanged (mod date + size), return cached result
            let fm = FileManager.default
            guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  let fileSize = attrs[.size] as? Int64 else {
                logger.warning("Failed to read attributes for transcript blob: \(file.path)")
                continue
            }
            
            if let cached = transcriptCache[agentId],
               cached.modDate == modDate,
               cached.size == fileSize {
                return cached.transcript
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
            
            // Cache the result
            transcriptCache[agentId] = (modDate: modDate, size: fileSize, transcript: replica)
            
            return replica
        }
        
        return nil
    }
    
    private func isLastEntryUserMessage(_ transcript: GrokBotTranscriptReplica) -> Bool {
        guard let last = transcript.entries.last else { return false }
        
        // User messages have kind "message" with role "user"
        // Assistant replies have kind "send-message" with no role field (nil)
        guard last.kind == "message" && last.role == "user" else {
            return false
        }
        
        // Only treat as pending/working if recent (within maxPendingMessageAge)
        // Older user messages indicate stale transcripts, don't pin Working state
        let messageTime = Date(timeIntervalSince1970: Double(last.timestampMs) / 1000.0)
        let age = Date().timeIntervalSince(messageTime)
        return age < maxPendingMessageAge
    }
    
    /// Count local exec commands currently running on this Mac.
    /// Uses cached helper PIDs and only scans descendants of known Grok Bot helpers.
    /// Ignores long-lived MCP servers/connectors.
    private func countLocalExecCommands() -> Int {
        // Get Grok Bot processes to find NodeService helper PIDs
        let grokBotProcesses = ProcessResolver.findGrokBotProcesses()
        
        guard let mainProc = grokBotProcesses.first(where: { $0.isMainGrokBot }) else {
            cachedMainGrokBotPid = 0
            cachedHelperPids.removeAll()
            return 0
        }
        
        // Refresh helper cache only if main Grok Bot PID changed
        if mainProc.pid != cachedMainGrokBotPid {
            let nodeHelpers = grokBotProcesses.filter { proc in
                proc.parentPid == mainProc.pid && proc.args.contains("--utility-sub-type=node.mojom.NodeService")
            }
            cachedMainGrokBotPid = mainProc.pid
            cachedHelperPids = Set(nodeHelpers.map { $0.pid })
        }
        
        guard !cachedHelperPids.isEmpty else { return 0 }
        
        // Scan process list for children of NodeService helpers only
        let allProcesses = ProcessResolver.listAllProcesses()
        let localExecPattern = ["<&3"]  // The local-exec wrapper snapshot pattern
        
        var count = 0
        for proc in allProcesses {
            // Must be a child of one of the cached NodeService helpers
            guard cachedHelperPids.contains(proc.parentPid) else { continue }
            
            // Get the process path (only for descendants)
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let ret = proc_pidpath(proc.pid, &pathBuffer, UInt32(MAXPATHLEN))
            guard ret > 0 else { continue }
            let path = String(cString: pathBuffer)
            
            // Must be a shell (/bin/zsh or /bin/bash)
            guard path == "/bin/zsh" || path == "/bin/bash" else { continue }
            
            // Get arguments and check for wrapper pattern (only for shell processes)
            let args = ProcessResolver.getProcessArguments(pid: proc.pid)
            let hasWrapper = localExecPattern.allSatisfy { args.contains($0) }
            let hasShellFlag = args.contains("-c")
            
            if hasShellFlag && hasWrapper {
                count += 1
            }
        }
        
        return count
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
