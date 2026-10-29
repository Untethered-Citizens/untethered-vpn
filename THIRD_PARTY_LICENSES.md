# Third-party licences

Untethered VPN is licensed under the Apache License 2.0 (the [`LICENSE`](LICENSE) file in the source code). It includes the following third-party code, each under its own licence. Where each copy came from, and any local changes, is recorded in the `VENDOR.md` next to it. The app shows this file on its About screen.

## WireGuardKit

- **Files:** `Vendor/WireGuardKit/` (the library parts of `wireguard-apple`, changed to run on tvOS)
- **Source:** <https://git.zx2c4.com/wireguard-apple>, revision `2fec12a6e1f6`
- **Authors:** WireGuard LLC
- **Licence:** MIT, full text under "MIT Licence (WireGuard LLC)" below.

## wireguard-go

- **Files:** `Vendor/WireGuardKit/Sources/WireGuardKitGo/vendor/golang.zx2c4.com/wireguard/` (compiled into the tunnel extension)
- **Source:** <https://git.zx2c4.com/wireguard-go>, revision `b3bc704ef0ee`
- **Authors:** WireGuard LLC
- **Licence:** MIT, full text under "MIT Licence (WireGuard LLC)" below.

## Go runtime and standard library, golang.org/x/crypto, golang.org/x/net, golang.org/x/sys

- **Files:** the Go toolchain (Go 1.27) and `Vendor/WireGuardKit/Sources/WireGuardKitGo/vendor/golang.org/x/` (compiled into the tunnel extension with wireguard-go)
- **Source:** <https://go.dev/>; `golang.org/x/crypto` v0.37.0, `golang.org/x/net` v0.39.0, `golang.org/x/sys` v0.49.0
- **Authors:** The Go Authors
- **Licence:** BSD 3-Clause, full text under "BSD 3-Clause Licence (The Go Authors)" below. Google's additional patent grant is in the `PATENTS` file next to each copy.

`golang.zx2c4.com/wintun` is also listed in the Go module files, but it is Windows-only and isn't compiled into the app.

## TweetNaCl

- **Files:** `Vendor/TweetNaCl/Sources/CTweetNaCl/tweetnacl.c`, `include/tweetnacl.h`
- **Source:** <https://tweetnacl.cr.yp.to/>, version 20140427
- **Authors:** Daniel J. Bernstein, Bernard van Gastel, Wesley Janssen, Tanja Lange, Peter Schwabe, Sjaak Smetsers
- **Licence:** public domain. In the authors' words, TweetNaCl "is a self-contained public-domain C library" (<https://tweetnacl.cr.yp.to/>).

## tweetnacl-js

- **File:** `Vendor/TweetNaCl/JS/nacl.js` (bundled in the app and served to the import page)
- **Source:** <https://github.com/dchest/tweetnacl-js>, npm `tweetnacl` 1.0.3
- **Authors:** Dmitry Chestnykh, Devi Mandiri and contributors (a port of TweetNaCl)
- **Licence:** The Unlicense (public domain dedication), full text under "The Unlicense" below.

# Licence texts

## MIT Licence (WireGuard LLC)

Copyright © 2018-2023 WireGuard LLC (WireGuardKit) and Copyright © 2017-2025 WireGuard LLC (wireguard-go). All Rights Reserved.

```
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## BSD 3-Clause Licence (The Go Authors)

```
Copyright 2009 The Go Authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google LLC nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## The Unlicense

```
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <http://unlicense.org>
```
