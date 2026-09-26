import Foundation
import Combine
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.emersonspiff.grokboteater.app", category: "GrokBotAXWorking")

/// Detects Grok Bot agents' live 'Working' state from the Grok Bot desktop app's
/// Accessibility tree. Polls the AX tree for bot status every 3 seconds on a background queue.
final class GrokBotAXWorkingService: @unchecked Sendable {
    
    /// Publisher of [lowercased bot name: isWorking]
    private let workingStateSubject = CurrentValueSubject<[String: Bool], Never>([:])
    var workingStatePublisher: AnyPublisher<[String: Bool], Never> {
        workingStateSubject.eraseToAnyPublisher()
    }
    
    /// True when AX is trusted AND pid is alive AND at least one sand-agent-item was found
    private let isAvailableSubject = CurrentValueSubject<Bool, Never>(false)
    var isAvailablePublisher: AnyPublisher<Bool, Never> {
        isAvailableSubject.eraseToAnyPublisher()
    }
    
    /// True when the AX tree is live (app visible, at least one window not minimized)
    private let treeIsLiveSubject = CurrentValueSubject<Bool, Never>(false)
    var treeIsLivePublisher: AnyPublisher<Bool, Never> {
        treeIsLiveSubject.eraseToAnyPublisher()
    }
    
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.emersonspiff.grokboteater.ax-working", qos: .utility)
    private let grokBotSupportDir: URL?
    private var lastSetPid: pid_t = -1
    private var lastAvailableState: Bool? = nil
    private var lastWorkingStates: [String: Bool] = [:]
    private var lastTreeIsLive: Bool? = nil
    
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
    
    init(grokBotSupportDirOverride: URL? = nil) {
        self.grokBotSupportDir = grokBotSupportDirOverride
    }
    
    func startMonitoring() {
        queue.async { [weak self] in
            self?.startTimerLocked()
        }
    }
    
