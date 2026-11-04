# Privacy policy

*Effective 2026-11-04*

Untethered VPN collects nothing about you and sends nothing anywhere except through the WireGuard tunnel you set up. There are no accounts, no analytics, no ads, no tracking, no crash reporting and no servers of ours.

## What the app keeps, on your Apple TV only

- **Your profiles:** each one's settings and keys, stored in the Apple TV's Keychain. The Keychain item never syncs to iCloud, and only the app and its own tunnel extension can read it.
- **Your settings:** things like the appearance and which profile you used last.
- **The Tunnel Log:** recent tunnel messages, kept so you can troubleshoot, with keys and your server's address hidden. Only the newest messages are kept; older ones are dropped.

None of this leaves the Apple TV unless you choose to show or send it: for example, by opening the Tunnel Log or a profile's Export and copying it into an issue. Deleting a profile in the app removes it.

## What goes over the network

- **Your tunnel.** When a profile is connected, the Apple TV's traffic goes to the WireGuard server named in that profile. That server is yours or belongs to whoever gave you the profile; what it does with the traffic is up to its operator, not this app.
- **The import page, only while Use Your Phone is showing.** The Apple TV runs a small web server on your local network so your phone can send it a profile. The phone encrypts the profile before sending it, the server accepts one profile and then stops, and it never logs what it receives. [SECURITY.md](https://github.com/Untethered-Citizens/untethered-vpn/blob/main/SECURITY.md) explains how it works.

The app makes no other connections: no update checks, no fonts or scripts from the web, and no third-party code that phones home.

## If you install with TestFlight

TestFlight is Apple's service, not part of this app, and Apple's own privacy terms apply to it. Apple gives the developer beta testing information such as session and crash counts, crash reports, and any feedback you choose to send. People who join through the public link show up as anonymous. The app itself still collects and sends nothing.

## Children

The app collects no information from anyone, including children.

## Changes

If this policy changes, the new version goes in this file with a new date, and the change shows in the repository's history.

## Questions

Please [open an issue](https://github.com/Untethered-Citizens/untethered-vpn/issues). For anything security-related, report it privately as described in [SECURITY.md](https://github.com/Untethered-Citizens/untethered-vpn/blob/main/SECURITY.md).
