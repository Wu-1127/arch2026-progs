# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# Two ideas beyond the textbook loop:
#   - m = (a | b) & -(a | b) is 2^k for the k factors of two that a and b
#     share. Testing bit k (x & m) instead of bit 0 makes every strip stop at
#     2^k * odd, so both operands keep the common 2^k and the loop ends with
#     the answer itself: no loop to count the shared twos, no counter, no
#     final shift.
#   - The main loop exists twice with the roles of a0 and a1 exchanged. When
#     the operand being reduced drops below the other, the subtraction goes
#     the other way and control moves to the mirrored copy, so a swap costs
#     bltu + sub instead of three moves.
# Every strip loop shifts first and tests after, which is legal because the
# value is known to be even there (after b - a, odd - odd is even).
#
# RV32I only: no mul, div, rem. Tests: tests/tgcd.c.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beq     a0, x0, ret_b         # gcd(0, b) = b
    beq     a1, x0, ret_a         # gcd(a, 0) = a
    or      t0, a0, a1
    sub     t1, x0, t0
    and     t0, t0, t1            # m = 2^k, the lowest set bit of a | b
    and     t1, a0, t0
    bne     t1, x0, rchk
strip_a:                          # a0 / 2^k even
    srli    a0, a0, 1
    and     t1, a0, t0
    beq     t1, x0, strip_a
rchk:
    and     t1, a1, t0
    bne     t1, x0, cmp_a
loop_a:                           # reduce a1: a1 / 2^k even and nonzero
    srli    a1, a1, 1
    and     t1, a1, t0
    beq     t1, x0, loop_a
cmp_a:
    bltu    a1, a0, a_to_b
    sub     a1, a1, a0            # a1 >= a0
    bne     a1, x0, loop_a
ret_a:
    ret                           # gcd in a0
a_to_b:
    sub     a0, a0, a1            # a1 < a0: reduce a0 instead
loop_b:                           # reduce a0: a0 / 2^k even and nonzero
    srli    a0, a0, 1
    and     t1, a0, t0
    beq     t1, x0, loop_b
    bltu    a0, a1, b_to_a
    sub     a0, a0, a1            # a0 >= a1
    bne     a0, x0, loop_b
ret_b:
    mv      a0, a1                # gcd in a1
    ret
b_to_a:
    sub     a1, a1, a0            # a0 < a1: back to reducing a1
    j       loop_a
    .size   gcd_u32_asm, .-gcd_u32_asm
