# Steps of the binary GCD, measured by mytests/steps.c; not graded.
# gcd_quiz is the Quiz 2 routine (proc_a) unchanged; gcd_v1..gcd_v7 change
# one thing each, as listed below. The submitted src/gcd/gcd.S is gcd_v6.

# Quiz 2, Problem A: binary GCD without a divider.
#
# gcd_quiz is the quiz routine with its blanks filled, unchanged apart from
# the .globl line: it is the baseline every optimization is measured
# against. The quiz's main lives in gcd_main.S.

    .text

# unsigned gcd_quiz(unsigned a0, unsigned a1)
    .globl  gcd_quiz
gcd_quiz:
    beq     a0, x0, qz_alt       # a0 is zero: the answer is in a1
    beq     a1, x0, qz_end        # a1 is zero: a0 already holds it
    addi    t0, x0, 0       # count of shared twos, starting here
qz_both:
    or t1, a0, a1            # combine a and b
    andi    t1, t1, 1       # keep the parity bit
    bne     t1, x0, qz_left
    srli    a0, a0, 1             # a /= 2, with no sign to preserve
    srli    a1, a1, 1             # b /= 2
    addi    t0, t0, 1       # one more shared two
    jal     x0, qz_both           # back to the head of this loop
qz_left:
    andi    t1, a0, 1
    bne     t1, x0, qz_right     # a is odd now, go work on b
    srli    a0, a0, 1
    jal     x0, qz_left
qz_right:
    andi    t1, a1, 1
    bne     t1, x0, qz_order
    srli    a1, a1, 1
    jal     x0, qz_right
qz_order:
    bgeu    a1, a0, qz_step       # skip the swap while b >= a holds
    addi    t2, a0, 0             # swap a and b
    addi    a0, a1, 0
    addi    a1, t2, 0
qz_step:
    sub     a1, a1, a0            # b -= a, and b stays even
    bne a1, x0, qz_right     # b is not zero yet
    sll a0, a0, t0            # put the shared twos back
    jalr    x0, ra, 0
qz_alt:
    addi    a0, a1, 0
qz_end:
    jalr    x0, ra, 0

# Binary GCD, hand-optimized RV32I variants of the quiz's proc_a.
#
# Each variant adds one change to the previous one, so the benchmark
# table shows the effect of every change on its own:
#
#   gcd_v1  bottom-tested strip loops: shift first, test after
#   gcd_v2  v1 + binary-search ctz for the one-time strips (shared twos,
#           twos of a), so their cost no longer grows with the count
#   gcd_v3  v2 + 16-entry table for the strip inside the main loop
#   gcd_v4  v3 + branchless order/subtract with sltu
#   gcd_v5  v2 + two mirrored copies of the main loop instead of a swap
#   gcd_v6  v5 with a bit-k mask in place of counting the shared twos
#   gcd_v7  size first: the quiz's loop shape with v6's mask
#
# All variants: uint32_t f(uint32_t a /* a0 */, uint32_t b /* a1 */),
# leaf functions using t-registers only.

# CTZ rd, rs, tmp: rd = number of trailing zeros of rs (rs != 0), and
# rs >>= rd. Binary search over the bit position: 16, 8, 4, 2, 1. RV32I
# has no ctz, and a de Bruijn table would need a multiply.
# 11 instructions when rs is odd, 21 at most.
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
tz4:    .byte   4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0

    .text

# ---------------------------------------------------------------------
# v1: the quiz loops test at the top and jump back from the bottom
# (andi, bne, srli, jal per zero bit, plus andi, bne to leave). Here each
# loop shifts first and tests after, which is legal wherever the value is
# known to be even: per zero bit srli, andi, beq, and nothing extra to
# leave. After `b -= a` (odd - odd) b is always even, so the main loop
# enters the strip loop directly instead of testing first.
    .globl  gcd_v1
    .type   gcd_v1, @function
gcd_v1:
    beq     a0, x0, v1_ret_b
    beq     a1, x0, v1_ret
    addi    t0, x0, 0             # shared twos
    or      t1, a0, a1
    andi    t1, t1, 1
    bne     t1, x0, v1_left       # at least one is odd: no shared twos
v1_both:                          # both even
    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    t0, t0, 1
    or      t1, a0, a1
    andi    t1, t1, 1
    beq     t1, x0, v1_both
v1_left:
    andi    t1, a0, 1
    bne     t1, x0, v1_rchk
v1_lloop:                         # a even
    srli    a0, a0, 1
    andi    t1, a0, 1
    beq     t1, x0, v1_lloop
v1_rchk:
    andi    t1, a1, 1
    bne     t1, x0, v1_order
