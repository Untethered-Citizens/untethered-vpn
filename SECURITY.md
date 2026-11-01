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

## Threat model

### What the app protects
- **Keys.** The whole profile, keys included, is stored as one Keychain item on the Apple TV. It never syncs to iCloud, and only the app and its own tunnel extension can read it (a shared Keychain access group). Keys never appear in logs, the Tunnel Log, the export, the review screens (they're masked), the tunnel's saved settings (which hold only the profile's ID) or the App Group.
- **The import.** A profile sent from a phone is encrypted on the phone before it leaves (see below), checked on the TV, and saved only after you confirm a preview on the TV with the remote.
- **Your privacy.** The app makes no network connections of its own: no analytics, no update checks, no fonts or scripts from the web. The only traffic is the WireGuard tunnel and, while the import screen is open, the import server.

### What it doesn't protect
- **Your WireGuard server**, its keys and its network. They're yours to secure.
- **Traffic while the tunnel is down.** tvOS doesn't let a VPN app block traffic outside the tunnel (there's no kill switch on Apple TV). Connect Automatically brings the tunnel back up after a restart, sleep or network change, but traffic can go out directly while it reconnects.
- **Someone with your Apple TV in hand**, or a compromised tvOS. A profile can be exported (with its keys hidden) by anyone holding the remote.
- **WireGuard itself.** Problems with the protocol, wireguard-go or WireGuardKit belong to the WireGuard project.

### The import server on your local network
Add Profile → **Use Your Phone** runs a small web server on the Apple TV, only while that screen is showing. The QR code holds its address, a one-time random token in the path, and a fresh encryption key in the part after `#`. Browsers don't send that part to the server. The phone page encrypts the profile with that key (NaCl secretbox: XSalsa20 and Poly1305) and sends only the sealed result. The server accepts one valid profile, refuses anything over 16 KB, and stops for good after a successful send, a cancel, 5 minutes or 10 bad requests. It never logs what it receives.

What someone else on the same network can do:
- **Watch the traffic:** they can see the token, because the page is served over plain HTTP (an Apple TV can't get a trusted certificate for a local address). They can't read the profile, because it's encrypted with a key that never crosses the network. They can end the import early by sending bad requests; start again on the TV.
- **Intercept and change the traffic** (for example by ARP spoofing on an open hotel network that doesn't keep devices apart): they could serve your phone a modified page that sends them the profile before it's encrypted. The encryption can't prevent this, because the page that does the encrypting comes over the same network.

So:
- **Import on a network you trust:** your home network, or your phone's Personal Hotspot with the Apple TV joined to it.
- **On a network you don't trust, type the profile instead** (Add Profile → **Type It In**, with your iPhone's keyboard if you like). That never touches the network.
- If you think a profile was captured, remove that peer on your server and make a new one.

## Supported versions

Only the latest release and `main` receive fixes.
