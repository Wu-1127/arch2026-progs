# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# Three ideas beyond the textbook loop:
#   - The one-time strips (the twos a and b share, then the twos of a) use a
#     binary search over the bit position, 11 to 21 instructions whatever
#     the count, instead of a loop per bit. Odd operands skip both.
#   - Inside the main loop the operand just reduced is even and nonzero.
#     tz4, the trailing zeros of its low nibble, strips 1 to 3 zeros in 5
#     instructions (andi, beq, add, lbu, srl), where a bit loop costs 3 per
#     zero; a zero nibble, 1 case in 16, shifts by 4 and looks again.
#   - The main loop exists twice with the roles of a0 and a1 exchanged. When
#     the operand being reduced drops below the other, the subtraction goes
#     the other way and control moves to the mirrored copy, so a swap costs
#     bltu + sub instead of three moves.
#
# RV32I only: no mul, div, rem. Tests: tests/tgcd.c. The earlier steps are
# in mytests/gcd_steps.S (this is gcd_v8 there).

# CTZ rd, rs, tmp: rd = trailing zeros of rs (rs != 0), and rs >>= rd.
# Binary search over the bit position (16, 8, 4, 2, 1).
.macro CTZ rd, rs, tmp
    addi    \rd, x0, 0
    slli    \tmp, \rs, 16         # low half all zero?
    bne     \tmp, x0, 81f
    srli    \rs, \rs, 16
    addi    \rd, \rd, 16
81: slli    \tmp, \rs, 24
    bne     \tmp, x0, 82f
    srli    \rs, \rs, 8
    addi    \rd, \rd, 8
82: slli    \tmp, \rs, 28
    bne     \tmp, x0, 83f
    srli    \rs, \rs, 4
    addi    \rd, \rd, 4
83: slli    \tmp, \rs, 30
    bne     \tmp, x0, 84f
    srli    \rs, \rs, 2
    addi    \rd, \rd, 2
84: andi    \tmp, \rs, 1
    bne     \tmp, x0, 85f
    srli    \rs, \rs, 1
    addi    \rd, \rd, 1
85:
.endm

    .section .rodata
# tz4[x] = trailing zeros of x for x = 1..15 (x = 0 is never read)
tz4:
    .byte   4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beq     a0, x0, ret_b         # gcd(0, b) = b
    beq     a1, x0, ret_a         # gcd(a, 0) = a
    addi    t0, x0, 0             # k, the shared twos
    or      t1, a0, a1
    andi    t2, t1, 1
    bne     t2, x0, strip_a
    CTZ     t0, t1, t2            # k = ctz(a | b)
    srl     a0, a0, t0
    srl     a1, a1, t0
strip_a:
    andi    t2, a0, 1
    bne     t2, x0, rchk
    CTZ     t3, a0, t2            # a >>= ctz(a): b is odd here
rchk:
    la      t5, tz4
    andi    t1, a1, 1
    bne     t1, x0, cmp_a
loop_a:                           # a0 odd, a1 even and nonzero
    andi    t1, a1, 15
    beq     t1, x0, by4_a
    add     t1, t1, t5
    lbu     t1, 0(t1)
    srl     a1, a1, t1
cmp_a:                            # both odd
    bltu    a1, a0, a_to_b
    sub     a1, a1, a0            # a1 >= a0: reduce a1
    bne     a1, x0, loop_a
    sll     a0, a0, t0            # gcd in a0, times 2^k
ret_a:
    ret
a_to_b:
    sub     a0, a0, a1            # a1 < a0: reduce a0 instead
loop_b:                           # a1 odd, a0 even and nonzero
    andi    t1, a0, 15
    beq     t1, x0, by4_b
    add     t1, t1, t5
    lbu     t1, 0(t1)
    srl     a0, a0, t1
    bltu    a0, a1, b_to_a
    sub     a0, a0, a1            # a0 >= a1: reduce a0
    bne     a0, x0, loop_b
    sll     a0, a1, t0            # gcd in a1, times 2^k
    ret
b_to_a:
    sub     a1, a1, a0            # a0 < a1: back to reducing a1
    j       loop_a
by4_a:                            # low nibble zero: 1 case in 16
    srli    a1, a1, 4
    j       loop_a
by4_b:
    srli    a0, a0, 4
    j       loop_b
ret_b:
    mv      a0, a1
    ret
    .size   gcd_u32_asm, .-gcd_u32_asm
