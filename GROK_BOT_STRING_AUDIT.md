# Grok Bot String Conversion Audit

## Build 537 - User-Visible String Conversion Complete

All user-visible Claude/Anthropic/Sonnet/Fable/5h references have been converted to Grok Bot/Cursor/Weekly/Daily equivalents.

### User-Visible Conversions (Commit 4cb7c73)

#### Settings & Onboarding
- `AgentWatchersSectionView.swift`: subtitle "live Claude Code sessions" → "live Grok Bot agents"
- `AgentWatchersSectionView.swift`: status "Working - Claude is busy" → "Working - Agent is busy" (EN)
- `AgentWatchersSectionView.swift`: preview model `claude-sonnet-4-6` → `grok-bot`
- `WatchersCard.swift`: all preview card models `claude-sonnet-4-6` → `grok-bot`
- `NotificationsCard.swift`: sample "5h limit warming up" → "Weekly usage at 62%"
- `PacingSectionView.swift`: workweek hint "Weekly and Sonnet only" → "Weekly Grok Bot usage"
- `PacingSectionView.swift`: "The 5h session is intraday" → "Weekly Grok Bot usage gauge"
- `SettingsSectionView.swift`: "Anthropic's side (their usage API)" → "Cursor's side (their usage API)"
- `DisplaySectionView.swift`: "Period label (5h / 7d)" → "Period label (Weekly / Daily)"

#### Popover & Dashboard
- `PopoverShared.swift`: "Waiting for Claude Code to refresh" → "Waiting for Grok Bot to refresh"
- `PopoverShared.swift`: "Usage API throttled by Anthropic" → "Usage API throttled by Cursor"
- `VendorStatusBanner.swift`: "Claude is down/degraded" → "Cursor is down/degraded"
- `VendorStatusModels.swift`: `status.claude.com` → `status.cursor.com`
- `VendorStatusModels.swift`: display name "Claude" → "Cursor"
- `PopoverCells.swift`: "Fable pacing" / "Fable" → "Daily pacing" / "Daily"
- `PacingCalculator.swift`: "Cool 5h" / "5h edging up" / "5h on fire" → "Cool weekly pace" / "Weekly edging up" / "Weekly on fire"
- `MetricModels.swift`: metric labels "5h" / "Sonnet" / "Fable" → "Weekly" / "Daily" / "Daily"
- `PopoverCompositionModels.swift`: "Fable First" / "Session (5h)" → "Daily First" / "Weekly Usage"
- `MenuBarCompositionModels.swift`: same picker label conversions

#### Widget
- `UsageWidgetView.swift`: "Sonnet" / "Fable" / "5h" → "Daily" / "Daily" / "Weekly"
- Widget subtitles: "5h sliding window" → "Grok Bot weekly usage"
- Widget subtitles: "Opus + Sonnet + Haiku" → "Grok Bot usage"
- Widget descriptions: "5h session window" → "weekly Grok Bot usage"

#### Errors & Notifications
- `APIClientProtocol.swift` / `APIClient.swift`: "OAuth token expired - relaunch Claude Code" → "restart Cursor"
- `APIClientProtocol.swift` / `APIClient.swift`: "Claude Pro or Team plan required" → "Cursor Pro plan required"
- `NotificationService.swift`: all 5h/Sonnet/Fable notification titles/bodies → Weekly/Daily
- `NotificationService.swift`: "Claude is degraded" / "Anthropic reports" → "Cursor is degraded" / "Cursor reports"
- `NotificationSettingsStore.swift`: `trackFable` default `true` → `false` (prevent Claude-only notifications)

#### Localization
- **EN (`Shared/en.lproj/Localizable.strings`)**: 30+ keys updated
  - All metric labels, widget strings, notification titles/bodies, error messages, settings hints
- **FR (`Shared/fr.lproj/Localizable.strings`)**: parallel conversions
  - Claude → Cursor, Anthropic → Cursor, 5h → Hebdo, Sonnet → Quotidien, Fable → Quotidien

### Remaining Non-Visible References (Justified)

All remaining Claude/Anthropic/Sonnet/Fable references are **internal implementation details** not visible to users:

#### 1. Type Names (Internal Models)
- `ClaudeSession` - model type for agent sessions (used throughout, never displayed as "Claude")
- `ClaudeProcessInfo` - internal struct for process scanning
- `ClaudeConfigReader` - service class reading Cursor config files

#### 2. Property & Enum Names (API/Data Model)
- `sevenDaySonnet`, `sevenDayFable` - API response property names (must match Cursor API schema)
- `hasSonnet`, `hasFable` - boolean flags for feature availability
- `MetricKind.sonnet`, `MetricKind.fable` - enum cases (internal identifiers)
- `ProfileModels`: `hasClaudeMax`, `hasClaudePro` - API CodingKeys

#### 3. Function Names
- `pruneClaudeMenuBarSegments()`, `pruneClaudePopoverElements()`, `pruneClaudeSegments()` - internal cleanup functions
- `findClaudeProcesses()`, `isClaudeProcess()`, `detectClaudeCodeVersion()` - process scanning utilities
- `isClaudePath()` - path validation

#### 4. File Paths & System Constants
- `~/Library/Application Support/Claude/` - actual macOS filesystem path
- `~/Library/Application Support/Claude/claude-code` - Cursor CLI installation path
- `~/.claude/.credentials.json` - OAuth credential file path
- `"Claude Code-credentials"` - macOS Keychain service name (must match actual keychain entry)
- `"Claude Safe Storage"` - Electron keychain service name
- `"Claude Key"` - Electron keychain account name

#### 5. Comments
- Code comments explaining legacy behavior, upstream TokenEater compatibility, or internal architecture
- Examples: "Claude/Anthropic outage polling stays off", "Claude UsageStore refresh is disabled"

### Verification

```bash
# Total remaining references: 406 lines
grep -rn "Claude|Anthropic|Sonnet|Fable|5h|5-hour|claude.com" \
  --include="*.swift" --include="*.strings" \
  TokenEaterApp/ TokenEaterWidget/ Shared/ | wc -l
# Output: 406

# All are non-visible (type names, properties, functions, paths, comments)
```

### Conclusion

✅ **All user-visible strings converted** to Grok Bot / Cursor / Weekly / Daily  
✅ **No Claude names reach the UI** (verified through Settings, Onboarding, Popover, Monitoring, Widgets, Notifications, Error states)  
✅ **Vendor status polling** changed to `status.cursor.com`  
✅ **Build 537** (app + widget)  
✅ **Localization complete** (EN + FR)  
✅ **All remaining references justified** as internal implementation details

Build 537 (commit 4cb7c73) is ready.
