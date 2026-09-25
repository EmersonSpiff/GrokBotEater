import SwiftUI

struct GrokBotAgentCard: View {
    let session: GrokBotSession
    let proximity: CGFloat
    let scale: CGFloat
    let leftSide: Bool
    
    private var baseWidth: CGFloat { 30 * scale }
    private var expandedWidth: CGFloat { 185 * scale }
    private var height: CGFloat { 40 * scale }
    
    private var actualWidth: CGFloat {
        baseWidth + (expandedWidth - baseWidth) * proximity
    }
    
    private var stateColor: Color {
        switch session.state {
        case .working: return Color(red: 0.3, green: 0.7, blue: 1.0)
        case .waitingOnUser: return .orange
        case .runningLocally: return .purple
        case .idle: return .gray
        }
    }
    
    private var stateGlyph: String {
        switch session.state {
        case .working: return "brain.head.profile"
        case .waitingOnUser: return "hand.raised.fill"
        case .runningLocally: return "terminal.fill"
        case .idle: return "clock.fill"
        }
    }
    
    private var stateLabel: String {
        switch session.state {
        case .working: return "Working"
        case .waitingOnUser: return "Waiting"
        case .runningLocally: return "Local"
        case .idle: return "Idle"
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if !leftSide {
                Spacer(minLength: 0)
            }
            
            HStack(spacing: 8 * scale) {
                // State indicator
                ZStack {
                    Circle()
                        .fill(stateColor.opacity(0.3))
                        .frame(width: 28 * scale, height: 28 * scale)
                    
                    Image(systemName: stateGlyph)
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .foregroundStyle(stateColor)
                }
                
                if proximity > 0.3 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.displayName)
                            .font(.system(size: 12 * scale, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text(stateLabel)
                                .font(.system(size: 9 * scale, weight: .medium))
                                .foregroundStyle(stateColor.opacity(0.9))
                            
                            if session.unreadCount > 0 {
                                Text("\(session.unreadCount) unread")
                                    .font(.system(size: 8 * scale, weight: .medium))
                                    .foregroundStyle(.orange.opacity(0.8))
                            }
                            
                            if let lastActivity = session.lastTranscriptTimestamp {
                                let elapsed = Date().timeIntervalSince(lastActivity)
                                if elapsed < 60 {
                                    Text("now")
                                        .font(.system(size: 8 * scale))
                                        .foregroundStyle(.white.opacity(0.5))
                                } else if elapsed < 3600 {
                                    Text("\(Int(elapsed / 60))m ago")
                                        .font(.system(size: 8 * scale))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        }
                    }
                    .opacity(proximity > 0.3 ? 1 : 0)
                }
            }
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 6 * scale)
            .frame(width: actualWidth, height: height)
            .background(
                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    .fill(.black.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                            .stroke(stateColor.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4 * scale, x: 0, y: 2 * scale)
            )
            
            if leftSide {
                Spacer(minLength: 0)
            }
        }
    }
}

struct GrokBotAgentContextMenu: View {
    let session: GrokBotSession
    let onHide: () -> Void
    let onMenuOpen: () -> Void
    let onMenuClose: () -> Void
    
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    onMenuClose()
                    onHide()
                } label: {
                    Label("Hide", systemImage: "eye.slash")
                }
            }
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        onMenuOpen()
                    }
            )
    }
}
