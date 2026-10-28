# Vendored TweetNaCl

The QR import encrypts a config on the phone with **tweetnacl-js** and the app decrypts it with **TweetNaCl**, the C library tweetnacl-js is a port of. Both implement NaCl's `secretbox` (XSalsa20-Poly1305). The page can't use the browser's own WebCrypto, because browsers only offer it to HTTPS pages and the import page is plain HTTP on the local network.

## Upstream

| File | Source | Version | SHA-256 | Licence |
|---|---|---|---|---|
| `Sources/CTweetNaCl/tweetnacl.c` | <https://tweetnacl.cr.yp.to/20140427/tweetnacl.c> | 20140427 | `02e65bc3013ff2168983365e55906bc783c4c7e0a60d8100f17bb303a17175c4` | Public domain |
| `Sources/CTweetNaCl/include/tweetnacl.h` | <https://tweetnacl.cr.yp.to/20140427/tweetnacl.h> | 20140427 | `43f29ad721d9927b747b0100ab4160c119e7bb180c7c98a66e4bf79d31244287` | Public domain |
| `JS/nacl.js`, `JS/LICENSE` | npm `tweetnacl` 1.0.3 (<https://github.com/dchest/tweetnacl-js>) | 1.0.3 | `nacl.js`: `2555523ab79e980c7aec94aaf6c80e3c120fba04e9c4a95ab9faa7878602380e` | Unlicense (public domain) |

The npm tarball `tweetnacl-1.0.3.tgz` matched the registry's published integrity, `sha512-6rt+RN7aOi1nGMyC4Xa5DdYiukl2UWCbcJft7YhxReBGQD7OAM8Pbxw6YMo4r2diNEA8FEmu32YOn9rhaiE5yw==`. `nacl.js` is the unminified build, a direct port of the C code, kept readable on purpose; the app bundle serves this file to the import page.

## Local changes

1. `tweetnacl.h` moved into `include/` so Swift Package Manager exposes it as the `CTweetNaCl` module. Its contents are unchanged.
2. `randombytes.c` added: TweetNaCl expects the caller to supply `randombytes()`. It uses `arc4random_buf`. Only TweetNaCl's key-pair functions call it, and the app doesn't use them.

3. `Package.swift` turns off clang's `-Wshorten-64-to-32` for this target only. It flags five lines (`tweetnacl.c` 410, 411, 430, 431, 548) in Curve25519 and SHA-512, which secretbox doesn't use, where the narrowed values are a 0-or-1 bit or a leftover byte count under 128. The code is left as published.

Both downloaded files are otherwise byte-for-byte as published; check with `shasum -a 256`.

## How the app uses it

Only the app links `CTweetNaCl` (the tunnel extension doesn't). `App/Import/SecretBox.swift` wraps `crypto_secretbox_xsalsa20poly1305_tweet` and `…_open`. Swift can't see the C header's short macro names such as `crypto_secretbox`, so it calls the full names.

## Updating

Both upstreams are stable: TweetNaCl hasn't changed since 2014, and tweetnacl-js 1.0.3 (2020) is its latest release. If either does change, replace the file, record the new version and hash here, and run the tests. `SecretBoxTests` runs `nacl.js` in JavaScriptCore against the C code in both directions.
