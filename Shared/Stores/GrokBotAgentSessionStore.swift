import Foundation
import Combine

@MainActor
final class GrokBotAgentSessionStore: ObservableObject {
    @Published var sessions: [GrokBotSession] = []
    @Published var roster: [GrokBotRosterEntry] = []
    @Published private(set) var hiddenSessionIds: Set<String> = []
    
    var activeSessions: [GrokBotSession] {
        sessions.filter { !$0.isDead }
    }
    
    var hasActiveSessions: Bool {
        !activeSessions.isEmpty
    }
    
    var overlaySessions: [GrokBotSession] {
        activeSessions.filter { !hiddenSessionIds.contains($0.id) }
    }
    
    var activeCount: Int {
        activeSessions.count
    }
    
    var waitingOnUserCount: Int {
        activeSessions.filter { $0.awaitingUserResponse }.count
    }
    
    var runningLocallyCount: Int {
        activeSessions.filter { $0.hasLocalWork }.count
    }
    
    func hideSession(id: String) {
        hiddenSessionIds.insert(id)
    }
    
    private let monitorService: GrokBotSessionMonitorService
    private var sessionsCancellable: AnyCancellable?
    private var rosterCancellable: AnyCancellable?
    
    init(monitorService: GrokBotSessionMonitorService = GrokBotSessionMonitorService()) {
        self.monitorService = monitorService
    }
    
    func bind() {
        sessionsCancellable = monitorService.sessionsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                guard let self else { return }
                self.sessions = sessions
                if !self.hiddenSessionIds.isEmpty {
                    let liveIds = Set(sessions.map { $0.id })
                    let stillLive = self.hiddenSessionIds.intersection(liveIds)
                    if stillLive != self.hiddenSessionIds {
                        self.hiddenSessionIds = stillLive
                    }
                }
            }
        
        rosterCancellable = monitorService.rosterPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] roster in
                self?.roster = roster
            }
    }
    
    func startMonitoring() {
        bind()
        monitorService.startMonitoring()
    }
    
    func stopMonitoring() {
        monitorService.stopMonitoring()
        sessionsCancellable = nil
        rosterCancellable = nil
    }
    
    func setScanInterval(_ seconds: TimeInterval) {
        monitorService.setScanInterval(seconds)
    }
    
    func setActivityWindow(_ seconds: TimeInterval) {
        monitorService.setActivityWindow(seconds)
    }
    
    func setLocalWorkBotIds(_ ids: Set<String>) {
        monitorService.setLocalWorkBotIds(ids)
    }
}
