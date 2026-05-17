# Claude Desktop Buddy — iOS

An iPhone app that acts as a BLE hardware buddy for Claude for macOS / Windows.
Your phone becomes a desk companion: see active sessions, approve tool calls,
monitor token usage — all without touching your keyboard.

## How it works

The app implements the [Nordic UART Service](https://github.com/anthropics/claude-desktop-buddy/blob/main/REFERENCE.md)
peripheral role over CoreBluetooth. Claude for Desktop discovers and connects to it
exactly as it would an ESP32 — the protocol is identical.

## Project structure

```
Sources/ClaudeDesktopBuddy/
  ClaudeDesktopBuddyApp.swift   — App entry point
  BLEPeripheralManager.swift    — CoreBluetooth peripheral, NUS UUIDs, line-buffered I/O
  BuddyState.swift              — Data models + BuddyModel observable state machine
  ContentView.swift             — Root navigation (waiting vs connected)
  WaitingView.swift             — Advertising / pre-connection screen
  BuddyDashboardView.swift      — Connected dashboard (status / transcript / stats tabs)
Resources/
  Info.plist                    — BLE permissions + background mode entitlement
```

## Xcode setup (required steps)

The Swift files are framework-agnostic. To build as an iOS app:

### 1. Create a new Xcode project

- File → New → Project → iOS → App
- Product Name: `ClaudeDesktopBuddy`
- Interface: SwiftUI  |  Language: Swift
- Bundle Identifier: `com.yourname.claude-desktop-buddy`

### 2. Add the source files

Drag all `.swift` files from `Sources/ClaudeDesktopBuddy/` into the Xcode project.

### 3. Configure Info.plist

Copy the keys from `Resources/Info.plist` into your project's `Info.plist`, or replace it entirely:

| Key | Value |
|-----|-------|
| `NSBluetoothAlwaysUsageDescription` | (see Info.plist) |
| `UIBackgroundModes` | `bluetooth-peripheral` |
| `UIRequiredDeviceCapabilities` | `bluetooth-le` |

### 4. Signing

- Set your Team under Signing & Capabilities
- Change the bundle identifier to something unique

### 5. Add background capability

In Signing & Capabilities → + Capability → Background Modes → tick **Uses Bluetooth LE accessories**.
This matches the `bluetooth-peripheral` key in Info.plist and keeps the app advertising when locked.

### 6. Build and run on device

BLE peripheral mode does **not** work in Simulator. Connect a physical iPhone.

---

## Pairing with Claude for Desktop

1. Run the app on your iPhone — it starts advertising as `"Claude <your iPhone name>"`
2. On your Mac/PC: **Help → Troubleshooting → Enable Developer Mode**
3. **Developer → Open Hardware Buddy…**
4. Click **Connect** and pick your iPhone from the list
5. Grant Bluetooth permission when macOS prompts

The bridge auto-reconnects whenever both sides are awake.

---

## Supported protocol features

| Feature | Supported |
|---------|-----------|
| Heartbeat snapshot (state, sessions, tokens) | ✅ |
| Permission approve / deny | ✅ |
| Turn events (last assistant response) | ✅ |
| Owner name | ✅ |
| Time sync | ✅ (logged, not displayed) |
| Status polling | ✅ |
| Unpair command | ✅ |
| Folder / character push | ❌ (graceful no-op) |
| Link encryption (LE Secure Connections) | ❌ (implement via `CBPeripheralManagerOptionShowPowerAlertKey` + IO capability if needed) |

---

## Customisation ideas

- **Haptics**: trigger `UIImpactFeedbackGenerator` on approval prompts
- **Live Activity**: show session count on Lock Screen via ActivityKit
- **Shortcuts**: expose approve/deny as Shortcuts actions via AppIntents
- **Watch companion**: forward state to Apple Watch via WatchConnectivity
- **Encryption**: implement LE Secure Connections bonding for encrypted transcript data