v1_right:                         # b even and nonzero
    srli    a1, a1, 1
    andi    t1, a1, 1
    beq     t1, x0, v1_right
v1_order:
    bgeu    a1, a0, v1_step
    addi    t2, a0, 0
    addi    a0, a1, 0
    addi    a1, t2, 0
v1_step:
    sub     a1, a1, a0            # odd - odd: even
    bne     a1, x0, v1_right      # so strip without testing first
    sll     a0, a0, t0
    ret
v1_ret_b:
    addi    a0, a1, 0
v1_ret:
    ret
    .size   gcd_v1, . - gcd_v1

# ---------------------------------------------------------------------
# v2: the shared twos and the twos of a are stripped once per call; a
# bit loop costs 6 (shared) or 3 (a) instructions per zero bit, so
# 0xF0000000 with 28 shared twos costs ~170. CTZ costs 11 to 21 whatever
# the count. The odd fast path is kept, so odd inputs pay nothing.
    .globl  gcd_v2
    .type   gcd_v2, @function
gcd_v2:
    beq     a0, x0, v2_ret_b
    beq     a1, x0, v2_ret
    addi    t0, x0, 0
    or      t1, a0, a1
    andi    t2, t1, 1
    bne     t2, x0, v2_left
    CTZ     t0, t1, t2            # k = ctz(a | b)
    srl     a0, a0, t0
    srl     a1, a1, t0
v2_left:
    andi    t2, a0, 1
    bne     t2, x0, v2_rchk
    CTZ     t3, a0, t2            # a >>= ctz(a)
v2_rchk:
    andi    t1, a1, 1
    bne     t1, x0, v2_order
v2_right:
    srli    a1, a1, 1
    andi    t1, a1, 1
    beq     t1, x0, v2_right
v2_order:
    bgeu    a1, a0, v2_step
    addi    t2, a0, 0
    addi    a0, a1, 0
    addi    a1, t2, 0
v2_step:
    sub     a1, a1, a0
    bne     a1, x0, v2_right
    sll     a0, a0, t0
    ret
v2_ret_b:
    addi    a0, a1, 0
v2_ret:
    ret
    .size   gcd_v2, . - gcd_v2

# ---------------------------------------------------------------------
# v3: inside the main loop b - a has k >= 1 trailing zeros with
# probability 2^-k, two on average, which the bit loop strips in 3k
# instructions. A table of the trailing zeros of the low nibble does it
# in 5 (andi, beq, add, lbu, srl) whenever k < 4, which is 15 times in 16.
    .globl  gcd_v3
    .type   gcd_v3, @function
gcd_v3:
    beq     a0, x0, v3_ret_b
    beq     a1, x0, v3_ret
    addi    t0, x0, 0
    or      t1, a0, a1
    andi    t2, t1, 1
    bne     t2, x0, v3_left
    CTZ     t0, t1, t2
    srl     a0, a0, t0
    srl     a1, a1, t0
v3_left:
    andi    t2, a0, 1
    bne     t2, x0, v3_rchk
    CTZ     t3, a0, t2
v3_rchk:
    la      t5, tz4               # hoisted out of the loop
    andi    t1, a1, 1
    bne     t1, x0, v3_order
v3_right:                         # b even and nonzero
    andi    t1, a1, 15
    beq     t1, x0, v3_by4
    add     t1, t1, t5
    lbu     t1, 0(t1)
    srl     a1, a1, t1
v3_order:
    bgeu    a1, a0, v3_step
    addi    t2, a0, 0
    addi    a0, a1, 0
    addi    a1, t2, 0
v3_step:
    sub     a1, a1, a0
    bne     a1, x0, v3_right
    sll     a0, a0, t0
    ret
v3_by4:                           # low nibble zero: rare, 1 in 16
    srli    a1, a1, 4
    j       v3_right
v3_ret_b:
    addi    a0, a1, 0
v3_ret:
    ret
    .size   gcd_v3, . - gcd_v3

# ---------------------------------------------------------------------
# v4: replace the bgeu swap and the subtract with a branchless form:
#   m = -(b < a);  d = b - a;  a += d & m  (= min);  b = (d ^ m) - m (= |d|)
# Seven instructions every iteration against two (no swap) or five
# (swap) for the branch. On a pipelined core the branch can mispredict;
# rv32emu counts instructions only, so this measures the instruction
# cost of removing it.
    .globl  gcd_v4
    .type   gcd_v4, @function
gcd_v4:
    beq     a0, x0, v4_ret_b
    beq     a1, x0, v4_ret
    addi    t0, x0, 0
    or      t1, a0, a1
    andi    t2, t1, 1
    bne     t2, x0, v4_left
    CTZ     t0, t1, t2
    srl     a0, a0, t0
    srl     a1, a1, t0
