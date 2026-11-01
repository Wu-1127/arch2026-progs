# Quiz 3 Problem C: op1, op2, op3 and the Q11.20 multiply, hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)
# uint32_t op2_asm(uint32_t a, uint32_t b)
# uint32_t op3_asm(uint32_t a, uint32_t b)
# int32_t  q_mul_asm(int32_t a, int32_t b)
#
# RV32I only: no mul, div, rem. Tests: tests/tfixed.c.

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

# op1_asm: the quiz loop tested at the bottom, with the carry computed
# straight into b: 5 instructions per pass (GCC -O2 needs 6).
    .globl  op1_asm
    .type   op1_asm, @function
op1_asm:
    addi    t1, x0, 0
    beq     a1, x0, o1_done
o1_loop:
    and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    addi    t1, t1, 1
    bne     a1, x0, o1_loop
o1_done:
    sw      t1, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

# op2_asm: a - b. The bitwise model op1(a, op1(~b, 1)) is a loop of up to 32
# passes per op1; the contract asks for the subtraction itself.
    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

# op3_asm: a + b = 2 (a & b) + (a ^ b) (the carries plus the carry-less sum,
# the split op1 uses), so floor((a + b) / 2) = (a & b) + ((a ^ b) >> 1).
# Neither term overflows: 4 instructions against the quiz's 6.
    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret
    .size   op3_asm, .-op3_asm

# q_mul_asm: ((int64) a * b + 2^19) >> 20, low 32 bits, without a multiply.
#   - Sign and magnitude: |a| * |b| with the smaller magnitude as multiplier.
#   - The multiplier's trailing zeros are stripped first (CTZ): Q20 constants
#     such as 1.5 = 0x180000 end in long runs of zeros, and until the first
#     set bit the accumulator is still zero.
#   - The accumulator shifts right, as in a hardware multiplier: each step adds
#     the multiplicand x into the high word (it stays below x <= 2^31, so the
#     add never carries out) and shifts the pair right; when the multiplier
#     runs out after k steps, one shift by 32 - k aligns the product.
#   - For a negative product -M, floor((-M + 2^19) / 2^20) equals
#     -floor((M + 2^19 - 1) / 2^20): round the magnitude with 2^19 - s and
#     negate the 32-bit result, instead of negating the 64-bit product.
    .globl  q_mul_asm
    .type   q_mul_asm, @function
q_mul_asm:
    ABS_ORDER t0
    addi    t1, x0, 0
    addi    t2, x0, 0
    addi    t5, x0, 32
    beq     a1, x0, qm_round
    CTZ     t3, a1, t0            # a1 >>= z, t3 = z
    sub     t5, t5, t3
qm_loop:
    andi    t0, a1, 1
    beq     t0, x0, qm_shift
    add     t2, t2, a0
qm_shift:
    slli    t0, t2, 31
    srli    t1, t1, 1
    or      t1, t1, t0
    srli    t2, t2, 1
    srli    a1, a1, 1
    addi    t5, t5, -1
    bne     a1, x0, qm_loop
    beq     t5, x0, qm_round
    srl     t1, t1, t5
    sub     t0, x0, t5
    sll     t0, t2, t0
    or      t1, t1, t0
    srl     t2, t2, t5
qm_round:
    srli    t3, a2, 31
    lui     t0, 0x80
    sub     t0, t0, t3
    add     t1, t1, t0
    sltu    t0, t1, t0
    add     t2, t2, t0
    slli    t2, t2, 12
    srli    t1, t1, 20
    or      a0, t2, t1
    bge     a2, x0, qm_ret
    sub     a0, x0, a0
qm_ret:
    ret
    .size   q_mul_asm, .-q_mul_asm