    func stopMonitoring() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.workingStateSubject.send([:])
            self?.isAvailableSubject.send(false)
            self?.lastAvailableState = nil
            self?.lastWorkingStates = [:]
        }
    }
    
    private func startTimerLocked() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 3.0)
        timer.setEventHandler { [weak self] in
            self?.scan()
        }
        timer.resume()
        self.timer = timer
    }
    
    private func scan() {
        // Check if Accessibility is trusted
        guard AXIsProcessTrusted() else {
            if lastAvailableState != false {
                logger.info("AX unavailable: not trusted for Accessibility")
                lastAvailableState = false
            }
            isAvailableSubject.send(false)
            treeIsLiveSubject.send(false)
            workingStateSubject.send([:])
            return
        }
        
        // Read desktop-status.json for current pid
        guard let status = readDesktopStatus(), status.signedIn == true else {
            if lastAvailableState != false {
                logger.info("AX unavailable: Grok Bot not running or not signed in")
                lastAvailableState = false
            }
            isAvailableSubject.send(false)
            treeIsLiveSubject.send(false)
            workingStateSubject.send([:])
            return
        }
        
        let pid = pid_t(status.pid)
        
        // Confirm pid is alive
        guard ProcessResolver.isProcessAlive(pid: pid) else {
            if lastAvailableState != false {
                logger.info("AX unavailable: pid \(pid) not alive")
                lastAvailableState = false
            }
            isAvailableSubject.send(false)
            treeIsLiveSubject.send(false)
            workingStateSubject.send([:])
            return
        }
        
        // Create app element and check if tree is live
        let app = AXUIElementCreateApplication(pid)
        let treeIsLive = isTreeLive(app: app)
        
        // Set AXManualAccessibility if pid changed, or if tree is not live (always reset)
        if lastSetPid != pid || !treeIsLive {
            let result = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            if result == .success {
                if lastSetPid != pid {
                    logger.info("AX: set AXManualAccessibility on pid \(pid)")
                    lastSetPid = pid
                }
            } else {
                logger.warning("AX: failed to set AXManualAccessibility on pid \(pid): \(result.rawValue)")
            }
        }
        
        // Log tree liveness changes
        if lastTreeIsLive != treeIsLive {
            logger.info("AX tree live: \(treeIsLive, privacy: .public)")
            lastTreeIsLive = treeIsLive
        }
        
        // Skip tree scan when tree is not live (minimized/hidden) - monitor ignores AX then
        treeIsLiveSubject.send(treeIsLive)
        if !treeIsLive {
            // Keep previous states and availability
            return
        }
        
        // Walk the tree for sand-agent-item elements
        let workingStates = scanAXTree(app: app)
        
        if workingStates.isEmpty {
            if lastAvailableState != false {
                logger.info("AX unavailable: no sand-agent-item elements found")
                lastAvailableState = false
            }
            isAvailableSubject.send(false)
            treeIsLiveSubject.send(treeIsLive)
            workingStateSubject.send([:])
            return
        }
        
        // AX is available
        if lastAvailableState != true {
            logger.info("AX available: found \(workingStates.count) bot(s) in tree")
            lastAvailableState = true
        }
        
        // Log state transitions
        for (name, isWorking) in workingStates {
            let wasWorking = lastWorkingStates[name] ?? false
            if isWorking != wasWorking {
                logger.info("AX: '\(name, privacy: .public)' working state: \(wasWorking) → \(isWorking)")
            }
        }
        lastWorkingStates = workingStates
        
        isAvailableSubject.send(true)
        treeIsLiveSubject.send(treeIsLive)
        workingStateSubject.send(workingStates)
    }
    
    /// Check if the AX tree is live: app not hidden, and at least one window not minimized
    private func isTreeLive(app: AXUIElement) -> Bool {
        // Check if app is hidden
        var hiddenValue: CFTypeRef?
        let hiddenResult = AXUIElementCopyAttributeValue(app, kAXHiddenAttribute as CFString, &hiddenValue)
        if hiddenResult == .success, let hidden = hiddenValue as? Bool, hidden {
            return false
        }
        
        // Get all windows
        var windowsValue: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue)
        guard windowsResult == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            return false
        }
        
        // Check if at least one window is not minimized
        for window in windows {
            var minimizedValue: CFTypeRef?
            let minimizedResult = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
            if minimizedResult == .success, let minimized = minimizedValue as? Bool, !minimized {
                return true
            } else if minimizedResult != .success {
                // If we can't read minimized state, assume it's not minimized
                return true
            }
        }
        
        return false
    }
    
    private func readDesktopStatus() -> GrokBotDesktopStatus? {
        let statusPath = grokBotAppSupportDir.appendingPathComponent("desktop-status.json")
        guard let data = try? Data(contentsOf: statusPath),
              let status = try? JSONDecoder().decode(GrokBotDesktopStatus.self, from: data) else {
            return nil
        }
        return status
    }
    
    /// Recursively walk the AX tree looking for elements with AXDOMClassList containing "sand-agent-item".
    /// Returns [lowercased bot name: isWorking].
    private func scanAXTree(app: AXUIElement) -> [String: Bool] {
        var result: [String: Bool] = [:]
        var visited = 0
        
        // Get all windows
        var windowsValue: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue)
        guard windowsResult == .success, let windows = windowsValue as? [AXUIElement] else {
            return result
        }
        
        for window in windows {
            walkElement(window, depth: 0, maxDepth: 25, visited: &visited, maxVisited: 3000, result: &result)
            if visited >= 3000 { break }
        }
        
        return result
    }
    
    private func walkElement(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        visited: inout Int,
        maxVisited: Int,
        result: inout [String: Bool]
    ) {
        visited += 1
        if visited > maxVisited || depth > maxDepth { return }
        
        // Check if this element has AXDOMClassList containing "sand-agent-item"
        if let classList = getAXDOMClassList(element), classList.contains("sand-agent-item") {
            // Parse AXDescription for name and working state
            if let description = getAXDescription(element) {
                let (name, isWorking) = parseAgentDescription(description)
                if !name.isEmpty {
                    result[name.lowercased()] = isWorking
                }
            }
        }
        
        // Recurse into children
        var childrenValue: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        guard childrenResult == .success, let children = childrenValue as? [AXUIElement] else {
            return
        }
        
        for child in children {
            walkElement(child, depth: depth + 1, maxDepth: maxDepth, visited: &visited, maxVisited: maxVisited, result: &result)
            if visited > maxVisited { break }
        }
    }
    
    private func getAXDOMClassList(_ element: AXUIElement) -> [String]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &value)
        guard result == .success else { return nil }
        return value as? [String]
    }
    
    private func getAXDescription(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }
    
    /// Parse AXDescription: "Name, Working" -> (name: "Name", isWorking: true)
    /// or "Name" -> (name: "Name", isWorking: false)
    /// or "Name, Something" -> (name: "Name", isWorking: suffix contains "Working")
    private func parseAgentDescription(_ description: String) -> (name: String, isWorking: Bool) {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Look for ", " separator
        if let commaIndex = trimmed.firstIndex(of: ",") {
            let nameEnd = commaIndex
            let name = String(trimmed[..<nameEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            let suffixStart = trimmed.index(after: commaIndex)
            let suffix = String(trimmed[suffixStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check if suffix components contain "Working"
            let components = suffix.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let isWorking = components.contains("Working")
            
            return (name: name, isWorking: isWorking)
        } else {
            // No comma, just the name
            return (name: trimmed, isWorking: false)
        }
    }
}

struct GrokBotDesktopStatus: Codable {
    let pid: Int
    let appVersion: String
    let startedAtMs: Int
    let signedIn: Bool?
}
