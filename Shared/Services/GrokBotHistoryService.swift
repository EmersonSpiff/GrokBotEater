import Foundation
import os.log

private let logger = Logger(subsystem: "com.emersonspiff.grokboteater.app", category: "GrokBotHistory")

struct GrokBotHistorySnapshot: Codable {
    let timestamp: Date
    let weeklyPercent: Int
    let activeAgentCount: Int
    let dailyPercent: Int?
    let pacingDelta: Double?
}

struct GrokBotHistoryData: Codable {
    var snapshots: [GrokBotHistorySnapshot]
    
    func pruned(olderThan days: Int) -> GrokBotHistoryData {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        return GrokBotHistoryData(
            snapshots: snapshots.filter { $0.timestamp > cutoff }
        )
    }
}

/// Lightweight local history recorder: takes periodic snapshots of Grok Bot
/// usage and agent counts, stores them locally, and provides chart data.
final class GrokBotHistoryService {
    private let historyFile: URL
    private let snapshotInterval: TimeInterval = 3600 // 1 hour
    private let retentionDays = 30
    
    init(historyFile: URL? = nil) {
        if let override = historyFile {
            self.historyFile = override
        } else {
            let home: String
            if let pw = getpwuid(getuid()) {
                home = String(cString: pw.pointee.pw_dir)
            } else {
                home = NSHomeDirectory()
            }
            let supportDir = URL(fileURLWithPath: home)
                .appendingPathComponent("Library/Application Support/com.emersonspiff.grokboteater.shared")
            try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            self.historyFile = supportDir.appendingPathComponent("grokbot-history.json")
        }
    }
    
    func recordSnapshot(weeklyPercent: Int, activeAgentCount: Int, dailyPercent: Int?, pacingDelta: Double?) {
        var history = loadHistory()
        
        // Rate limit: don't record more than once per hour
        if let last = history.snapshots.last,
           Date().timeIntervalSince(last.timestamp) < snapshotInterval {
            return
        }
        
        let snapshot = GrokBotHistorySnapshot(
            timestamp: Date(),
            weeklyPercent: weeklyPercent,
            activeAgentCount: activeAgentCount,
            dailyPercent: dailyPercent,
            pacingDelta: pacingDelta
        )
        
        history.snapshots.append(snapshot)
        history = history.pruned(olderThan: retentionDays)
        
        saveHistory(history)
    }
    
    func loadHistory() -> GrokBotHistoryData {
        guard let data = try? Data(contentsOf: historyFile),
              let history = try? JSONDecoder().decode(GrokBotHistoryData.self, from: data) else {
            return GrokBotHistoryData(snapshots: [])
        }
        return history.pruned(olderThan: retentionDays)
    }
    
    private func saveHistory(_ history: GrokBotHistoryData) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: historyFile, options: .atomic)
    }
    
    func chartData(days: Int = 7) -> [(date: Date, weeklyPercent: Int, activeAgents: Int)] {
        let history = loadHistory()
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        
        return history.snapshots
            .filter { $0.timestamp > cutoff }
            .map { ($0.timestamp, $0.weeklyPercent, $0.activeAgentCount) }
    }
}
