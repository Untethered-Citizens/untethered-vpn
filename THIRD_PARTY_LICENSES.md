# Third-party licences

Untethered VPN is licensed under the Apache License 2.0 (see [LICENSE](LICENSE)). It includes the following third-party code, each under its own licence. Where each copy came from, and any local changes, is recorded in the `VENDOR.md` next to it.

> Entries for WireGuardKit (`wireguard-apple`), `wireguard-go` and its Go dependencies (`Vendor/WireGuardKit/`) will be added before the v1.0 release.

## TweetNaCl

- **Files:** `Vendor/TweetNaCl/Sources/CTweetNaCl/tweetnacl.c`, `include/tweetnacl.h`
- **Source:** <https://tweetnacl.cr.yp.to/>, version 20140427
- **Authors:** Daniel J. Bernstein, Bernard van Gastel, Wesley Janssen, Tanja Lange, Peter Schwabe, Sjaak Smetsers
- **Licence:** public domain. In the authors' words, TweetNaCl "is a self-contained public-domain C library" (<https://tweetnacl.cr.yp.to/>).

## tweetnacl-js

- **File:** `Vendor/TweetNaCl/JS/nacl.js` (bundled in the app and served to the import page)
- **Source:** <https://github.com/dchest/tweetnacl-js>, npm `tweetnacl` 1.0.3
- **Authors:** Dmitry Chestnykh, Devi Mandiri and contributors (a port of TweetNaCl)
- **Licence:** The Unlicense (public domain dedication), full text in [`Vendor/TweetNaCl/JS/LICENSE`](Vendor/TweetNaCl/JS/LICENSE).
