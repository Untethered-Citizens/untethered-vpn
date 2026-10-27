# Architecture

How Untethered VPN is put together and how to build it. Keep this file in step with the code.

## Layout

```
UntetheredVPN.xcodeproj    one project, one shared scheme: UntetheredVPN
Config.sample.xcconfig     default developer settings (committed)
Config.xcconfig            your own overrides (git-ignored, optional)
App/                       tvOS SwiftUI app            → target UntetheredVPN
TunnelExtension/           NEPacketTunnelProvider      → target UntetheredVPNTunnel
Shared/                    code compiled into both the app and the extension
Tests/                     Swift Testing unit tests    → target UntetheredVPNTests
  Fixtures.swift           synthetic configs; keys are random bytes made at run time
Support/                   Info.plists, entitlements, Base.xcconfig
Vendor/WireGuardKit/       vendored wireguard-apple library + wireguard-go (see VENDOR.md)
```

`App/`, `TunnelExtension/`, `Shared/` and `Tests/` are folder-synced groups: a Swift file added to one of those folders is part of its target(s) automatically, with no project-file edit. `Shared/` belongs to both the app and the extension, so its code is compiled twice; it must not import anything only one of them links (WireGuardKit is extension-only).

## Config parsing

`Shared/Config/` reads and writes `wg-quick` text without WireGuardKit, so both the app (import preview, manual entry) and the extension can use it:

- `WireGuardConfig.parse(_:)` returns a validated `WireGuardConfig` and a list of `ConfigWarning`s, or throws a `ConfigError`. Errors and warnings name the section, setting and line, never a value.
- The validators are failable initialisers: `WireGuardKey(base64:)`, `CIDRRange(_:)` and `CIDRRange.list(_:)`, `PeerEndpoint(_:)`. Manual entry uses them field by field.
- `wgQuickText(maskingKeys:)` writes the config back out; masked for the review screen.
- `WireGuardKey` prints as `(hidden)` everywhere; only `.base64` gives the real value.

## Profiles and tunnels

A profile is a name plus a checked `WireGuardConfig`, identified by a UUID (`Shared/Profiles/TunnelProfile.swift`). Each profile is stored in two places, and only one of them holds secrets:

- **Keychain** (`ConfigKeychain`): the whole `wg-quick` text, keys included, as one generic-password item in the shared access group (`KEYCHAIN_GROUP`). Never synchronised to iCloud; readable after the first unlock so the extension can start on its own.
- **System VPN preferences**: one `NETunnelProviderManager` per profile. Its protocol configuration (`TunnelProtocolInfo`) holds a persistent reference to the Keychain item (`passwordReference`), the profile ID, a format version and the first peer's endpoint for display. Nothing secret.

`App/Tunnel/TunnelManager.swift` is the app's side: load, save, delete, connect (disconnecting any other profile first), disconnect, and a live `TunnelStatus` per profile. The extension (`TunnelExtension/PacketTunnelProvider.swift`) reads the config through the reference, parses it with our parser, converts it to WireGuardKit's types (`WireGuardConfig+WireGuardKit.swift`) and starts `WireGuardAdapter`. If it can't, it records a `TunnelFailure` in the App Group's defaults and the app shows its message. Logs name the step and the failure, never a key or a config value; wireguard-go's own messages are logged as private.

The Keychain tests skip themselves when the test host is built with `CODE_SIGNING_ALLOWED=NO`, which leaves it without a Keychain entitlement. To run them, test without that flag (with a team in `Config.xcconfig`).

## Home screen

`App/Home/`: `HomeView` shows a large `ProfileCard` for one profile, a `ProfileList` for several, and an empty state for none; `StatusLabel` is the coloured dot and status text. Delete is a context menu (press and hold) with a confirmation.

The simulator can't run tunnels, so Debug builds take two launch arguments for checking layouts: `-sampleProfiles one|several|failed|empty` fills the screen with sample entries (connecting one pretends to succeed; nothing touches the system or the Keychain), and `-appearance light|dark` forces the appearance, which the tvOS simulator can't switch from the command line:

```sh
xcrun simctl launch <simulator id> com.untetheredcitizens.vpn -sampleProfiles several -appearance light
```

## Targets

| Target | Product | Notes |
|---|---|---|
| `UntetheredVPN` | `UntetheredVPN.app` | Embeds the extension. |
| `UntetheredVPNTunnel` | `UntetheredVPNTunnel.appex` | Links WireGuardKit (local package) and depends on `WireGuardGoBridge`. |
| `WireGuardGoBridge` | `libwg-go.a` | External build target: runs `make` in `Vendor/WireGuardKit/Sources/WireGuardKitGo` to cross-compile wireguard-go for `appletvos` or `appletvsimulator`. Needs Go 1.27.x. |
| `UntetheredVPNTests` | `UntetheredVPNTests.xctest` | Hosted in the app; `@testable import UntetheredVPN`. |

## Developer settings

`Support/Base.xcconfig` is the project's base configuration. It includes `Config.sample.xcconfig` and then, if it exists, `Config.xcconfig`, so your own values win:

| Setting | Default | Used for |
|---|---|---|
| `DEVELOPMENT_TEAM` | empty | Signing for a device |
| `APP_BUNDLE_ID` | `com.untetheredcitizens.vpn` | The app |
| `TUNNEL_BUNDLE_ID` | `$(APP_BUNDLE_ID).tunnel` | The extension |
| `APP_GROUP_ID` | `group.$(APP_BUNDLE_ID)` | Shared container for non-secret state |
| `KEYCHAIN_GROUP` | `$(APP_BUNDLE_ID).shared` | Shared Keychain items (keys); the team prefix is added when signing |

The entitlements and both Info.plists use these settings, and the code reads them back at run time through `AppConfiguration` (`Shared/AppConfiguration.swift`), so no identifier is hard-coded in Swift.

## Building

You need Xcode 27 with the tvOS platform and Go 1.27.x (`brew install go`).

`make` can't handle spaces in paths, so if your DerivedData path has any, pass `-derivedDataPath` with a path that doesn't.

Simulator build and tests:

```sh
xcodebuild -scheme UntetheredVPN \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Parallel testing clones the simulator, which takes minutes; the suite itself runs in well under a second.

Device build: put your team ID in `Config.xcconfig` (copy `Config.sample.xcconfig`), then:

```sh
xcodebuild -scheme UntetheredVPN -destination 'id=<Apple TV UDID>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <Apple TV UDID> <DerivedData>/Build/Products/Debug-appletvos/UntetheredVPN.app
xcrun devicectl device process launch --device <Apple TV UDID> <your APP_BUNDLE_ID>
```

`xcrun devicectl list devices` shows the UDID of an Apple TV paired with Xcode. With automatic signing, the first device build registers the App IDs, the App Group and the Network Extension capability on your team.

Tunnel behaviour can only be checked on a real Apple TV; the simulator can't run packet-tunnel extensions.
