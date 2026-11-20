# Architecture

How Untethered VPN is put together and how to build it. Keep this file in step with the code.

## Non-negotiables

Every change has to keep these. A pull request that would break one isn't merged, however useful it is. [SECURITY.md](SECURITY.md) explains the threat model behind them.

- **Keys never leak.** Private and preshared keys live only in the Keychain, shared with the tunnel extension through an access group. They never appear in logs, the Tunnel Log, exports, review screens (masked), crash output, source, test fixtures or the repository.
- **No traffic but the tunnel.** The app's only network activity is the WireGuard tunnel and, while the import screen is showing, the import server. No analytics, ads, third-party SDKs, update checks or CDN calls; every web asset is served from the app bundle.
- **The import server stays tightly limited.** It listens only while the import screen is visible, never in the background. It takes one random one-time token in the URL path, a profile encrypted on the phone with a per-session key in the URL fragment, one successful submission and requests of at most 16 KB. It shuts down on success, cancel or a 5-minute timeout, and never logs request bodies.
- **Nothing is saved without confirmation on the TV.** Every import shows a parsed preview with the keys masked, and the user confirms it with the remote.
- **The Siri Remote alone** reaches every action, with large focus targets that can be read across a room.
- **Clean licensing.** No code from, or derived from, GPL projects. Every vendored component's licence is in `THIRD_PARTY_LICENSES.md`.
- **No accounts, servers of ours, analytics, ads or tracking.**

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
Vendor/TweetNaCl/          vendored TweetNaCl (C) and tweetnacl-js for the QR import (see VENDOR.md)
THIRD_PARTY_LICENSES.md    licences of everything vendored
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

`App/Home/`: `HomeView` shows a large `ProfileCard` for one profile, a `ProfileList` for several, and an empty state for none; `StatusLabel` is the coloured dot and status text, and `StatsLine` one line of stats under the connected profile. Details, Rename, Edit and Delete are a context menu (press and hold); the card also has a Details button. With several profiles, focus starts on the connected one, else the one connected last (`TunnelManager.preferredID`; `LastUsedProfile` keeps only its ID in the App Group defaults).

`App/Detail/ProfileDetail.swift` is one profile's screen: status, live stats, Connect/Disconnect, Rename, Edit, Export and Delete (with a confirmation).

### Export, Settings and About

`App/Detail/ProfileExport.swift` writes a profile out for troubleshooting with `WireGuardConfig.wgQuickText(maskingKeys: true, maskingEndpointHosts: true)`: private and preshared keys become `(hidden)` and each endpoint's host `hidden.example` (the port stays). `ExportView` shows the text and a QR code of the same text (`QRCodeTile`), so a phone camera can copy it; nothing goes over the network. `ProfileExportTests` decodes the QR code and checks no key or host is in it.

