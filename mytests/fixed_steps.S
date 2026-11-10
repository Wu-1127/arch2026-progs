# Quiz 3, Problem C: hand-optimized RV32I versions.
#
#   op3_v1    floor((a + b) / 2) as (a & b) + ((a ^ b) >> 1): 5 instructions
#   q_mul_v1  q_mul_v0 + the smaller magnitude as multiplier, early exit
#   q_mul_v2  v1 + a right-shifting accumulator: no addend pair, no carry
#   q_mul_v3  v2 + sign-aware rounding constant instead of a 64-bit negate
#   q_mul_v4  v3 + strip the multiplier's trailing zeros before the loop
#   q_mul_v5  v4's strip and rounding on v1's left-shifting loop
#   op1_v1    the op1 loop tested at the bottom: 5 instructions per pass
#   op2_v1    -b with one sub, then a 4-instruction-per-pass loop
#   q_mul_1p5 q_mul specialized for the constant 1.5: 4 instructions
#
# op1 and op2 are bitwise models of add and sub: the real optimization is
# to use add and sub, one instruction each. op1_v1/op2_v1 only show how
# far the models themselves can be tightened.

# CTZ rd, rs, tmp: rd = trailing zeros of rs (rs != 0), and rs >>= rd.
# Binary search over the bit position (16, 8, 4, 2, 1): RV32I has no
# ctz, and a de Bruijn table would need a multiply. 11 to 21 instructions.
.macro CTZ rd, rs, tmp
    addi    \rd, x0, 0
    slli    \tmp, \rs, 16
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

# ABS_ORDER: a0 = |a0|, a1 = |a1| (as unsigned, so INT32_MIN gives 2^31), and
# a2 bit 31 = sign of the product. Then a1 = the smaller magnitude.
.macro ABS_ORDER tmp
    xor     a2, a0, a1
    srai    \tmp, a0, 31
    xor     a0, a0, \tmp
    sub     a0, a0, \tmp
    srai    \tmp, a1, 31
    xor     a1, a1, \tmp
    sub     a1, a1, \tmp
    bgeu    a0, a1, 86f           # keep the smaller one in a1
    addi    \tmp, a0, 0
    addi    a0, a1, 0
    addi    a1, \tmp, 0
86:
.endm

    .text

# ---------------------------------------------------------------------
# op3_v1: a + b = 2 (a & b) + (a ^ b) (the carries plus the carry-less
# sum, the same split op1 uses), so floor((a + b) / 2) = (a & b) +
# ((a ^ b) >> 1). Neither term can overflow and the sum is < 2^32.
    .globl  op3_v1
    .type   op3_v1, @function
op3_v1:
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret
    .size   op3_v1, . - op3_v1

# ---------------------------------------------------------------------
# q_mul_v1: v0 runs all 32 iterations whatever |b| is. Here the smaller
# magnitude is the multiplier and the loop stops when no set bit is left,
# so the count is the bit length of min(|a|, |b|): 21 for 1.0 in Q20.
    .globl  q_mul_v1
    .type   q_mul_v1, @function
q_mul_v1:
    ABS_ORDER t0
    addi    t1, x0, 0             # product low
    addi    t2, x0, 0             # product high
    addi    t3, a0, 0             # addend low
    addi    t4, x0, 0             # addend high
    beq     a1, x0, v1_sign
v1_loop:
    andi    t0, a1, 1
    beq     t0, x0, v1_shift
    add     t1, t1, t3
    sltu    t0, t1, t3
    add     t2, t2, t4
    add     t2, t2, t0
v1_shift:
    srli    t0, t3, 31
    slli    t4, t4, 1
    or      t4, t4, t0
    slli    t3, t3, 1
    srli    a1, a1, 1
    bne     a1, x0, v1_loop
v1_sign:
    bge     a2, x0, v1_round
    sltu    t0, x0, t1
    sub     t1, x0, t1
    sub     t2, x0, t2
    sub     t2, t2, t0
v1_round:
    lui     t0, 0x80              # 2^19
    add     t1, t1, t0
    sltu    t0, t1, t0
    add     t2, t2, t0
    slli    t2, t2, 12
    srli    t1, t1, 20
    or      a0, t2, t1
    ret
    .size   q_mul_v1, . - q_mul_v1

# ---------------------------------------------------------------------
# q_mul_v2: shift the accumulator right instead of the addend left, as a
# hardware multiplier does. Each step adds x = max(|a|, |b|) into the
# high word and shifts the pair right by one. After k steps the pair
# holds P_k * 2^(32 - k), where P_k < x * 2^k is the partial product, so
# the high word stays below x <= 2^31 and adding x never carries out:
# no sltu, no addend pair to shift. When the multiplier runs out after
# k < 32 steps, one bulk shift by 32 - k lines the product up.
    .globl  q_mul_v2
    .type   q_mul_v2, @function
