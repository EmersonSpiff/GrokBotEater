import SwiftUI

struct GrokBotAgentCard: View {
    let session: GrokBotSession
    let proximity: CGFloat
    let scale: CGFloat
    let leftSide: Bool
    let animationsEnabled: Bool
    let style: WatcherStyle
    let onTap: () -> Void
    
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
        case .done: return .green
        }
    }
    
    private var stateGlyph: String {
        switch session.state {
        case .working: return "sparkles"
        case .waitingOnUser: return "person.bubble"
        case .runningLocally: return "desktopcomputer.and.macbook"
        case .idle: return "moon.stars"
        case .done: return "checkmark.square"
        }
    }
    
    private var stateLabel: String {
        switch session.state {
        case .working: return "Working"
        case .waitingOnUser: return "Waiting"
        case .runningLocally: return "Local"
        case .idle: return "Idle"
        case .done: return "Done"
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if !leftSide {
                Spacer(minLength: 0)
            }
            
            HStack(spacing: 8 * scale) {
                // State indicator
                stateIcon
                
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
            .background(cardBackground)
            .onTapGesture {
                onTap()
            }
            
            if leftSide {
                Spacer(minLength: 0)
            }
        }
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        let cornerRadius = 8.0 * scale
        
        Group {
            if style == .frost {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.black.opacity(0.75))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(stateColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 4 * scale, x: 0, y: 2 * scale)
    }
    
    @ViewBuilder
    private var stateIcon: some View {
        let iconSize = 13.0 * scale
        let circleSize = 28.0 * scale
        
        ZStack {
            Circle()
                .fill(stateColor.opacity(0.3))
                .frame(width: circleSize, height: circleSize)
            
            stateIconImage
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(stateColor)
        }
    }
    
    @ViewBuilder
    private var stateIconImage: some View {
        let baseImage = Image(systemName: stateGlyph)
        
        if session.state == .runningLocally {
            baseImage.symbolRenderingMode(.multicolor)
        } else {
            baseImage
        }
        .modifier(StateSymbolEffect(state: session.state, animationsEnabled: animationsEnabled))
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

private struct StateSymbolEffect: ViewModifier {
    let state: GrokBotSessionState
    let animationsEnabled: Bool
    
    func body(content: Content) -> some View {
        if animationsEnabled {
            switch state {
            case .working:
                content.symbolEffect(.bounce, options: .repeating)
            case .waitingOnUser:
                if #available(macOS 15, *) {
                    content.symbolEffect(.wiggle, options: .repeating)
                } else {
                    content.symbolEffect(.pulse, options: .repeating)
                }
            case .runningLocally:
                if #available(macOS 15, *) {
                    content.symbolEffect(.breathe)
                } else {
                    content.symbolEffect(.pulse)
                }
            case .done:
                content.symbolEffect(.scale)
            case .idle:
                content
            }
        } else {
            content
        }
    }
}
