import SwiftUI

struct GrokBotAgentCard: View {
    let session: GrokBotSession
    let proximity: CGFloat
    let scale: CGFloat
    let leftSide: Bool
    let animationsEnabled: Bool
    let style: WatcherStyle
    let detailedMode: Bool
    let onTap: () -> Void
    
    private var baseWidth: CGFloat { 30 * scale }
    private var expandedWidth: CGFloat { 185 * scale }
    private var height: CGFloat { 40 * scale }
    
    private var actualWidth: CGFloat {
        baseWidth + (expandedWidth - baseWidth) * proximity
    }
    
    private var iconSize: CGFloat {
        let collapsedIconSize = 15.0 * scale
        let expandedIconSize = 16.0 * scale
        return collapsedIconSize + (expandedIconSize - collapsedIconSize) * proximity
    }
    
    private var stateColor: Color {
        if detailedMode {
            switch session.state {
            case .working: return Color(red: 0.3, green: 0.7, blue: 1.0)
            case .waitingOnUser: return .orange
            case .runningLocally: return .purple
            case .idle: return .gray
            case .done: return .green
            }
        } else {
            switch session.state {
            case .working, .runningLocally:
                return Color(red: 0.95, green: 0.62, blue: 0.22)
            case .waitingOnUser, .idle, .done:
                return Color(red: 0.3, green: 0.78, blue: 0.52)
            }
        }
    }
    
    private var neonColor: Color {
        if detailedMode {
            switch session.state {
            case .working: return Color(red: 0.2, green: 0.75, blue: 1.0)
            case .waitingOnUser: return Color(red: 1.0, green: 0.6, blue: 0.1)
            case .runningLocally: return Color(red: 0.8, green: 0.4, blue: 1.0)
            case .idle: return Color(red: 0.6, green: 0.6, blue: 0.65)
            case .done: return Color(red: 0.2, green: 1.0, blue: 0.5)
            }
        } else {
            switch session.state {
            case .working, .runningLocally:
                return Color(red: 1.0, green: 0.55, blue: 0.1)
            case .waitingOnUser, .idle, .done:
                return Color(red: 0.2, green: 1.0, blue: 0.55)
            }
        }
    }
    
    private var stateGlyph: String {
        switch session.state {
        case .working: return "sparkles"
        case .waitingOnUser: return "person.bubble"
        case .runningLocally: return "dot.scope.laptopcomputer"
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
                        // Line 1: Name in medium/semibold weight, followed by role chip
                        HStack(spacing: 6) {
                            Text(session.displayName)
                                .font(.system(size: 12 * scale, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .layoutPriority(1)
                            
                            if let role = session.roleLabel, role != session.displayName, !role.isEmpty {
                                Text(role)
                                    .font(.system(size: 9.5 * scale, weight: .regular))
                                    .foregroundStyle(Color.white.opacity(0.65))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 5 * scale)
                                    .padding(.vertical, 1.5 * scale)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4 * scale, style: .continuous)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 0.75)
                                    )
                                    .layoutPriority(0)
                            }
                        }
                        
                        // Line 2: Status and time info
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
        let materialOpacity = min(1.0, max(0.0, Double(proximity - 0.15) / 0.5))
        
        ZStack {
            if style == .frost {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.black.opacity(0.55))
                    .opacity(materialOpacity)
                
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(materialOpacity)
                
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(stateColor)
                    .opacity(max(0, 1 - materialOpacity) * 0.85)
                
                if proximity > 0.3 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(stateColor.opacity(0.15), lineWidth: 0.5)
                        .opacity(materialOpacity)
                }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.black.opacity(0.85))
                    .opacity(materialOpacity)
                
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(neonColor)
                    .opacity(max(0, 1 - materialOpacity) * 0.9)
                
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(neonColor.opacity(0.8), lineWidth: 1.5)
                    .opacity(materialOpacity)
            }
        }
        .shadow(color: shadowColor, radius: shadowRadius * scale, y: shadowY * scale)
    }
    
    private var shadowColor: Color {
        switch style {
        case .frost:
            return .black.opacity(Double(proximity) * 0.1)
        case .neon:
            return neonColor.opacity(Double(proximity) * 0.25)
        }
    }
    
    private var shadowRadius: CGFloat {
        switch style {
        case .frost: return 6
        case .neon: return 8
        }
    }
    
    private var shadowY: CGFloat {
        switch style {
        case .frost: return 2
        case .neon: return 0
        }
    }
    
    @ViewBuilder
    private var stateIcon: some View {
        let collapsedCircleSize = 5.0 * scale
        let expandedCircleSize = 28.0 * scale
        let circleSize = collapsedCircleSize + (expandedCircleSize - collapsedCircleSize) * proximity
        
        ZStack {
            if proximity > 0.3 {
                // Show circle background only when expanded
                Circle()
                    .fill(stateColor.opacity(0.3))
                    .frame(width: circleSize, height: circleSize)
            }
            
            stateIconImage
                .font(.system(size: iconSize, weight: .medium))
        }
    }
    
    @ViewBuilder
    private var stateIconImage: some View {
        let baseImage = Image(systemName: stateGlyph)
        let iconColor = proximity < 0.3 ? Color.white : stateColor
        
        applySymbolEffect(to: baseImage)
            .foregroundStyle(iconColor)
    }
    
    @ViewBuilder
    private func applySymbolEffect<V: View>(to view: V) -> some View {
        if animationsEnabled {
            switch session.state {
            case .working:
                view.symbolEffect(.bounce, options: .repeating)
            case .waitingOnUser:
                if #available(macOS 15, *) {
                    view.symbolEffect(.wiggle, options: .repeating)
                } else {
                    view.symbolEffect(.pulse, options: .repeating)
                }
            case .runningLocally:
                if #available(macOS 15, *) {
                    view.symbolEffect(.breathe)
                } else {
                    view.symbolEffect(.pulse)
                }
            case .done:
                view.symbolEffect(.scale)
            case .idle:
                view
            }
        } else {
            view
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
    }
}
