#include "bf16.h"

/* BFloat16 (Quiz 1 Problem B). The arithmetic is the quiz's code, verbatim:
 * the 2026 problem gives fragments (blanks B05 to B33) of the implementation
 * whose full source is the 2025 Quiz 1 Problem C solution. The only change is
 * at the edges: the contract passes bit patterns (uint16_t, and uint32_t for
 * a binary32), so bf16_from_f32 takes the binary32 bits instead of a float
 * copied with memcpy.
 */
typedef struct {
    uint16_t bits;
} bf16_t;

#define BF16_SIGN_MASK 0x8000U
#define BF16_EXP_MASK 0x7F80U
#define BF16_MANT_MASK 0x007FU
#define BF16_EXP_BIAS 127

#define BF16_NAN() ((bf16_t) {.bits = 0x7FC0})
#define BF16_ZERO() ((bf16_t) {.bits = 0x0000})

/* f32_to_bf16 of the quiz without the memcpy: Inf and NaN keep their top
 * half; otherwise round to nearest, ties to even, by adding 0x7FFF plus the
 * lowest kept bit.
 */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    if (((f32bits >> 23) & 0xFF) == 0xFF)
        return (uint16_t) ((f32bits >> 16) & 0xFFFF);
    f32bits += ((f32bits >> 16) & 1) + 0x7FFF;
    return (uint16_t) (f32bits >> 16);
}

static bf16_t mul(bf16_t a, bf16_t b)
{
    uint16_t sign_a = (a.bits >> 15) & 1;
    uint16_t sign_b = (b.bits >> 15) & 1;
    int16_t exp_a = ((a.bits >> 7) & 0xFF);
    int16_t exp_b = ((b.bits >> 7) & 0xFF);
    uint16_t mant_a = a.bits & 0x7F;
    uint16_t mant_b = b.bits & 0x7F;

    uint16_t result_sign = sign_a ^ sign_b;

    if (exp_a == 0xFF) {
        if (mant_a)
            return a;
        if (!exp_b && !mant_b)
            return BF16_NAN();
        return (bf16_t) {.bits = (result_sign << 15) | 0x7F80};
    }
    if (exp_b == 0xFF) {
        if (mant_b)
            return b;
        if (!exp_a && !mant_a)
            return BF16_NAN();
        return (bf16_t) {.bits = (result_sign << 15) | 0x7F80};
    }
    if ((!exp_a && !mant_a) || (!exp_b && !mant_b))
        return (bf16_t) {.bits = result_sign << 15};

    int16_t exp_adjust = 0;
    if (!exp_a) {
        while (!(mant_a & 0x80)) {
            mant_a <<= 1;
            exp_adjust--;
        }
        exp_a = 1;
    } else
        mant_a |= 0x80;
    if (!exp_b) {
        while (!(mant_b & 0x80)) {
            mant_b <<= 1;
            exp_adjust--;
        }
        exp_b = 1;
    } else
        mant_b |= 0x80;

    uint32_t result_mant = (uint32_t) mant_a * mant_b;

    int32_t result_exp = (int32_t) exp_a + exp_b - BF16_EXP_BIAS + exp_adjust;

    if (result_mant & 0x8000) {
        result_mant = (result_mant >> 8) & 0x7F;
        result_exp++;
    } else
        result_mant = (result_mant >> 7) & 0x7F;

    if (result_exp >= 0xFF)
        return (bf16_t) {.bits = (result_sign << 15) | 0x7F80};
    if (result_exp <= 0) {
        if (result_exp < -6)
            return (bf16_t) {.bits = result_sign << 15};
        result_mant >>= (1 - result_exp);
        result_exp = 0;
    }

    return (bf16_t) {.bits = (result_sign << 15) | ((result_exp & 0xFF) << 7) |
                             (result_mant & 0x7F)};
}

static bf16_t sqrt_(bf16_t a)
{
    uint16_t sign = (a.bits >> 15) & 1;
    int16_t exp = ((a.bits >> 7) & 0xFF);
    uint16_t mant = a.bits & 0x7F;

    /* Handle special cases */
    if (exp == 0xFF) {
        if (mant)
            return a; /* NaN propagation */
        if (sign)
            return BF16_NAN(); /* sqrt(-Inf) = NaN */
        return a;              /* sqrt(+Inf) = +Inf */
    }

    /* sqrt(0) = 0 (handle both +0 and -0) */
    if (!exp && !mant)
        return BF16_ZERO();

    /* sqrt of negative number is NaN */
    if (sign)
        return BF16_NAN();

    /* Flush denormals to zero */
    if (!exp)
        return BF16_ZERO();

    /* Direct bit manipulation square root algorithm */
    /* For sqrt: new_exp = (old_exp - bias) / 2 + bias */
    int32_t e = exp - BF16_EXP_BIAS;
    int32_t new_exp;

    /* Get full mantissa with implicit 1 */
    uint32_t m = 0x80 | mant; /* Range [128, 256) representing [1.0, 2.0) */

    /* Adjust for odd exponents: sqrt(2^odd * m) = 2^((odd-1)/2) * sqrt(2*m) */
    if (e & 1) {
        m <<= 1; /* Double mantissa for odd exponent */
        new_exp = ((e - 1) >> 1) + BF16_EXP_BIAS;
    } else {
        new_exp = (e >> 1) + BF16_EXP_BIAS;
    }

    /* Now m is in range [128, 256) or [256, 512) if exponent was odd */
    /* Binary search for integer square root */
    /* We want result where result^2 = m * 128 (since 128 represents 1.0) */

    uint32_t low = 90;     /* Min sqrt (roughly sqrt(128)) */
    uint32_t high = 256;   /* Max sqrt (roughly sqrt(512)) */
    uint32_t result = 128; /* Default */

    /* Binary search for square root of m */
    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        uint32_t sq = (mid * mid) / 128; /* Square and scale */

        if (sq <= m) {
            result = mid; /* This could be our answer */
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    /* result now contains sqrt(m) * sqrt(128) / sqrt(128) = sqrt(m) */
    /* But we need to adjust the scale */
    /* Since m is scaled where 128=1.0, result should also be scaled same way */

    /* Normalize to ensure result is in [128, 256) */
    if (result >= 256) {
        result >>= 1;
        new_exp++;
    } else if (result < 128) {
        while (result < 128 && new_exp > 1) {
            result <<= 1;
            new_exp--;
        }
    }

    /* Extract 7-bit mantissa (remove implicit 1) */
    uint16_t new_mant = result & 0x7F;

    /* Check for overflow/underflow */
    if (new_exp >= 0xFF)
        return (bf16_t) {.bits = 0x7F80}; /* +Inf */
    if (new_exp <= 0)
        return BF16_ZERO();

    return (bf16_t) {.bits = ((new_exp & 0xFF) << 7) | new_mant};
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    bf16_t x = {.bits = a}, y = {.bits = b};
    return mul(x, y).bits;
}

uint16_t bf16_sqrt(uint16_t a)
{
    bf16_t x = {.bits = a};
    return sqrt_(x).bits;
}
