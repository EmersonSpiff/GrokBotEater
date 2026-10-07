# Browser-Based Authentication Implementation

## Overview

This document describes the browser-based PKCE authentication flow implemented for GrokBotEater to replace the in-app modal web view sign-in.

## How It Works

### 1. PKCE Generation

```swift
// Generate 32 random bytes
var randomBytes = [UInt8](repeating: 0, count: 32)
SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)

// Base64URL encode to create verifier
let verifier = Data(randomBytes).base64URLEncodedString()

// Challenge = base64url(SHA-256(verifier string))
let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
let challenge = challengeData.base64URLEncodedString()
```

**Important:** The SHA-256 is computed on the **UTF-8 bytes of the base64url verifier string**, not the raw 32 bytes. This matches the Cursor SDK specification and all reference implementations.

### 2. Browser Launch

```
https://cursor.com/loginDeepControl?challenge=...&uuid=...&mode=login&redirectTarget=sand&supportsSelectedTeamLogin=true
```

Query parameters:
- `challenge`: Base64URL-encoded SHA-256 hash of the verifier
- `uuid`: Lowercase UUID string (one-time nonce)
- `mode`: Always "login"
- `redirectTarget`: "sand" (Cursor's internal name for Grok Bot/usage API)
- `supportsSelectedTeamLogin`: "true" (team account support)

Opened via `NSWorkspace.shared.open(url)` to use the user's default browser.

### 3. Polling Loop

```
GET https://api2.cursor.sh/auth/poll?uuid=...&verifier=...
```

Response codes:
- **404**: User hasn't completed authentication yet → continue polling
- **200**: Success → JSON body contains `{"accessToken": "...", "refreshToken": "..."}`
- **403**: Authentication refused → error message in `{"error": "..."}` → abort
- **Other errors**: Network issues → continue polling (transient failures don't abort)

Poll interval: 2 seconds  
Timeout: 5 minutes (300 seconds)

### 4. Token Storage

The `accessToken` returned is used directly as the session cookie value:

```swift
let sessionCookie = tokens.accessToken
GrokBotSessionStore.shared.save(cookie: sessionCookie)
```

This is then used in the existing API calls:
```
Cookie: WorkosCursorSessionToken=<accessToken>
```

## Code Flow

```
User clicks "Connect"
    ↓
OnboardingViewModel.connect()
    ↓
Check for existing cookie
    ↓
[No cookie] → startBrowserAuth()
    ↓
Generate PKCE pair + UUID
    ↓
Open cursor.com/loginDeepControl in browser
    ↓
Show "Waiting for sign-in in your browser..." UI
    ↓
Start polling task: pollForBrowserAuth()
    ↓
Poll api2.cursor.sh/auth/poll every 2s
    ↓
[404] → Keep waiting
[200] → Got tokens → save & test connection
[403] → Show error
[Timeout] → Show timeout error
    ↓
Test connection with GrokBotAPIClient.fetchUsage()
    ↓
[Success] → Show connected state
```

## User Actions

### Cancel
Cancels the polling task and returns to idle state. User can retry.

### Sign in another way
Cancels browser auth and opens the in-app WKWebView fallback (existing implementation).

## Endpoints Verified

Research sources that confirm these endpoints:

1. **Cursor SDK (official)**
   - `@cursor/sdk@1.0.27/dist/cjs/auth/login-flow.d.ts`
   - Documents the exact PKCE flow and endpoints

2. **opencodex** (TypeScript)
   - `https://github.com/lidge-jun/opencodex/blob/main/src/oauth/cursor.ts`
   - Production implementation used by CLI tools

3. **Pulse** (Swift)
   - `https://github.com/qunqin24/Pulse/blob/main/Sources/Pulse/Auth/CursorWebLogin.swift`
   - Swift implementation with identical flow

4. **pi-cursor** (Rust/Multi-platform)
   - `https://github.com/Laurens-Nys/pi-cursor`
   - Provider documentation confirms endpoints

All sources use:
- `cursor.com/loginDeepControl` for browser login
- `api2.cursor.sh/auth/poll` for token retrieval
- Same PKCE construction method
- Same polling behavior (404 = pending)

## Compatibility

### Existing Features Preserved
- ✅ Keychain cookie reading (auto-detection)
- ✅ Chrome/Cursor cookie scraping (auto-detection)
- ✅ Cursor IDE `state.vscdb` reading (auto-detection)
- ✅ Widget refresh and shared JSON cache
- ✅ In-app web view fallback option

### Requirements
- macOS 14.0+ (deployment target)
- `NSWorkspace` (available since macOS 10.0)
- `CryptoKit.SHA256` (available since macOS 10.15, but deployment is 14.0)
- Async/await (Swift 5.9+)

## Testing Checklist

- [ ] Fresh install → Connect → browser opens
- [ ] Sign in via browser → app detects completion
- [ ] Connection test succeeds with browser-acquired token
- [ ] "Cancel" during waiting → returns to idle
- [ ] "Sign in another way" → opens in-app webview
- [ ] In-app webview still works correctly
- [ ] Timeout after 5 minutes → shows error
- [ ] Existing cookie detected → skips browser auth
- [ ] Widget updates after successful connection
- [ ] French localization displays correctly

## Files Changed

```
Shared/Services/CursorBrowserAuthService.swift (new)
TokenEaterApp/Onboarding/OnboardingViewModel.swift
TokenEaterApp/Onboarding/Cards/ConnectCard.swift
Shared/en.lproj/Localizable.strings
Shared/fr.lproj/Localizable.strings
project.yml (build 550 → 551)
```

## Pull Request

https://github.com/EmersonSpiff/GrokBotEater/pull/10

Branch: `cursor/browser-auth-flow-b267`

## Known Limitations

1. **No build verification in this environment:** VM lacks xcodegen/Xcode. Changes follow existing patterns but need local/CI testing.

2. **Updater script naming:** Bundled updater is still named "TokenEater" instead of "GrokBotEater" - noted in PR but not fixed here.

3. **Refresh token not used:** The flow receives a refresh token but we only store/use the access token. Refresh token support could be added later if token expiry becomes an issue.

## Future Enhancements

- Use refresh token for automatic renewal
- Add progress indicator showing poll attempts
- Retry with exponential backoff on network errors
- QR code option for mobile browser sign-in
