#include "gcd.h"

/* Binary GCD (Stein's algorithm), one block per identity, unsigned a, b:
 *   (1) gcd(0, b) = b
 *   (2) gcd(2a, 2b) = 2 gcd(a, b)
 *   (3) gcd(2a, b) = gcd(a, b) when b is odd
 *   (4) gcd(a, b) = gcd(a, b - a) when a, b are odd and b >= a
 * After (3) both operands are odd, so b - a is even and (3) applies again;
 * every pass at least halves the product of the odd parts, so the loop runs
 * at most 64 times. uint32_t keeps the shifts logical and the comparisons
 * unsigned.
 */
uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    unsigned k = 0; /* (2): count the shared factors of two */
    while (((a | b) & 1) == 0) {
        a >>= 1;
        b >>= 1;
        k++;
    }

    while ((a & 1) == 0) /* (3): b is odd here */
        a >>= 1;

    do {
        while ((b & 1) == 0) /* (3): a is odd */
            b >>= 1;
        if (a > b) { /* make b >= a for (4) */
            uint32_t t = a;
            a = b;
            b = t;
        }
        b -= a; /* (4): odd - odd is even */
    } while (b != 0);

    return a << k; /* restore the 2^k removed by (2) */
}