v4_left:
    andi    t2, a0, 1
    bne     t2, x0, v4_rchk
    CTZ     t3, a0, t2
v4_rchk:
    la      t5, tz4
    andi    t1, a1, 1
    bne     t1, x0, v4_order
v4_right:
    andi    t1, a1, 15
    beq     t1, x0, v4_by4
    add     t1, t1, t5
    lbu     t1, 0(t1)
    srl     a1, a1, t1
v4_order:
    sltu    t2, a1, a0            # b < a
    sub     t3, a1, a0            # d = b - a
    sub     t2, x0, t2            # m = 0 or all ones
    and     t4, t3, t2
    add     a0, a0, t4            # a = min(a, b)
    xor     t3, t3, t2
    sub     a1, t3, t2            # b = |b - a|
    bne     a1, x0, v4_right
    sll     a0, a0, t0
    ret
v4_by4:
    srli    a1, a1, 4
    j       v4_right
v4_ret_b:
    addi    a0, a1, 0
v4_ret:
    ret
    .size   gcd_v4, . - gcd_v4

# ---------------------------------------------------------------------
# v5: v2 without the swap. The loop is written twice with the roles of
# a0 and a1 exchanged (LA reduces a1, LB reduces a0). When the operand
# being reduced drops below the other, the subtraction goes the other way
# and control moves to the mirrored copy, so the three moves of the swap
# disappear: a swap step costs bltu + sub instead of bgeu + 3 mv + sub.
# The price is a second copy of the loop (code size).
    .globl  gcd_v5
    .type   gcd_v5, @function
gcd_v5:
    beq     a0, x0, v5_ret_b
    beq     a1, x0, v5_ret
    addi    t0, x0, 0
    or      t1, a0, a1
    andi    t2, t1, 1
    bne     t2, x0, v5_left
    CTZ     t0, t1, t2            # k = ctz(a | b)
    srl     a0, a0, t0
    srl     a1, a1, t0
v5_left:
    andi    t2, a0, 1
    bne     t2, x0, v5_rchk
    CTZ     t3, a0, t2            # a >>= ctz(a)
v5_rchk:
    andi    t1, a1, 1
    bne     t1, x0, v5_acmp
v5_A:                             # a0 odd, a1 even and nonzero
    srli    a1, a1, 1
    andi    t1, a1, 1
    beq     t1, x0, v5_A
v5_acmp:                          # both odd
    bltu    a1, a0, v5_a2b
    sub     a1, a1, a0            # a1 >= a0: reduce a1
    bne     a1, x0, v5_A
    sll     a0, a0, t0            # gcd in a0
    ret
v5_a2b:
    sub     a0, a0, a1            # a1 < a0: reduce a0 instead
v5_B:                             # a1 odd, a0 even and nonzero
    srli    a0, a0, 1
    andi    t1, a0, 1
    beq     t1, x0, v5_B
    bltu    a0, a1, v5_b2a
    sub     a0, a0, a1            # a0 >= a1: reduce a0
    bne     a0, x0, v5_B
    sll     a0, a1, t0            # gcd in a1
    ret
v5_b2a:
    sub     a1, a1, a0            # a0 < a1: back to reducing a1
    j       v5_A
v5_ret_b:
    addi    a0, a1, 0
v5_ret:
    ret
    .size   gcd_v5, . - gcd_v5

# ---------------------------------------------------------------------
# v6: v5 without counting the shared twos. m = (a | b) & -(a | b) is the
# lowest set bit of a | b, i.e. 2^k for the k shared twos. Testing bit k
# (x & m) in place of bit 0 makes every strip stop at 2^k * odd, so a and
# b keep the common 2^k throughout, b - a stays a multiple of 2^(k+1),
# and the loop ends with a0 = 2^k * gcd(odd parts) = gcd(a, b) directly:
# no pa_both loop, no counter, no final sll. Three instructions replace
# a cost that grew with k (0xF0000000, 0x30000000: 28 shared twos).
    .globl  gcd_v6
    .type   gcd_v6, @function
gcd_v6:
    beq     a0, x0, v6_ret_b
    beq     a1, x0, v6_ret
    or      t0, a0, a1
    sub     t1, x0, t0
    and     t0, t0, t1            # m = 2^k
    and     t1, a0, t0
    bne     t1, x0, v6_rchk
v6_L:                             # a0 / 2^k even
    srli    a0, a0, 1
    and     t1, a0, t0
    beq     t1, x0, v6_L
v6_rchk:
    and     t1, a1, t0
    bne     t1, x0, v6_acmp
