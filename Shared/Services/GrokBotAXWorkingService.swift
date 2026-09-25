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
    
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.emersonspiff.grokboteater.ax-working", qos: .utility)
    private let grokBotSupportDir: URL?
    private var lastSetPid: pid_t = -1
    private var lastAvailableState: Bool? = nil
    private var lastWorkingStates: [String: Bool] = [:]
    
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
            workingStateSubject.send([:])
            return
        }
        
        // Create app element and set AXManualAccessibility if pid changed
        let app = AXUIElementCreateApplication(pid)
        if lastSetPid != pid {
            let result = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            if result == .success {
                logger.info("AX: set AXManualAccessibility on pid \(pid)")
                lastSetPid = pid
            } else {
                logger.warning("AX: failed to set AXManualAccessibility on pid \(pid): \(result.rawValue)")
            }
        }
        
        // Walk the tree for sand-agent-item elements
        let workingStates = scanAXTree(app: app)
        
        if workingStates.isEmpty {
            if lastAvailableState != false {
                logger.info("AX unavailable: no sand-agent-item elements found")
                lastAvailableState = false
            }
            isAvailableSubject.send(false)
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
        workingStateSubject.send(workingStates)
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