q_mul_v2:
    ABS_ORDER t0
    addi    t1, x0, 0             # accumulator low
    addi    t2, x0, 0             # accumulator high
    addi    t5, x0, 32            # shifts still owed
    beq     a1, x0, v2_sign
v2_loop:
    andi    t0, a1, 1
    beq     t0, x0, v2_shift
    add     t2, t2, a0
v2_shift:
    slli    t0, t2, 31            # pair >>= 1
    srli    t1, t1, 1
    or      t1, t1, t0
    srli    t2, t2, 1
    srli    a1, a1, 1
    addi    t5, t5, -1
    bne     a1, x0, v2_loop
    beq     t5, x0, v2_sign
    srl     t1, t1, t5            # pair >>= t5 (1..31)
    sub     t0, x0, t5            # 32 - t5 (sll uses the low 5 bits)
    sll     t0, t2, t0
    or      t1, t1, t0
    srl     t2, t2, t5
v2_sign:
    bge     a2, x0, v2_round
    sltu    t0, x0, t1
    sub     t1, x0, t1
    sub     t2, x0, t2
    sub     t2, t2, t0
v2_round:
    lui     t0, 0x80
    add     t1, t1, t0
    sltu    t0, t1, t0
    add     t2, t2, t0
    slli    t2, t2, 12
    srli    t1, t1, 20
    or      a0, t2, t1
    ret
    .size   q_mul_v2, . - q_mul_v2

# ---------------------------------------------------------------------
# q_mul_v3: the 64-bit negate before rounding goes. For a product -M
# with M >= 0, floor((-M + 2^19) / 2^20) = -floor((M + 2^19 - 1) / 2^20),
# so round the magnitude with 2^19 - s (s = 1 when negative) and negate
# the 32-bit result instead. Ties still go toward +infinity: 1.5 -> 2,
# -1.5 -> -1, as in the C code.
    .globl  q_mul_v3
    .type   q_mul_v3, @function
q_mul_v3:
    ABS_ORDER t0
    addi    t1, x0, 0
    addi    t2, x0, 0
    addi    t5, x0, 32
    beq     a1, x0, v3_round
v3_loop:
    andi    t0, a1, 1
    beq     t0, x0, v3_shift
    add     t2, t2, a0
v3_shift:
    slli    t0, t2, 31
    srli    t1, t1, 1
    or      t1, t1, t0
    srli    t2, t2, 1
    srli    a1, a1, 1
    addi    t5, t5, -1
    bne     a1, x0, v3_loop
    beq     t5, x0, v3_round
    srl     t1, t1, t5
    sub     t0, x0, t5
    sll     t0, t2, t0
    or      t1, t1, t0
    srl     t2, t2, t5
v3_round:
    srli    t3, a2, 31            # s
    lui     t0, 0x80
    sub     t0, t0, t3            # 2^19 - s
    add     t1, t1, t0
    sltu    t0, t1, t0
    add     t2, t2, t0
    slli    t2, t2, 12
    srli    t1, t1, 20
    or      a0, t2, t1
    bge     a2, x0, v3_ret
    sub     a0, x0, a0
v3_ret:
    ret
    .size   q_mul_v3, . - q_mul_v3

# ---------------------------------------------------------------------
# q_mul_v4: Q20 constants such as 0.5 (2^19), 1.5 (0x180000) or 2.0
# (2^21) end in long runs of zeros, and each zero costs the loop a full
# step (8 instructions). Before the first set bit the accumulator is
# still zero, so those steps only need the counter: CTZ strips them in
# 11 to 21 instructions and subtracts their count from the shifts owed.
    .globl  q_mul_v4
    .type   q_mul_v4, @function
q_mul_v4:
    ABS_ORDER t0
    addi    t1, x0, 0
    addi    t2, x0, 0
    addi    t5, x0, 32
    beq     a1, x0, v4_round
    CTZ     t3, a1, t0            # a1 >>= z, t3 = z
    sub     t5, t5, t3
v4_loop:
    andi    t0, a1, 1
    beq     t0, x0, v4_shift
    add     t2, t2, a0
v4_shift:
    slli    t0, t2, 31
    srli    t1, t1, 1
    or      t1, t1, t0
    srli    t2, t2, 1
    srli    a1, a1, 1
    addi    t5, t5, -1
    bne     a1, x0, v4_loop
    beq     t5, x0, v4_round
    srl     t1, t1, t5
    sub     t0, x0, t5
    sll     t0, t2, t0
    or      t1, t1, t0
    srl     t2, t2, t5
