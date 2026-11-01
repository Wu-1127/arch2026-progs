#include "fixed.h"

/* op1: a + b with bitwise passes (Quiz 3, blanks C01 and C02). Each pass
 * keeps a + b unchanged modulo 2^32, since x + y = (x ^ y) + 2 (x & y); after
 * pass k the low k bits of the carry word are zero, so at most 32 passes.
 */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;
    while (b) {
        uint32_t c = (a & b) << 1; /* carries, moved up one position */
        a = a ^ b;                 /* sum without carries */
        b = c;
        ++*n;
    }
    return a;
}

/* op2: a - b. The quiz models it as op1(a, op1(~b, 1)), since ~b + 1 = -b in
 * two's complement; that model needs up to 32 passes for each op1, beyond the
 * contract's budget, so the function is the subtraction itself.
 */
uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

/* op3: floor((a + b) / 2) without overflow (the quiz's code). With a = 2a' +
 * a0 and b = 2b' + b0, the floor of the half sum is a' + b' + (a0 & b0).
 */
uint32_t op3(uint32_t a, uint32_t b)
{
    return (a >> 1) + (b >> 1) + (a & b & 1);
}

/* q_mul: the quiz computes ((int64_t) a * b + (1 << (Q - 1))) >> Q, but a
 * 64-bit multiply makes GCC call __muldi3, which the runtime does not supply.
 * The product is built from four 16 x 16-bit partial products instead (each a
 * 32-bit multiply, __mulsi3 on RV32I), as an unsigned 64-bit pair (hi, lo),
 * then corrected for the signs: for two's-complement operands the signed
 * product's high word is the unsigned one minus b when a < 0 and minus a when
 * b < 0 (modulo 2^32). Adding 2^19 and shifting right by 20 keeps the low 32
 * bits of the rounded result: (hi << 12) | (lo >> 20) after the carry.
 */
int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a, ub = (uint32_t) b;
    uint32_t al = ua & 0xFFFFu, ah = ua >> 16;
    uint32_t bl = ub & 0xFFFFu, bh = ub >> 16;

    uint32_t ll = al * bl, lh = al * bh, hl = ah * bl, hh = ah * bh;
    uint32_t mid = (ll >> 16) + (lh & 0xFFFFu) + (hl & 0xFFFFu);
    uint32_t lo = (ll & 0xFFFFu) | (mid << 16);
    uint32_t hi = hh + (lh >> 16) + (hl >> 16) + (mid >> 16);
    if (a < 0)
        hi -= ub;
    if (b < 0)
        hi -= ua;

    /* Adding 2^19 carries out of lo exactly when lo >> 19 is 0x1FFF. */
    uint32_t rlo = lo + (1u << (Q - 1));
    hi += ((lo >> (Q - 1)) + 1) >> (33 - Q);
    return (int32_t) ((hi << (32 - Q)) | (rlo >> Q));
}
