<p align="center">
  <img src="TokenEaterApp/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="GrokBotEater">
</p>

<h1 align="center">GrokBotEater</h1>

<p align="center">
  <strong>Monitor your Grok Bot (Cursor) usage limits directly from your macOS desktop.</strong>
  <br />
  <sub>A fork of <a href="https://github.com/AThevon/TokenEater">TokenEater</a> by Adrien Thevon, adding Grok Bot tracking alongside Claude.</sub>
</p>

<p align="center">
  <a href="https://github.com/EmersonSpiff/GrokBotEater">Repository</a> ·
  <a href="#install">Install</a> ·
  <a href="#what-you-get">Features</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="https://github.com/EmersonSpiff/GrokBotEater/releases">Releases</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/WidgetKit-native-007AFF?logo=apple&logoColor=white" alt="WidgetKit">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

---

> **Fork of TokenEater**  
> This is a community fork adding **Grok Bot** weekly usage tracking via Cursor's `get-sand-usage-status` API.  
> Full credit to [Adrien Thevon](https://github.com/AThevon) for the original TokenEater architecture.  
> Branding may evolve; this is an experimental integration.

## What you get

A native menu bar app, desktop widgets, and a floating overlay that track your **Grok Bot** usage (and Claude, if configured).

- **Menu bar.** Live Grok Bot weekly usage percentage with color-coded thresholds. Add the Grok Bot segment to your menu bar composition.
- **Dashboard.** Monitoring view with Grok Bot usage ring and status (UI integration in progress).
- **Widgets.** Native WidgetKit gauges showing Grok Bot weekly progress (widget integration in progress).
- **Smart Color.** Adaptive coloring based on usage patterns.
- **Notifications.** Alerts when approaching weekly limits (Grok Bot notifications in progress).

**Current Status (2026-09-21):**
- ✅ Grok Bot API client and cookie authentication
- ✅ Ring-gating logic (respects shouldDrawRing, pooled/zero-limit flags)
- ✅ GrokBotUsageStore with auto-refresh
- ✅ Menu bar segment (GB label, shows when plan includes Grok Bot)
- 🚧 Dashboard UI (rings/tiles for Grok Bot)
- 🚧 Widget support
- 🚧 Onboarding flow for cookie detection

Inherited from TokenEater (Claude-focused, still functional):
- Claude usage tracking (5h/7d/model-specific)
- History from Claude Code JSONL logs
- Agent Watchers overlay for live Claude Code sessions
- Themes, pacing, smart notifications

## Install

### Build from source (required for now)

GrokBotEater is not yet distributed via DMG or Homebrew. Build instructions:

```bash
git clone https://github.com/EmersonSpiff/GrokBotEater.git
cd GrokBotEater
./build.sh
```

**Prerequisites:**
- macOS 14+
- Xcode 15+ (Swift 5.9)
- XcodeGen (`brew install xcodegen`)

The build script generates the Xcode project, inserts the required WidgetKit extension key, and builds in Debug mode. The resulting `GrokBotEater.app` is unsigned and will require right-click > Open on first launch.

**Detailed build steps:** See [`SETUP.md`](SETUP.md) for step-by-step instructions.

### First setup

**Prerequisites:**
- **Grok Bot access** via a Cursor plan that includes Grok Bot weekly usage.
- Logged in to Cursor at [cursor.com](https://cursor.com) (the app reads your browser's `CursorAppLogin` cookie from `~/Library/Application Support/Cursor/User Data/*/Cookies`).

**Initial configuration:**

1. Build and launch GrokBotEater
2. The app will auto-refresh Grok Bot usage every 5 minutes alongside Claude
3. Add Grok Bot to your menu bar:
   - Right-click menu bar icon > Open
   - Settings > Display > Menu Bar > Edit Composition
   - Add "Grok Bot" segment (shows when your plan includes it)

**Cookie authentication:**
- GrokBotEater reads the `CursorAppLogin` cookie from Cursor's Chromium cookie database
- If the cookie is not found: log in to Cursor at [cursor.com](https://cursor.com)
- If usage shows "Cursor session expired": log in again (cookies expire after ~60 days)
- [Inference] Encrypted v10+ Chromium cookies are not yet decrypted; if plain-value read fails, you'll see "Cursor session not found"

## Privacy

GrokBotEater is **read-only** and makes the following calls:

### Grok Bot tracking
- `POST https://cursor.com/api/dashboard/get-sand-usage-status` with your Cursor session cookie
- Returns `usagePercent` (0–100) for your weekly Grok Bot allocation
- No writes, no account modifications

### Claude tracking (inherited from TokenEater)
- `GET api.anthropic.com/api/oauth/usage` (usage stats)
- `GET api.anthropic.com/api/oauth/profile` (plan info)
- Uses the OAuth token Claude Code stores in macOS Keychain

All data stays local. The widget reads a cached JSON file with no network access. History and Agent Watchers parse local Claude Code JSONL logs without network calls.

**Cookie security:**  
The Cursor session cookie is read from Chromium/Cursor's SQLite cookie database (same pattern as browser extensions). The cookie is used only for the read-only `get-sand-usage-status` API. You can revoke access by logging out of Cursor at cursor.com.

**Source audit:**  
- Grok Bot: [`GrokBotAPIClient.swift`](Shared/Services/GrokBotAPIClient.swift), [`CursorCookieReader.swift`](Shared/Services/CursorCookieReader.swift)
- Claude: [`APIClient.swift`](Shared/Services/APIClient.swift), [`TokenProvider.swift`](Shared/Services/TokenProvider.swift)

## Update

GrokBotEater does not auto-update (Sparkle updater is neutralized to avoid conflicts with upstream TokenEater). Check this repo for new releases and rebuild from source.

## Uninstall

```bash
rm -rf /Applications/GrokBotEater.app
rm -rf ~/Library/Application\ Support/com.emersonspiff.grokboteater.shared
```

## Documentation

- [Setup](SETUP.md), building from source step by step
- [Troubleshooting](docs/TROUBLESHOOTING.md), common fixes (inherited from TokenEater)
- [Contributing](CONTRIBUTING.md), workflow and conventions
- [AGENTS.md](AGENTS.md), architecture, data flow, and SwiftUI rules for contributors/AI agents
- [Design system](docs/design/MASTER.md), window structure and coloring

## Contributing

Contributions welcome: bug reports, Grok Bot integration improvements, or feature ideas. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for workflow and testing guidelines.

## Upstream & Credits

**GrokBotEater** is a fork of **[TokenEater](https://github.com/AThevon/TokenEater)** by [Adrien Thevon](https://athevon.dev).  
All core architecture, SwiftUI patterns, widget infrastructure, and Agent Watchers are from TokenEater.  
This fork adds Grok Bot tracking via Cursor's dashboard API and renames the bundle to avoid conflicts.

If you want a polished, production-ready **Claude usage tracker**, use the upstream [TokenEater](https://github.com/AThevon/TokenEater).  
If you need **Grok Bot weekly usage** in the same UX, try this fork.

## License

MIT (same as upstream TokenEater)

---

<p align="center">
  Fork maintained by <a href="https://github.com/EmersonSpiff">EmersonSpiff</a>.
  <br />
  <sub>
    Original TokenEater by <a href="https://athevon.dev"><strong>Adrien Thevon</strong></a>.
  </sub>
</p>
