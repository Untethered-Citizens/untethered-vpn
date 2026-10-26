# Vendored WireGuardKit

This folder is a copy of the library parts of [`wireguard-apple`](https://git.zx2c4.com/wireguard-apple) (MIT, see `COPYING`), changed so it builds and runs on tvOS. The iOS and macOS WireGuard apps themselves are not included.

## Upstream

| Component | Source | Revision |
|---|---|---|
| `Sources/WireGuardKit`, `Sources/WireGuardKitC`, `Sources/WireGuardKitGo`, `Package.swift` | `wireguard-apple` | `2fec12a6e1f6e3460b6ee483aa00ad29cddadab1` (2023-02-15) |
| `wireguard-go` (via `go.mod`) | `golang.zx2c4.com/wireguard` | `b3bc704ef0ee` (2026-10-24) |
| Go dependencies | `Sources/WireGuardKitGo/vendor/` (`go mod vendor`) | as listed in `go.mod` |

## Local changes

1. **tvOS behaves like iOS.** Every `#if os(iOS)` in `WireGuardKit` is now `#if os(iOS) || os(tvOS)`: the 1280-byte default MTU, the mobile roaming workaround, re-resolving endpoints for DNS64, and pausing the backend when the network goes away.
2. **`Package.swift`** declares tvOS 17 (the first tvOS with `NEPacketTunnelProvider`), uses tools version 5.9 to express it, and excludes the Go `vendor/` folder.
3. **`Makefile`** maps the `appletvos` and `appletvsimulator` SDKs to `GOOS=ios`. Go has no tvOS target, but its linker copies the platform from the cgo objects that clang builds against the tvOS SDK, so the result is tagged tvOS (or tvOS Simulator) correctly.
4. **`Makefile`** pins Go 1.27.x (the runtime patch `goruntime-boottime-over-monotonic.diff` is tied to the Go release) and builds offline: `GOTOOLCHAIN=local`, `GOFLAGS=-mod=vendor`, `GOPROXY=off`.
5. **`go.mod`** moves `wireguard-go` from the 2023 revision to `b3bc704ef0ee`, picking up upstream fixes including two from October 2026, and `golang.org/x/sys` to v0.49.0.

## Updating

1. Diff a fresh `wireguard-apple` checkout against the revision above and copy over any changes, keeping the local changes listed here.
2. In `Sources/WireGuardKitGo`: `go get golang.zx2c4.com/wireguard@master && go mod tidy && go mod vendor`.
3. If the Go minor version changes, check that the runtime patch still applies, then update `GO_VERSION_PINNED`.
4. Update the revisions in this file.

## Known limitation

`make` can't handle spaces in its target paths. Xcode builds into DerivedData, which normally has none; if you run the `Makefile` by hand, point `CONFIGURATION_BUILD_DIR` and `CONFIGURATION_TEMP_DIR` at a path without spaces.