v4_round:
    srli    t3, a2, 31
    lui     t0, 0x80
    sub     t0, t0, t3
    add     t1, t1, t0
    sltu    t0, t1, t0
    add     t2, t2, t0
    slli    t2, t2, 12
    srli    t1, t1, 20
    or      a0, t2, t1
    bge     a2, x0, v4_ret
    sub     a0, x0, a0
v4_ret:
    ret
    .size   q_mul_v4, . - q_mul_v4

# ---------------------------------------------------------------------
# q_mul_v5: v4's two wins (trailing zeros stripped, sign-aware rounding)
# on v1's loop. The right-shifting accumulator of v2 costs 9
# instructions per zero bit (it needs a step counter for the final
# alignment) against 8 for v1's left-shifting addend, and Q20 operands
# have more zero bits than set ones after the strip. Stripping z zeros
# from the multiplier means starting the addend at x << z, a pair:
# low = x << z, high = (x >> 1) >> (31 - z), which is 0 when z = 0.
    .globl  q_mul_v5
    .type   q_mul_v5, @function
q_mul_v5:
    ABS_ORDER t0
    addi    t1, x0, 0             # product low
    addi    t2, x0, 0             # product high
    beq     a1, x0, v5_round
    CTZ     t3, a1, t0            # a1 >>= z, t3 = z
    sll     t5, a0, t3            # addend low  = x << z
    srli    t4, a0, 1
    addi    t0, x0, 31
    sub     t0, t0, t3
    srl     t4, t4, t0            # addend high = x >> (32 - z)
v5_loop:
    andi    t0, a1, 1
    beq     t0, x0, v5_shift
    add     t1, t1, t5
    sltu    t0, t1, t5
    add     t2, t2, t4
    add     t2, t2, t0
v5_shift:
    srli    t0, t5, 31
    slli    t4, t4, 1
    or      t4, t4, t0
    slli    t5, t5, 1
    srli    a1, a1, 1
    bne     a1, x0, v5_loop
v5_round:
    srli    t3, a2, 31            # s
    lui     t0, 0x80
    sub     t0, t0, t3            # 2^19 - s
    add     t1, t1, t0
    sltu    t0, t1, t0
    add     t2, t2, t0
    slli    t2, t2, 12
    srli    t1, t1, 20
    or      a0, t2, t1
    bge     a2, x0, v5_ret
    sub     a0, x0, a0
v5_ret:
    ret
    .size   q_mul_v5, . - q_mul_v5

# ---------------------------------------------------------------------
# op1_v1: the quiz loop tested at the bottom, with the carry computed
# straight into b: 5 instructions per pass (GCC -O2: 6, op1_asm: 7).
# It is still a model of add; real code uses the add instruction.
    .globl  op1_v1
    .type   op1_v1, @function
op1_v1:
    addi    t1, x0, 0
    beq     a1, x0, o1v_done
o1v_loop:
    and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    addi    t1, t1, 1
    bne     a1, x0, o1v_loop
o1v_done:
    sw      t1, 0(a2)
    ret
    .size   op1_v1, . - op1_v1

# op2_v1: op1(~b, 1) is ~b + 1 = -b in two's complement, one sub instead
# of a loop of up to 32 passes; the second op1 needs no pass count, so
# its loop is 4 instructions per pass. Real code uses sub.
    .globl  op2_v1
    .type   op2_v1, @function
op2_v1:
    sub     a1, x0, a1            # -b
    beq     a1, x0, o2v_done
o2v_loop:
    and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    bne     a1, x0, o2v_loop
o2v_done:
    ret
    .size   op2_v1, . - op2_v1

# ---------------------------------------------------------------------
# q_mul_1p5: q_mul(x, 1.5) for a constant 1.5 = 3 * 2^19 in Q20:
#   floor((3x * 2^19 + 2^19) / 2^20) = floor((3x + 1) / 2)
#                                    = x + floor((x + 1) / 2)
#                                    = x + (x >> 1) + (x & 1)
# with an arithmetic shift. Every step is exact in integers, so the low
# 32 bits match the C code even when the result overflows Q11.20.
    .globl  q_mul_1p5
    .type   q_mul_1p5, @function
q_mul_1p5:
    srai    t0, a0, 1
    andi    t1, a0, 1
    add     a0, a0, t0
    add     a0, a0, t1
    ret
    .size   q_mul_1p5, . - q_mul_1p5
