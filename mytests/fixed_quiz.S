# Quiz 3, Problem C, translated to RV32I as written: the assembly
# baseline. op3_quiz is the quiz's own 7-instruction listing; op1_quiz,
# op2_quiz and q_mul_v0 follow the C code line by line with no tricks.

    .text

# unsigned op1_quiz(unsigned a, unsigned b, int *n)
# a + b by bitwise passes: each pass adds without carries (xor) and moves
# the carries up one position ((a & b) << 1); *n counts the passes.
    .globl  op1_quiz
    .type   op1_quiz, @function
op1_quiz:
    addi    t1, x0, 0             # pass count
o1_loop:
    beq     a1, x0, o1_done
    and     t0, a0, a1
    slli    t0, t0, 1             # c = (a & b) << 1
    xor     a0, a0, a1            # a = a ^ b
    addi    a1, t0, 0             # b = c
    addi    t1, t1, 1
    j       o1_loop
o1_done:
    sw      t1, 0(a2)
    ret
    .size   op1_quiz, . - op1_quiz

# unsigned op2_quiz(unsigned a, unsigned b): op1(a, op1(~b, 1, &n), &n)
    .globl  op2_quiz
    .type   op2_quiz, @function
op2_quiz:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    sw      s0, 8(sp)
    addi    s0, a0, 0             # keep a
    xori    a0, a1, -1            # ~b
    addi    a1, x0, 1
    addi    a2, sp, 4             # &n
    jal     ra, op1_quiz           # -b = ~b + 1
    addi    a1, a0, 0
    addi    a0, s0, 0
    addi    a2, sp, 4
    jal     ra, op1_quiz           # a + (-b)
    lw      ra, 12(sp)
    lw      s0, 8(sp)
    addi    sp, sp, 16
    ret
    .size   op2_quiz, . - op2_quiz

# unsigned op3_quiz(unsigned a, unsigned b): the quiz's listing (blank C07
# is srli: the operands are unsigned, and srai would break a >= 2^31).
    .globl  op3_quiz
    .type   op3_quiz, @function
op3_quiz:
    srli    t1, a0, 1
    and     a0, a0, a1
    srli    a1, a1, 1
    add     t1, t1, a1
    andi    a0, a0, 1
    add     a0, t1, a0
    jalr    x0, ra, 0
    .size   op3_quiz, . - op3_quiz

# qfixed_t q_mul_v0(qfixed_t a, qfixed_t b)
# (int32) (((int64) a * b + 2^19) >> 20), done the plain way:
#   1. take magnitudes and remember the sign of the product,
#   2. 32 x 32 -> 64 shift-and-add over all 32 bits of |b|, with the
#      addend |a| << i kept in a register pair,
#   3. negate the 64-bit product if the sign is negative,
#   4. add 2^19 with carry into the high word,
#   5. the low 32 bits of the 64-bit >> 20: (hi << 12) | (lo >> 20).
    .globl  q_mul_v0
    .type   q_mul_v0, @function
q_mul_v0:
    xor     a2, a0, a1            # bit 31: sign of the product
    srai    t0, a0, 31
    xor     a0, a0, t0
    sub     a0, a0, t0            # |a| (2^31 for INT32_MIN, as unsigned)
    srai    t0, a1, 31
    xor     a1, a1, t0
    sub     a1, a1, t0            # |b|
    addi    t1, x0, 0             # product, low word
    addi    t2, x0, 0             # product, high word
    addi    t3, a0, 0             # addend, low word
    addi    t4, x0, 0             # addend, high word
    addi    t5, x0, 32            # bit counter
v0_loop:
    andi    t0, a1, 1
    beq     t0, x0, v0_shift
    add     t1, t1, t3
    sltu    t0, t1, t3            # carry out of the low word
    add     t2, t2, t4
    add     t2, t2, t0
v0_shift:
    srli    t0, t3, 31            # addend <<= 1 across the pair
    slli    t4, t4, 1
    or      t4, t4, t0
    slli    t3, t3, 1
    srli    a1, a1, 1
    addi    t5, t5, -1
    bne     t5, x0, v0_loop
    bge     a2, x0, v0_round      # product is non-negative
    sltu    t0, x0, t1            # borrow = (lo != 0)
    sub     t1, x0, t1            # 64-bit negate
    sub     t2, x0, t2
    sub     t2, t2, t0
v0_round:
    lui     t0, 0x80              # 2^19
    add     t1, t1, t0
    sltu    t0, t1, t0            # carry
    add     t2, t2, t0
    slli    t2, t2, 12
    srli    t1, t1, 20
    or      a0, t2, t1
    ret
    .size   q_mul_v0, . - q_mul_v0
