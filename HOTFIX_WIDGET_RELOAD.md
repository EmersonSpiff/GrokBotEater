# GrokBot Widget Reload Hotfix

## Quick Local Fix (1 minute)

If you need immediate relief before building from the PR branch, apply this one-line change directly to your current build:

### Location
`~/Developer/GrokBotEater/Shared/Helpers/WidgetReloader.swift`

### Change
**Line 20** (inside `scheduleReload()` method), add:
```swift
WidgetCenter.shared.reloadTimelines(ofKind: "GrokBotUsageWidget")
```

So the method becomes:
```swift
static func scheduleReload(delay: TimeInterval = 0.5) {
    pending?.cancel()
    let item = DispatchWorkItem {
        WidgetCenter.shared.reloadTimelines(ofKind: usageKind)
        WidgetCenter.shared.reloadTimelines(ofKind: pacingKind)
        WidgetCenter.shared.reloadTimelines(ofKind: "GrokBotUsageWidget")  // ← ADD THIS LINE
    }
    pending = item
    DispatchQueue.global(qos: .utility).asyncAfter(
        deadline: .now() + delay,
        execute: item
    )
}
```

### Rebuild
```bash
cd ~/Developer/GrokBotEater
xcodegen generate && \
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null && \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=S7B8M9JYF4 build && \
killall GrokBotEater 2>/dev/null; killall chronod 2>/dev/null; \
rm -rf /private/var/folders/*/*/com.apple.chrono 2>/dev/null; \
pluginkit -r -i com.emersonspiff.grokboteater.app.widget 2>/dev/null; \
sleep 2 && \
rm -rf /Applications/GrokBotEater.app && \
cp -R build/Build/Products/Release/GrokBotEater.app /Applications/ && \
xattr -cr /Applications/GrokBotEater.app && \
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R /Applications/GrokBotEater.app && \
sleep 2 && \
open /Applications/GrokBotEater.app
```

### Verify
1. Add the "GROK BOT / Weekly usage" widget to desktop (right-click > Edit Widgets > GrokBotEater)
2. Open GrokBotEater, go to Settings > Connection > Test (or just wait for auto-refresh)
3. Widget should update within 1–2 seconds instead of staying stale

---

## Proper Fix (PR #3)

The proper fix with notifications is already in [PR #3](https://github.com/EmersonSpiff/GrokBotEater/pull/3).

Checkout and build from the PR branch instead:
```bash
cd ~/Developer/GrokBotEater
git fetch origin
git checkout cursor/fix-grokbot-widget-notifications-58a1
# Then run the same build command above
```

This includes:
- The widget reload fix (same line as the hotfix above, but properly structured)
- Threshold notifications (warning @ 60%, critical @ 85%)
- Settings toggle for Grok Bot notifications (default ON)
- EN/FR localization
- Unit tests
