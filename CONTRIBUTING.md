# Contributing to Untethered VPN

Thanks for your interest. This is a small project with one maintainer, so the process is kept simple and predictable. Please read this page before opening an issue or a pull request.

## How a change gets in

1. **Open an issue first.** Describe the bug or the idea. Every pull request must link an issue that the maintainer has agreed to, including what "done" looks like. Pull requests without an agreed issue are closed, however good the code is, so your time isn't wasted on something that won't be merged.
2. **Fork the repo and make a branch** from an up-to-date `main`, named `<type>/<issue>-<short-slug>`:
   - `fix/` for a bug, `feature/` for an enhancement, `docs/` for documentation, `chore/` for tooling and cleanup
   - One issue per branch. Unrelated changes belong in their own issue.
3. **Make small commits** with imperative messages ("Add profile list").
4. **Before opening the pull request:** it builds, all tests pass, new logic has tests, and UI changes have been checked in the tvOS simulator (light and dark mode where it matters).
5. **Open the pull request** and fill in the template. Put `Closes #N` on its own line.
6. **CI** scans every push and pull request for secrets; building and testing on CI comes later. Every check must be green before merging.
7. **Review.** The maintainer reviews every pull request and may ask for changes. Only the maintainer merges, using squash merge.

Anything that touches the tunnel, the network extension or the import server is proven on a real Apple TV, not just the simulator. Say in the pull request which device and tvOS version you tested on.

## Building and testing

Untethered VPN is built with Xcode for tvOS 26 or later, and needs Go to cross-compile wireguard-go. [ARCHITECTURE.md](ARCHITECTURE.md) has the code layout and the build, test and run commands. Running it on an Apple TV needs a paid Apple developer account, because the app uses a Network Extension.

Every push and pull request is scanned for secrets with [gitleaks](https://github.com/gitleaks/gitleaks). To run the same scan before you push:

```sh
gitleaks git . --redact
```

## The rules that keep it trustworthy

Please keep these in mind before changing the tunnel, key storage, logging or the import server:

- **Keys never leak.** Private and preshared keys live only in the Keychain. They never appear in logs, exports, review screens (they're masked), crash output, source code, test fixtures or the repo.
- **No traffic but the tunnel.** The only network activity is the tunnel itself and the temporary import server on the local network. No analytics, ads, third-party SDKs or CDN calls; every web asset is served from the app bundle.
- **The import server is tightly limited.** It runs only while the import screen is showing, uses a one-time random token and client-side encryption, accepts one small submission, and shuts down on success, cancel or after 5 minutes. It never logs request bodies.
- **Nothing is saved without confirmation on the TV.** Every import shows a preview with keys masked, and the user confirms with the remote.
- **The Siri Remote alone** reaches every action.
- **Clean licensing.** No code from, or derived from, GPL projects. Third-party licences are listed in the repo.

Pull requests that touch these areas must say so in the template.

## Out of scope

Untethered VPN has no accounts, servers, analytics, ads, tracking or subscriptions, and it connects only to WireGuard servers you run yourself. Changes that add any of these won't be accepted. Commercial VPN provider integrations are out of scope too.

## Security

Never commit a key, password or real WireGuard configuration, even a revoked one. Test configs use generated throwaway keys, documentation addresses such as `192.0.2.0/24` and `example.com` endpoints. If your change touches network calls, stored keys or anything that listens on the network, tick the security box in the pull request template so it gets a closer review.

To report a vulnerability, don't open an issue. See [SECURITY.md](SECURITY.md).

## Licence

The code is under the [Apache License 2.0](LICENSE). By opening a pull request, you agree that your contribution is licensed under the same terms, and that you have the right to submit it.

The licence covers the code only. The name "Untethered VPN", its icon and the Untethered Citizens branding aren't licensed for reuse. If you publish your own version, please give it a different name and icon.

"WireGuard" is a registered trademark of Jason A. Donenfeld. This project is not affiliated with or endorsed by the WireGuard project.

## Conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
