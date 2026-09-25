# Agent Watchers Overlay Investigation (Build 537)

## Issue Report
Owner tested build 536 and reported: "With Agent Watchers turned ON, NO Grok Bot watcher cards appear at all, even though Grok Bot agents are active on his Mac."

## Code Trace - Full Data Flow

### 1. GrokBotSessionMonitorService (Shared/Services/)
**Path**: Scans filesystem → builds GrokBotSession objects → publishes via Combine

```
scan() {
  1. Read ~/Library/Application Support/Grok Bot/sand-session-marker.json (heartbeat)
  2. Read roster.json (active agent list)
  3. Count local work processes (Node helper children)
  4. For each roster entry:
     - Filter by activity window (default 180s)
     - Read transcript.jsonl to determine state (working/idle/waitingOnUser)
     - Build GrokBotSession with state, lastActivityAt, etc.
  5. Publish sessions via sessionsSubject (CurrentValueSubject)
}
```

**Scan interval**: 3s default (settable via `setScanInterval`)  
**Activity window**: 180s default (settable via `setActivityWindow`)

### 2. GrokBotAgentSessionStore (Shared/Stores/)
**Path**: Subscribes to monitor service → filters dead/hidden sessions → exposes overlaySessions

```swift
var overlaySessions: [GrokBotSession] {
    activeSessions.filter { !hiddenSessionIds.contains($0.id) }
}

var activeSessions: [GrokBotSession] {
    sessions.filter { !$0.isDead }
}
```

**Started in**: `TokenEaterApp.swift` AppDelegate.init (lines 52-56)  
**Condition**: Only starts if `settingsStore.overlayEnabled == true`

### 3. OverlayWindowController (TokenEaterApp/Overlay/)
**Path**: Observes GrokBotAgentSessionStore → shows/hides panel → orders window front

```swift
Publishers.CombineLatest3(
    grokBotAgentSessionStore.$sessions,
    grokBotAgentSessionStore.$hiddenSessionIds,
    overlayState.$contextMenuSessionId
)
.map { sessions, hidden, openMenu in
    let visibleSessions = sessions.filter { !$0.isDead && !hidden.contains($0.id) }
    return openMenu != nil || !visibleSessions.isEmpty
}
.sink { hasVisible in
    if hasVisible { showOverlay() } else { hideOverlay() }
}
```

**showOverlay()**: 
- Creates NSPanel with floating level, borderless, non-activating
- Hosts OverlayView via NSHostingView
- Sets `.ignoresMouseEvents = true` initially (pass-through)
- Orders front with `panel.orderFront(nil)`
- Installs global mouse monitor for cursor tracking

### 4. OverlayView (TokenEaterApp/Overlay/)
**Path**: Renders GrokBotAgentCard for each session

```swift
private var displayedGrokBotSessions: [GrokBotSession] {
    overlayState.frozenGrokBotSessions ?? grokBotAgentSessionStore.overlaySessions
}

var body: some View {
    VStack {
        ForEach(displayedGrokBotSessions) { session in
            GrokBotAgentCard(session: session, proximity: prox, scale: scale, leftSide: leftSide)
        }
    }
}
```

**Card positioning**: Dock-like proximity scaling based on cursor distance  
**Side**: Left or right edge (controlled by `settingsStore.overlayLeftSide`)

## Potential Failure Points

### A. No Sessions Found (Most Likely)
**Symptom**: `GrokBotSessionMonitorService.scan()` returns empty array

**Possible causes**:
1. **Directory doesn't exist**: `~/Library/Application Support/Grok Bot/` not present
2. **roster.json missing or unreadable**: No agent roster file
3. **Activity window too short**: All agents outside 180s window (old lastActivityAt)
4. **isHiddenFromSidebar filter**: All roster entries marked hidden
5. **isGroup filter**: All entries are groups (not individual agents)

**Debug with logs**: Build 537 adds:
```
"Grok Bot scan: roster has X entries, Y non-group visible entries"
"Grok Bot scan complete: Z active sessions found"
```

### B. Store Not Started
**Symptom**: `GrokBotAgentSessionStore.sessions` never updates

