# Security policy

## Reporting a vulnerability

Please **don't open a public issue** for a security problem.

Report it privately instead: on this repository, go to the **Security** tab and choose **Report a vulnerability**. Only the maintainer can see the report. Please include what you found, how to reproduce it, and which version or commit it affects.

You'll get a reply as soon as practical. This is a one-person project, so allow a few days. Once a fix is released, the report can be published with credit to you, if you'd like.

## What's in scope

Untethered VPN has no server of ours and no accounts. The most sensitive things it handles are:

- **WireGuard private and preshared keys**, stored in the Keychain and shared only with the app's own tunnel extension
- **Tunnel configurations**: server endpoints, addresses, DNS and allowed IPs
- **The temporary import server** the Apple TV runs on the local network while the import screen is showing, and the encryption that protects a configuration sent to it
- **Traffic through the tunnel**, including anything that could make traffic leak outside it

Anything that could leak, misuse or expose these is in scope. Problems with WireGuard itself, wireguard-go or WireGuardKit should go to the WireGuard project, and problems with your own WireGuard server to its software's maintainers.

A full threat model, including the import server's exposure on the local network, will be added here before the first release.

## Supported versions

Only the latest release and `main` receive fixes.