`App/Tutorial/`: How It Works, six cards (`TutorialCard`, `TutorialCardContent`) in `TutorialView`, with Skip, Back and Next. `SetupDiagram` draws the typical setup with shapes and SF Symbols. `TutorialPrompt` offers it by itself once, on a launch with no profiles (a flag in the app's own defaults); it also opens from the empty home screen and Settings. Card 2's QR code opens the README's "Set up a WireGuard server" (`Tutorial.serverGuideURL`); `TutorialTests` checks that anchor still matches a README heading. The app makes no network call for it.

`App/Settings/`: `SettingsView` (from the home header's Settings button) holds How It Works, `TunnelLogView` and `AboutView`. About shows the version, the licence and trademark notices, and `THIRD_PARTY_LICENSES.md`, bundled as a resource and split into blocks by `LicenceDocument`. Every paragraph takes focus so the remote can scroll.

### Tunnel Log

`Shared/Log/TunnelLog.swift` keeps short lines in the App Group container (`Library/Caches/TunnelLog/`: tvOS refuses writes to Application Support, and may purge Caches when storage runs low): the app writes `app.log` (Connect, Disconnect, Connect Automatically changes, never profile names) and the extension `tunnel.log` (its own steps and failures, and WireGuardKit's messages except wireguard-go's routine handshake, keepalive, worker and UAPI lines, `RoutineMessages`). Each process writes only its own file, keeping the newest 500 lines; the screen merges them newest first. Every line goes through `LogRedactor` before it's written: key-shaped text (base64 and hex) becomes `(hidden)`, the configured endpoint hosts `hidden.example`, and public IPv4/IPv6 addresses `(public IP)`; private, tunnel, link-local and CGNAT addresses stay. Clear Log stores a time in the App Group defaults and lines older than it are ignored, so the extension can't bring them back. `TunnelLogView` shows the lines and a QR code of the newest that fit in 1,200 bytes. The system log is unchanged. `-sampleSettings log` (with `-sampleProfiles`) shows sample lines through the real redactor. `AboutTests` checks the bundled copy matches the repository's and contains every vendored licence text, so update the file whenever a vendored component changes.

### Connect Automatically

`App/Tunnel/AutoConnect.swift`: on-demand rules (`NEOnDemandRuleConnect`, any interface) on one profile at a time, so tvOS brings the tunnel up by itself at startup, after sleep, on network changes and after a drop. `TunnelManager.setConnectsAutomatically` turns it on (and off for the others, then connects) or off. Disconnecting a profile with it on turns it off first, or tvOS would reconnect it; connecting another profile turns it off too. Both return `AutoConnect.TurnedOff` notes that the screens show in an alert. tvOS has no kill switch (`includeAllNetworks` is unavailable there, D36); the app never calls this one.

### Names

`App/Editor/ProfileName.swift` holds the name rules for every path that names a profile: not empty, at most 40 characters, and not another profile's name (ignoring case, width and surrounding spaces). `RenameView` changes only the name: `TunnelManager.rename` updates the VPN configuration's `localizedDescription`, leaving the config and Keychain alone. Manual entry checks the name in `ProfileDraft` (the editor passes the other profiles' names); the QR import's review shows a taken name under Name, disables Save and offers Rename.

### Live stats

The app can't see inside the tunnel, so it asks the extension. `TunnelManager.refreshStats(_:)` sends the app message `TunnelStats.request`; the extension's `handleAppMessage` reads wireguard-go's runtime state (`WireGuardAdapter.getRuntimeConfiguration`) and replies with a JSON `TunnelStats`: per peer, the endpoint in use, last handshake, and bytes received and sent. **The runtime state includes the private and preshared keys**: `TunnelStats(runtimeConfiguration:)` (in `Shared/Stats/`) reads only the fields above, and the raw text is never logged or returned. `TunnelStatsTests` checks that no key reaches the reply.

`HomeView` refreshes the connected profile's stats about once a second while the app is in front, into `TunnelManager.stats`, which both the home screen and Details read. `LiveStats` (`App/Tunnel/`) adds when the tunnel came up, measures ages, and flags silence: no handshake for over 3 minutes (`LiveStats.staleAfter`), counted from connecting if there's never been one. `StatsFormat` writes durations, byte counts (powers of 1,000) and the endpoint with its resolved address.

The simulator can't run tunnels, so Debug builds take two launch arguments for checking layouts: `-sampleProfiles one|several|failed|empty` fills the screen with sample entries (connecting one pretends to succeed; nothing touches the system or the Keychain), `-sampleStats live|stale|never` sets what a connected sample reports, `-sampleDetail YES` opens Details for the connected sample, `-sampleExport YES` (with `-sampleDetail`) opens its Export, `-sampleSettings main|log|about` opens Settings, the Tunnel Log or About, `-sampleRename <name>` opens Rename with that name typed in, `-sampleTutorial 1…6` opens How It Works on that card, and `-appearance light|dark` forces the appearance, which the tvOS simulator can't switch from the command line:

```sh
xcrun simctl launch <simulator id> com.untetheredcitizens.vpn -sampleProfiles several -appearance light
```

## Adding and editing profiles

`App/Editor/`: `ProfileEditor` is a full-screen cover holding a `ProfileDraft` and a navigation stack of `ProfileForm` → `ProfileReview`. One peer only (D30).

- `ProfileDraft` keeps one string per setting and checks each with the same validators as the config parser (`WireGuardKey`, `CIDRRange`, `PeerEndpoint`, `WireGuardConfig.dnsEntries` and `number`). Problems are plain sentences that never repeat the value. `makeProfile()` returns the profile only when every field is valid.
- Editing starts with the key fields blank; a blank key field keeps the saved key, so saved keys never return to the screen. ListenPort and any further peers (from a future QR import) are kept as they are.
- The form shows a field's problem once the field has changed, and every problem when Review is selected. Keys are typed into `SecureField`s; the review screen masks the private and preshared keys.
- Nothing is saved until Save on the review screen, which calls `TunnelManager.save`.

In Debug builds, `-sampleEditor add|filled|errors|review|edit` opens the editor at launch with sample values (random keys, documentation addresses). With `-sampleProfiles`, saving keeps the profile in memory only.

## QR import

The phone encrypts the config in the import page and the app decrypts it, so the config never crosses the local network in the clear. Browsers only offer WebCrypto to HTTPS pages, and the import page is plain HTTP, so the page uses tweetnacl-js and the app uses TweetNaCl, the C library it was ported from (both in `Vendor/TweetNaCl/`).

`App/Import/SecretBox.swift` wraps TweetNaCl's `secretbox` (XSalsa20-Poly1305):

- `SecretBox.Key.random()` makes a fresh 32-byte key per import session; `base64URL` is how it travels in the URL fragment (43 characters, no padding). Like `WireGuardKey`, a key's description is always masked.
- A sealed message is the 24-byte nonce followed by tweetnacl-js's box (16-byte tag, then the ciphertext). `SecretBox.open(_:key:)` returns nil for a wrong key, any changed byte, or input too short to be valid, without saying which.
- `Vendor/TweetNaCl/JS/nacl.js` is copied into the app bundle; the import page will be served with it. `SecretBoxTests` loads that same file into JavaScriptCore and checks both directions against the C code.

Only the app links TweetNaCl; the tunnel extension doesn't need it.

### The import server

`App/Import/ImportServer.swift` is the one-time web server the phone talks to. It listens only on the TV's own address on Ethernet or Wi-Fi (`LocalAddress`), never on a VPN tunnel interface, on a port the system picks. It reports `.ready(url:expires:)` once, then exactly one `.ended(_)`: `imported(ImportedProfile)`, `cancelled`, `timedOut`, `tooManyBadRequests` or `failed`. After it ends, nothing is listening. Events arrive on the server's own queue.

The rules live in `ImportSession` (no networking, fully unit-tested):

- **URL:** `http://<TV address>:<port>/<token>/#<key>`. The token is 128 random bits (22 base64url characters). The key never reaches the server, because browsers don't send the fragment.
- **Answers:** `GET /<token>/` (the page, `App/Import/Web/import.html`) and `GET /<token>/nacl.js`, from the bundle; `POST /<token>/` (the submission). `/<token>` redirects to `/<token>/`. Everything else is a bare 404.
- **Submission:** the page seals `{"name": "…", "config": "…"}` as JSON with `SecretBox` and posts it as base64 text.
  - A valid one ends the session.
  - A readable one with a bad name or config gets a 422 with the reason in plain words (never the value), and the session stays open for a fix.
- **Bad requests:** wrong token, wrong method, malformed or oversized requests, and anything that won't decrypt. After `maxBadRequests` (10) the session ends. `/favicon.ico` doesn't count.
- **Limits** (in `HTTPRequestParser` and the server):
  - 8 KB of headers and a 16 KB body, checked before buffering more
  - no chunked bodies
  - one request per connection
  - at most 4 connections, each closed after 10 seconds
  - the whole session ends after 5 minutes
- **Replies:** every reply carries `Cache-Control: no-store`, `Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff` and `Connection: close`. HTML also gets a strict `Content-Security-Policy`: only files from this server, no inline script, no framing.
- **Logging:** the server logs only that it started, its HTTP status codes, and how it ended. It never logs paths, bodies, the token or the key.

`ImportServerTests` runs the real server on 127.0.0.1 (`binding: .loopback`) and talks raw HTTP to it.

### The import screens and the phone page

- **Add Profile** opens `AddProfileView`: a choice between **Use Your Phone** (`PhoneImportView`) and **Type It In** (the existing `ProfileEditor`). Menu on the import screen returns to the choice.
- **`PhoneImport`** (main actor, observable) owns one `ImportServer` at a time and turns its events into `starting`, `waiting(url:expires:)`, `received(ImportedProfile)` or `ended(Problem)`. Events from a replaced server are ignored.
- **The server runs only while the import screen is visible and the app is active.**
  - `PhoneImportView` stops it on `onDisappear` and whenever `scenePhase` leaves `.active`.
  - When the app is active again, it starts a fresh session (new token and key) if a code was showing.
- **`PhoneImportView`** shows:
  - the QR code (`QRCode`: CoreImage's generator, black on white even in dark mode)
  - the address as text
  - a countdown with units
  - Cancel and Type It In Instead
  - "Trouble connecting?" help

  A received profile goes to `ProfileReview` with its warnings and a Cancel button; nothing is saved until Save.
- **The phone page** is `App/Import/Web/import.html`, `import.css` and `import.js`, served with `nacl.js` under the token.
  - `import.js` reads the key from the fragment, removes it from the address bar, and offers a file picker that reads a `.conf` on the phone.
  - It seals `{"name","config"}` with `nacl.secretbox` and shows the TV's answer.
  - The sealing code avoids browser-only APIs, so `ImportPageScriptTests` runs the real `import.js` in JavaScriptCore and feeds its output to `ImportSession`.
- **Local network:** `NSLocalNetworkUsageDescription` in the app's Info.plist explains the import, for when tvOS asks.

Debug launch arguments: `-sampleImport choose|waiting|received|timedOut|tooMany|noNetwork` shows each screen with sample data. `-sampleImport live` runs the real server, which in the simulator listens on the Mac's own network address, so the page can be tried from a browser on the Mac or a phone on the same network.

## Targets

| Target | Product | Notes |
|---|---|---|
| `UntetheredVPN` | `UntetheredVPN.app` | Embeds the extension. Links `CTweetNaCl` (local package `Vendor/TweetNaCl`) and bundles `nacl.js`. |
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

CI runs the same build and tests on every pull request and every push to `main` (`.github/workflows/build-test.yml`, on GitHub's `xcode-27` runner with Go 1.27.3), alongside the gitleaks secret scan (`secret-scan.yml`).

Device build: put your team ID in `Config.xcconfig` (copy `Config.sample.xcconfig`), then:

```sh
xcodebuild -scheme UntetheredVPN -destination 'id=<Apple TV UDID>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <Apple TV UDID> <DerivedData>/Build/Products/Debug-appletvos/UntetheredVPN.app
xcrun devicectl device process launch --device <Apple TV UDID> <your APP_BUNDLE_ID>
```

`xcrun devicectl list devices` shows the UDID of an Apple TV paired with Xcode. With automatic signing, the first device build registers the App IDs, the App Group and the Network Extension capability on your team.

Tunnel behaviour can only be checked on a real Apple TV; the simulator can't run packet-tunnel extensions.