**Check**: `settingsStore.overlayEnabled` must be `true` at app launch  
**Fix**: Settings > Agent Watchers > toggle ON

### C. Sessions Filtered Out
**Symptom**: Sessions exist but `overlaySessions` is empty

**Possible causes**:
1. All sessions marked `isDead` (state calculation issue)
2. All sessions in `hiddenSessionIds` (user dismissed them)

**Debug with logs**: Build 537 adds:
```
"Overlay session check: X total, Y visible, menuOpen=Z"
```

### D. Panel Never Shown
**Symptom**: showOverlay() not called or panel stays invisible

**Check**: 
- `settingsStore.overlayEnabled == true`
- `NSScreen.main` exists
- Panel level is `.floating`
- No other window blocking (full-screen app, etc.)

**Debug with logs**: Build 537 adds:
```
"showOverlay called: X Grok Bot agent sessions visible"
"Overlay visibility decision: hasVisible=X, enabled=Y"
```

### E. Hit-Test / Visibility Issue
**Symptom**: Panel exists but cards don't render or are transparent

**Check**:
- `overlayState.windowHeight/windowWidth` calculated correctly
- `activationZone` within screen bounds
- SwiftUI rendering (view hierarchy not collapsed)

## Build 537 Diagnostics

### Logging Added
Three strategic log points to trace the full flow:

1. **GrokBotSessionMonitorService.scan()** (line 103):
   ```swift
   logger.info("Grok Bot scan: roster has \(roster.count) entries, \(roster.filter { !$0.isGroup && !$0.isHiddenFromSidebar }.count) non-group visible entries")
   ```

2. **GrokBotSessionMonitorService.scan()** (line 150):
   ```swift
   logger.info("Grok Bot scan complete: \(sessions.count) active sessions found")
   ```

3. **OverlayWindowController.showOverlay()** (line 177):
   ```swift
   logger.info("showOverlay called: \(sessionCount) Grok Bot agent sessions visible")
   ```

4. **OverlayWindowController visibility publisher** (line 94):
   ```swift
   logger.info("Overlay session check: \(sessions.count) total, \(visibleSessions.count) visible, menuOpen=\(openMenu != nil)")
   ```

### How to Use Logs
```bash
# Stream logs in real-time
log stream --predicate 'subsystem == "com.emersonspiff.grokboteater.app" AND (category == "GrokBotSessionMonitor" OR category == "OverlayWindow")' --level info

# Or check Console.app:
# Filter: subsystem:com.emersonspiff.grokboteater.app
```

**Expected output when working**:
```
Grok Bot scan: roster has 3 entries, 3 non-group visible entries
Grok Bot scan complete: 2 active sessions found
Overlay session check: 2 total, 2 visible, menuOpen=false
Overlay visibility decision: hasVisible=true, enabled=true
showOverlay called: 2 Grok Bot agent sessions visible
```

**If no cards appear**:
- `roster has 0 entries` → Directory/file missing
- `0 non-group visible entries` → All hidden or groups
- `0 active sessions found` → Activity window filter dropped all
- `0 visible` → Sessions are dead or hidden
- `hasVisible=false` → Panel not shown
- `showOverlay called: 0` → No sessions reaching overlay

## Architecture is Correct

✅ All wiring verified:
- Monitor service publishes to store
- Store exposes `overlaySessions`
- Controller subscribes to store publisher
- View renders from `grokBotAgentSessionStore.overlaySessions`
- Panel creates correctly (NSPanel setup matches upstream TokenEater)

The issue is almost certainly **no sessions being found** by the monitor service, not a UI rendering bug.

## Next Steps for Owner

1. **Check logs** (see commands above) to see which stage fails
2. **Verify directory exists**: `ls -la ~/Library/Application Support/Grok Bot/`
3. **Check roster**: `cat ~/Library/Application Support/Grok Bot/roster.json | jq`
4. **Increase activity window** if agents are idle >3min: Settings > Agent Watchers > Visibility
5. **Report log output** so we can pinpoint the exact failure point

Build 537 should reveal exactly where the flow breaks.
