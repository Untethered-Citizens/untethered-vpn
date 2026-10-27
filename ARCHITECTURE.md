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
Support/                   Info.plists, entitlements, Base.xcconfig
Vendor/WireGuardKit/       vendored wireguard-apple library + wireguard-go (see VENDOR.md)
```

`App/`, `TunnelExtension/`, `Shared/` and `Tests/` are folder-synced groups: a Swift file added to one of those folders is part of its target(s) automatically, with no project-file edit. `Shared/` belongs to both the app and the extension, so its code is compiled twice; it must not import anything only one of them links (WireGuardKit is extension-only).

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
  CODE_SIGNING_ALLOWED=NO test
```

Device build: put your team ID in `Config.xcconfig` (copy `Config.sample.xcconfig`), then:

```sh
xcodebuild -scheme UntetheredVPN -destination 'id=<Apple TV UDID>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <Apple TV UDID> <DerivedData>/Build/Products/Debug-appletvos/UntetheredVPN.app
xcrun devicectl device process launch --device <Apple TV UDID> <your APP_BUNDLE_ID>
```

`xcrun devicectl list devices` shows the UDID of an Apple TV paired with Xcode. With automatic signing, the first device build registers the App IDs, the App Group and the Network Extension capability on your team.

Tunnel behaviour can only be checked on a real Apple TV; the simulator can't run packet-tunnel extensions.
