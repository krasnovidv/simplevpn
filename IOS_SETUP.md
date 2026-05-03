# iOS Setup Guide

Step-by-step guide to build and run the SimpleVPN iOS client.

## Prerequisites

- macOS 13+ with Xcode 15+
- Apple Developer account (paid, $99/year) — required for Network Extension entitlement
- Go 1.21+ with gomobile installed
- Flutter 3.19+

Install gomobile:
```bash
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

## 1. Build the Go xcframework

On macOS, from the `mobile/` directory:

```bash
make install-ios
```

This runs `gomobile bind -target=ios` and copies `Vpnlib.xcframework` to
`app/ios/Frameworks/Vpnlib.xcframework`.

## 2. Generate the Xcode project

```bash
cd mobile/app
flutter build ios --no-codesign
```

This generates `ios/Runner.xcworkspace`. Open it in Xcode.

## 3. Xcode project configuration

### 3.1 Add Vpnlib.xcframework to Runner target

1. Select the **Runner** target → **General** → **Frameworks, Libraries, and Embedded Content**
2. Click **+** → **Add Other…** → **Add Files…**
3. Navigate to `ios/Frameworks/Vpnlib.xcframework` and add it
4. Set embed to **Embed & Sign**

### 3.2 Create PacketTunnel extension target

1. **File → New → Target** → **Network Extension** → Next
2. Product Name: `PacketTunnel`
3. Bundle Identifier: `com.simplevpn.app.tunnel`
4. Language: Swift
5. Deployment Target: **iOS 15.0**

### 3.3 Add PacketTunnelProvider.swift to extension

1. Remove the default `PacketTunnelProvider.swift` Xcode created
2. Add `ios/PacketTunnel/PacketTunnelProvider.swift` to the **PacketTunnel** target

### 3.4 Add Vpnlib.xcframework to extension target

1. Select the **PacketTunnel** target → **General** → **Frameworks and Libraries**
2. Add `Vpnlib.xcframework` — set to **Do Not Embed** (the framework is already embedded in the app)

### 3.5 Set Info.plist for extension

1. Select **PacketTunnel** target → **Build Settings** → search `Info.plist`
2. Set **Info.plist File** to `PacketTunnel/Info.plist`
   (or replace the generated plist content with `ios/PacketTunnel/Info.plist`)

### 3.6 Set entitlements

**Runner target:**
1. Select **Runner** target → **Signing & Capabilities**
2. Click **+** → **App Groups** → add `group.com.simplevpn.app`
3. Click **+** → **Network Extensions** → check **Packet Tunnel**
4. Set **Code Signing Entitlements** to `Runner/Runner.entitlements`

**PacketTunnel target:**
1. Select **PacketTunnel** target → **Signing & Capabilities**
2. Add same App Group: `group.com.simplevpn.app`
3. Add **Network Extensions** → check **Packet Tunnel**
4. Set **Code Signing Entitlements** to `PacketTunnel/PacketTunnel.entitlements`

### 3.7 Provisioning profiles

Both the Runner and PacketTunnel targets need provisioning profiles with the
**Network Extension (Packet Tunnel)** capability. Create these in the Apple Developer portal
and download them, or use **Automatically manage signing** in Xcode if your account has the entitlement.

### 3.8 Set deployment target

Set **iOS Deployment Target** to **15.0** for both the **Runner** and **PacketTunnel** targets.

## 4. Build and run

Select your physical iPhone as the target (Network Extension does not work in the Simulator).

```
Product → Run  (⌘R)
```

The first time you connect, iOS will prompt the user to allow the VPN profile. Accept it.

## 5. Troubleshooting

**"Missing entitlement" error at runtime:** The provisioning profile for PacketTunnel must
include the `com.apple.developer.networking.networkextension` entitlement. Regenerate it
in the developer portal.

**Extension crashes immediately:** Check Xcode logs → open **Window → Devices and Simulators**
→ select your device → **Open Console** → filter by `simplevpn`. Look for Go-side crash logs.

**"RunTunnel called without a pending Preflight":** Preflight's 10-second watchdog fired —
`startTunnel` took too long between `setTunnelNetworkSettings` and calling `RunTunnel`.
Check for network latency or an unresponsive server.

**EMSGSIZE on socketpair write:** MTU 1380 fits within iOS DGRAM `maxdgram` (≥2048).
If you still see EMSGSIZE on-device, switch `PacketTunnelProvider` to `SOCK_STREAM`
with a 2-byte length prefix.

## Split Tunneling (Phase 4)

iOS split tunneling uses CIDR routes applied to `NEPacketTunnelNetworkSettings`:

| Mode | Implementation | Effect |
|------|---------------|--------|
| **Allowlist** | `ipv4Settings.includedRoutes = [parsed CIDRs]` | Only specified subnets route through VPN |
| **Blocklist** | `ipv4Settings.excludedRoutes = [parsed CIDRs]` | Specified subnets bypass VPN |
| **Off** | `includedRoutes = [NEIPv4Route.default()]` | All traffic through VPN (default) |

**Important:** an empty allowlist with mode=`allowlist` falls back to full tunnel (treated as `off`) to prevent traffic black-holing.

**Kill switch limitation:** `includeAllNetworks` requires iOS 14.2+. On older versions the kill switch is unavailable and the app emits an `unsupported_kill_switch` status to the UI.

## Bundle IDs

| Target | Bundle ID |
|---|---|
| Runner (main app) | `com.simplevpn.app` |
| PacketTunnel (extension) | `com.simplevpn.app.tunnel` |
| App Group | `group.com.simplevpn.app` |