v6_A:                             # a1 / 2^k even and nonzero
    srli    a1, a1, 1
    and     t1, a1, t0
    beq     t1, x0, v6_A
v6_acmp:
    bltu    a1, a0, v6_a2b
    sub     a1, a1, a0
    bne     a1, x0, v6_A
    ret                           # gcd in a0
v6_a2b:
    sub     a0, a0, a1
v6_B:                             # a0 / 2^k even and nonzero
    srli    a0, a0, 1
    and     t1, a0, t0
    beq     t1, x0, v6_B
    bltu    a0, a1, v6_b2a
    sub     a0, a0, a1
    bne     a0, x0, v6_B
    addi    a0, a1, 0             # gcd in a1
    ret
v6_b2a:
    sub     a1, a1, a0
    j       v6_A
v6_ret_b:
    addi    a0, a1, 0
v6_ret:
    ret
    .size   gcd_v6, . - gcd_v6

# ---------------------------------------------------------------------
# v7: size first. The quiz's single loop and swap with the bit-k mask of
# v6: 22 instructions (88 bytes) against the quiz's 28, and no shared-two
# loop. Loops are top-tested, which takes fewer instructions to write.
    .globl  gcd_v7
    .type   gcd_v7, @function
gcd_v7:
    beq     a0, x0, v7_ret_b
    beq     a1, x0, v7_ret
    or      t0, a0, a1
    sub     t1, x0, t0
    and     t0, t0, t1            # m = 2^k
v7_left:
    and     t1, a0, t0
    bne     t1, x0, v7_right
    srli    a0, a0, 1
    j       v7_left
v7_right:
    and     t1, a1, t0
    bne     t1, x0, v7_order
    srli    a1, a1, 1
    j       v7_right
v7_order:
    bgeu    a1, a0, v7_step
    addi    t1, a0, 0
    addi    a0, a1, 0
    addi    a1, t1, 0
v7_step:
    sub     a1, a1, a0
    bne     a1, x0, v7_right
v7_ret:
    ret
v7_ret_b:
    addi    a0, a1, 0
    ret
    .size   gcd_v7, . - gcd_v7

# ---------------------------------------------------------------------
# v8: v5 with v3's table strip in both mirrored loops. After a
# subtraction the reduced operand is even and nonzero; the table of the
# trailing zeros of its low nibble strips 1 to 3 zeros in 5 instructions
# (andi, beq, add, lbu, srl), where the bit loop costs 3 per zero.
    .globl  gcd_v8
    .type   gcd_v8, @function
gcd_v8:
    beq     a0, x0, v8_ret_b
    beq     a1, x0, v8_ret
    addi    t0, x0, 0
    or      t1, a0, a1
    andi    t2, t1, 1
    bne     t2, x0, v8_left
    CTZ     t0, t1, t2            # k = ctz(a | b)
    srl     a0, a0, t0
    srl     a1, a1, t0
v8_left:
    andi    t2, a0, 1
    bne     t2, x0, v8_rchk
    CTZ     t3, a0, t2            # a >>= ctz(a)
v8_rchk:
    la      t5, tz4
    andi    t1, a1, 1
    bne     t1, x0, v8_acmp
v8_A:                             # a0 odd, a1 even and nonzero
    andi    t1, a1, 15
    beq     t1, x0, v8_A4
    add     t1, t1, t5
    lbu     t1, 0(t1)
    srl     a1, a1, t1
v8_acmp:                          # both odd
    bltu    a1, a0, v8_a2b
    sub     a1, a1, a0            # a1 >= a0: reduce a1
    bne     a1, x0, v8_A
    sll     a0, a0, t0            # gcd in a0
    ret
v8_a2b:
    sub     a0, a0, a1            # a1 < a0: reduce a0 instead
v8_B:                             # a1 odd, a0 even and nonzero
    andi    t1, a0, 15
    beq     t1, x0, v8_B4
    add     t1, t1, t5
    lbu     t1, 0(t1)
    srl     a0, a0, t1
    bltu    a0, a1, v8_b2a
    sub     a0, a0, a1            # a0 >= a1: reduce a0
    bne     a0, x0, v8_B
    sll     a0, a1, t0            # gcd in a1
    ret
v8_b2a:
    sub     a1, a1, a0            # a0 < a1: back to reducing a1
    j       v8_A
v8_A4:                            # low nibble zero: 1 in 16
    srli    a1, a1, 4
    j       v8_A
v8_B4:
    srli    a0, a0, 4
    j       v8_B
v8_ret_b:
    addi    a0, a1, 0
v8_ret:
    ret
    .size   gcd_v8, . - gcd_v8
