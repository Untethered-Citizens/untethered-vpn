// TweetNaCl leaves randombytes() to the caller. Only its key-pair functions
// use it, and Untethered VPN doesn't call those, but the library won't link
// without it. arc4random_buf is the system's cryptographic random generator.

#include <stdlib.h>

void randombytes(unsigned char *x, unsigned long long xlen)
{
    arc4random_buf(x, (size_t)xlen);
}
