# BFloat16 in hand-written RV32I, bit-exact with the quiz's C code
# (bf16_quiz.h), quirks included: products and quotients truncate,
# bf16_sqrt flushes denormal inputs to zero, bf16_add drops an operand
# more than 8 binades smaller.
#
# A bfloat16 travels as a uint16_t in a0/a1 (zero-extended, as the ABI
# extends unsigned scalars), a binary32 as its uint32_t bit pattern. The
# fields: sign = bit 15, exponent = bits 14..7, mantissa = bits 6..0.
#
#   bf16_mul_v0  / v1   mantissa product through __mulsi3 / inline
#   bf16_div_v0  / v1 / v2   the C loop / a shifted remainder with a
#                            sentinel / remainder and quotient in one
#                            register, unrolled
#   bf16_sqrt_v0 / v1 / v2   binary search with __mulsi3 / digit-by-digit
#                            isqrt / 256-entry table

    .section .rodata
sqrt_tab:
    .include "mytests/bf16_sqrt_tab.inc"

    .text

# ---------------------------------------------------------------------
# Classification on x = bits & 0x7FFF (shift out the sign).
#   NaN:  x > 0x7F80    Inf: x == 0x7F80    zero: x == 0

    .globl  bf16_isnan_asm
    .type   bf16_isnan_asm, @function
bf16_isnan_asm:
    slli    a0, a0, 17
    srli    a0, a0, 17
    lui     t0, 0x8
    addi    t0, t0, -128          # 0x7F80
    sltu    a0, t0, a0
    ret
    .size   bf16_isnan_asm, . - bf16_isnan_asm

    .globl  bf16_isinf_asm
    .type   bf16_isinf_asm, @function
bf16_isinf_asm:
    slli    a0, a0, 17
    srli    a0, a0, 17
    lui     t0, 0x8
    addi    t0, t0, -128
    xor     a0, a0, t0
    seqz    a0, a0
    ret
    .size   bf16_isinf_asm, . - bf16_isinf_asm

    .globl  bf16_iszero_asm
    .type   bf16_iszero_asm, @function
bf16_iszero_asm:
    slli    a0, a0, 17
    seqz    a0, a0
    ret
    .size   bf16_iszero_asm, . - bf16_iszero_asm

# ---------------------------------------------------------------------
# uint16_t f32_to_bf16_asm(uint32_t f32bits)
# Inf and NaN (exponent all ones) keep their top half; everything else
# rounds to nearest, ties to even: add 0x7FFF plus the lowest kept bit,
# then drop the low half. (f32bits << 1) >= 0xFF000000 tests the
# exponent in two instructions.
    .globl  f32_to_bf16_asm
    .type   f32_to_bf16_asm, @function
f32_to_bf16_asm:
    slli    t0, a0, 1
    lui     t1, 0xFF000
    bgeu    t0, t1, ftb_special
    srli    t0, a0, 16
    andi    t0, t0, 1             # lowest kept bit: ties go to even
    lui     t1, 0x8
    addi    t1, t1, -1            # 0x7FFF
    add     a0, a0, t1
    add     a0, a0, t0
ftb_special:
    srli    a0, a0, 16
    ret
    .size   f32_to_bf16_asm, . - f32_to_bf16_asm

# uint32_t bf16_to_f32_asm(uint16_t a): the bits become the top half.
    .globl  bf16_to_f32_asm
    .type   bf16_to_f32_asm, @function
bf16_to_f32_asm:
    slli    a0, a0, 16
    ret
    .size   bf16_to_f32_asm, . - bf16_to_f32_asm

# ---------------------------------------------------------------------
# void bf16_negate_asm(uint16_t *v, size_t n)
# Flips bit 15 of each element. Once the pointer is word aligned, a word
# xor with 0x80008000 negates two elements, and the main loop does four
# words (eight elements) per iteration: 15 instructions for 8 elements.
    .globl  bf16_negate_asm
    .type   bf16_negate_asm, @function
bf16_negate_asm:
    lui     t1, 0x8               # 0x8000
    beq     a1, x0, ng_done
    andi    t0, a0, 2
    beq     t0, x0, ng_words
    lhu     t0, 0(a0)             # one element to reach word alignment
    xor     t0, t0, t1
    sh      t0, 0(a0)
    addi    a0, a0, 2
    addi    a1, a1, -1
ng_words:
    slli    t2, t1, 16
    or      t2, t2, t1            # 0x80008000
    addi    t3, x0, 8
    bltu    a1, t3, ng_pairs
ng_loop8:
    lw      t0, 0(a0)
    lw      t4, 4(a0)
    lw      t5, 8(a0)
    lw      t6, 12(a0)
    xor     t0, t0, t2
    xor     t4, t4, t2
    xor     t5, t5, t2
    xor     t6, t6, t2
    sw      t0, 0(a0)
    sw      t4, 4(a0)
    sw      t5, 8(a0)
    sw      t6, 12(a0)
    addi    a0, a0, 16
    addi    a1, a1, -8
    bgeu    a1, t3, ng_loop8
ng_pairs:
    addi    t3, x0, 2
    bltu    a1, t3, ng_tail
ng_loop2:
    lw      t0, 0(a0)
    xor     t0, t0, t2
    sw      t0, 0(a0)
    addi    a0, a0, 4
    addi    a1, a1, -2
    bgeu    a1, t3, ng_loop2
ng_tail:
    beq     a1, x0, ng_done
    lhu     t0, 0(a0)
    xor     t0, t0, t1
    sh      t0, 0(a0)
ng_done:
    ret
    .size   bf16_negate_asm, . - bf16_negate_asm

# ---------------------------------------------------------------------
# uint16_t bf16_add_asm(uint16_t a, uint16_t b), the C code's order of
# special cases. Registers: t0/t1 signs, t2/t3 exponents, t4/t5 mantissas,
# a2 result exponent, a3 result mantissa.
    .globl  bf16_add_asm
    .type   bf16_add_asm, @function
bf16_add_asm:
    srli    t0, a0, 15
    srli    t1, a1, 15
    srli    t2, a0, 7
    andi    t2, t2, 0xFF
    srli    t3, a1, 7
    andi    t3, t3, 0xFF
    andi    t4, a0, 0x7F
    andi    t5, a1, 0x7F
    addi    t6, x0, 0xFF
    bne     t2, t6, ad_afin
    bne     t4, x0, ad_ret_a      # a is NaN
    bne     t3, t6, ad_ret_a      # Inf + finite = Inf
    bne     t5, x0, ad_ret_b      # Inf + NaN = NaN (b)
    beq     t0, t1, ad_ret_b      # Inf + Inf of the same sign
    lui     a0, 0x8
    addi    a0, a0, -64           # Inf - Inf = NaN (0x7FC0)
    ret
ad_afin:
    beq     t3, t6, ad_ret_b      # b is Inf or NaN
    slli    t6, a0, 17
    beq     t6, x0, ad_ret_b      # a is +-0
    slli    t6, a1, 17
    beq     t6, x0, ad_ret_a      # b is +-0
    beq     t2, x0, 1f
    ori     t4, t4, 0x80          # implicit bit (not for denormals)
1:  beq     t3, x0, 2f
    ori     t5, t5, 0x80
2:  sub     t6, t2, t3            # exp_diff
    addi    a2, t2, 0             # result_exp = exp_a ...
    blt     t6, x0, ad_bbigger
    beq     t6, x0, ad_signs
    addi    a4, x0, 8
    blt     a4, t6, ad_ret_a      # b more than 8 binades smaller
    srl     t5, t5, t6
    j       ad_signs
ad_bbigger:
    addi    a2, t3, 0             # ... or exp_b
    addi    a4, x0, -8
    blt     t6, a4, ad_ret_b
    sub     t6, x0, t6
    srl     t4, t4, t6
ad_signs:
    bne     t0, t1, ad_diff
    add     a3, t4, t5
    andi    a4, a3, 0x100
    beq     a4, x0, ad_pack       # sign = sign_a (t0)
    srli    a3, a3, 1             # carry out: renormalize
    addi    a2, a2, 1
    addi    a4, x0, 0xFF
    blt     a2, a4, ad_pack
    slli    a0, t0, 15            # overflow: signed Inf
    lui     a4, 0x8
    addi    a4, a4, -128
    or      a0, a0, a4
    ret
ad_diff:
    bltu    t4, t5, ad_bmag
    sub     a3, t4, t5            # sign = sign_a
    j       ad_norm
ad_bmag:
    sub     a3, t5, t4
    addi    t0, t1, 0             # sign = sign_b
ad_norm:
    beq     a3, x0, ad_zero       # exact cancellation
ad_nloop:
    andi    a4, a3, 0x80
    bne     a4, x0, ad_pack
    slli    a3, a3, 1
    addi    a2, a2, -1
    blt     x0, a2, ad_nloop      # --exp <= 0 flushes to zero
ad_zero:
    addi    a0, x0, 0
    ret
ad_pack:
    slli    a0, t0, 15
    andi    a2, a2, 0xFF
    slli    a2, a2, 7
    or      a0, a0, a2
    andi    a3, a3, 0x7F
    or      a0, a0, a3
    ret
ad_ret_b:
    addi    a0, a1, 0
ad_ret_a:
    ret
    .size   bf16_add_asm, . - bf16_add_asm

# uint16_t bf16_sub_asm(uint16_t a, uint16_t b): a + (-b)
    .globl  bf16_sub_asm
    .type   bf16_sub_asm, @function
bf16_sub_asm:
    lui     t0, 0x8
    xor     a1, a1, t0
    j       bf16_add_asm
    .size   bf16_sub_asm, . - bf16_sub_asm

# ---------------------------------------------------------------------
# Shared front end of bf16_mul_v0/v1: special cases in the C code's order
# and normalization of denormal inputs. On fall-through:
#   a2 = result sign, t2/t3 = exponents (1 for a denormal),
#   t4/t5 = 8-bit mantissas with bit 7 set, a4 = exp_adjust (<= 0).
.macro MUL_FRONT p
    srli    t0, a0, 15
    srli    t1, a1, 15
    xor     a2, t0, t1            # result_sign
    srli    t2, a0, 7
    andi    t2, t2, 0xFF
    srli    t3, a1, 7
    andi    t3, t3, 0xFF
    andi    t4, a0, 0x7F
    andi    t5, a1, 0x7F
    addi    t6, x0, 0xFF
    bne     t2, t6, \p\()_afin
    bne     t4, x0, \p\()_ret_a   # NaN * x = NaN (a)
    slli    t6, a1, 17
    beq     t6, x0, \p\()_nan     # Inf * 0 = NaN
    j       \p\()_inf
\p\()_afin:
    bne     t3, t6, \p\()_bfin
    bne     t5, x0, \p\()_ret_b
    slli    t6, a0, 17
    beq     t6, x0, \p\()_nan
    j       \p\()_inf
\p\()_bfin:
    slli    t6, a0, 17
    beq     t6, x0, \p\()_szero
    slli    t6, a1, 17
    beq     t6, x0, \p\()_szero
    addi    a4, x0, 0             # exp_adjust
    bne     t2, x0, \p\()_anorm
\p\()_adnl:                       # denormal a: shift up to bit 7
    slli    t4, t4, 1
    addi    a4, a4, -1
    andi    t6, t4, 0x80
    beq     t6, x0, \p\()_adnl
    addi    t2, x0, 1
    j       \p\()_bchk
\p\()_anorm:
    ori     t4, t4, 0x80
\p\()_bchk:
    bne     t3, x0, \p\()_bnorm
\p\()_bdnl:
    slli    t5, t5, 1
    addi    a4, a4, -1
    andi    t6, t5, 0x80
    beq     t6, x0, \p\()_bdnl
    addi    t3, x0, 1
    j       \p\()_fdone
\p\()_bnorm:
    ori     t5, t5, 0x80
\p\()_fdone:
.endm

# Shared back end: a3 = 16-bit mantissa product, a5 = result exponent
# before adjustment, a2 = sign. Truncates as the C code does.
.macro MUL_BACK p
    lui     t6, 0x8
    and     t6, a3, t6
    beq     t6, x0, \p\()_lo
    srli    a3, a3, 8             # product in [2, 4): one more binade
    addi    a5, a5, 1
    j       \p\()_chk
\p\()_lo:
    srli    a3, a3, 7
\p\()_chk:
    andi    a3, a3, 0x7F
    addi    t6, x0, 0xFF
    bge     a5, t6, \p\()_inf
    blt     x0, a5, \p\()_pack
    addi    t6, x0, -6
    blt     a5, t6, \p\()_szero   # below the denormal range
    addi    t6, x0, 1
    sub     t6, t6, a5
    srl     a3, a3, t6            # denormal result (implicit bit already gone)
    addi    a5, x0, 0
\p\()_pack:
    slli    a0, a2, 15
    andi    a5, a5, 0xFF
    slli    a5, a5, 7
    or      a0, a0, a5
    or      a0, a0, a3
    ret
\p\()_inf:
    slli    a0, a2, 15
    lui     t6, 0x8
    addi    t6, t6, -128
    or      a0, a0, t6
    ret
\p\()_szero:
    slli    a0, a2, 15
    ret
\p\()_nan:
    lui     a0, 0x8
    addi    a0, a0, -64
    ret
\p\()_ret_b:
    addi    a0, a1, 0
\p\()_ret_a:
    ret
.endm

# uint16_t bf16_mul_v0(uint16_t a, uint16_t b)
# The C code's shape: the 8 x 8-bit product through __mulsi3, which
# loops over the bits of its second operand (8 iterations here).
    .globl  bf16_mul_v0
    .type   bf16_mul_v0, @function
bf16_mul_v0:
    MUL_FRONT m0
    add     a5, t2, t3
    add     a5, a5, a4
    addi    a5, a5, -127          # exp_a + exp_b - bias + exp_adjust
    addi    sp, sp, -16
    sw      ra, 12(sp)
    sw      a2, 8(sp)
    sw      a5, 4(sp)
    addi    a0, t4, 0
    addi    a1, t5, 0
    call    __mulsi3
    addi    a3, a0, 0
    lw      ra, 12(sp)
    lw      a2, 8(sp)
    lw      a5, 4(sp)
    addi    sp, sp, 16
    MUL_BACK m0
    .size   bf16_mul_v0, . - bf16_mul_v0

# uint16_t bf16_mul_v1(uint16_t a, uint16_t b)
# Both mantissas have bit 7 set, so ma * mb = (ma << 7) + ma * (mb & 0x7F):
# a shift for the implicit bit and a 7-bit shift-and-add that stops when
# no set bit is left. 1.0, 2.0 or 0.5 (mb & 0x7F = 0) cost no iteration,
# 1.5 one; no call, no stack frame.
    .globl  bf16_mul_v1
    .type   bf16_mul_v1, @function
bf16_mul_v1:
    MUL_FRONT m1
    add     a5, t2, t3
    add     a5, a5, a4
    addi    a5, a5, -127
    slli    a3, t4, 7             # ma * 128
    andi    t5, t5, 0x7F
    beq     t5, x0, m1_pdone
m1_ploop:                         # t4 = ma << i for bit i of mb & 0x7F
    andi    t6, t5, 1
    srli    t5, t5, 1
    beq     t6, x0, m1_pskip
    add     a3, a3, t4
m1_pskip:
    slli    t4, t4, 1
    bne     t5, x0, m1_ploop
m1_pdone:
    MUL_BACK m1
    .size   bf16_mul_v1, . - bf16_mul_v1

# ---------------------------------------------------------------------
# Division front end: special cases in the C code's order. On
# fall-through: a2 = sign, t2/t3 = exponents (0 for a denormal), t4/t5 =
# mantissas with the implicit bit for normal inputs.
.macro DIV_FRONT p
    srli    t0, a0, 15
    srli    t1, a1, 15
    xor     a2, t0, t1
    srli    t2, a0, 7
    andi    t2, t2, 0xFF
    srli    t3, a1, 7
    andi    t3, t3, 0xFF
    andi    t4, a0, 0x7F
    andi    t5, a1, 0x7F
    addi    t6, x0, 0xFF
    bne     t3, t6, \p\()_bfin
    bne     t5, x0, \p\()_ret_b   # x / NaN = NaN (b)
    bne     t2, t6, \p\()_szero   # finite / Inf = 0
    bne     t4, x0, \p\()_szero   # NaN / Inf: the C code returns 0 too
    j       \p\()_nan             # Inf / Inf
\p\()_bfin:
    slli    a3, a1, 17
    bne     a3, x0, \p\()_bnz
    slli    a3, a0, 17
    beq     a3, x0, \p\()_nan     # 0 / 0
    j       \p\()_inf             # x / 0
\p\()_bnz:
    bne     t2, t6, \p\()_afin
    bne     t4, x0, \p\()_ret_a   # NaN / x
    j       \p\()_inf             # Inf / x
\p\()_afin:
    slli    a3, a0, 17
    beq     a3, x0, \p\()_szero   # 0 / x
    beq     t2, x0, 1f
    ori     t4, t4, 0x80
1:  beq     t3, x0, 2f
    ori     t5, t5, 0x80
2:
.endm

# Division back end: a5 = 16-bit quotient; computes the exponent from
# t2/t3, normalizes and truncates as the C code does.
.macro DIV_BACK p
    sub     a4, t2, t3
    addi    a4, a4, 127           # exp_a - exp_b + bias
    bne     t2, x0, 1f
    addi    a4, a4, -1
1:  bne     t3, x0, 2f
    addi    a4, a4, 1
2:  lui     t6, 0x8               # 0x8000
    and     a3, a5, t6
    bne     a3, x0, \p\()_shift
    addi    t0, x0, 1
\p\()_nl:                         # while (!(q & 0x8000) && exp > 1)
    bge     t0, a4, \p\()_shift
    slli    a5, a5, 1
    addi    a4, a4, -1
    and     a3, a5, t6
    beq     a3, x0, \p\()_nl
\p\()_shift:
    srli    a5, a5, 8
    andi    a5, a5, 0x7F
    addi    t6, x0, 0xFF
    bge     a4, t6, \p\()_inf
    bge     x0, a4, \p\()_szero
    slli    a0, a2, 15
    slli    a4, a4, 7
    or      a0, a0, a4
    or      a0, a0, a5
    ret
\p\()_inf:
    slli    a0, a2, 15
    lui     t6, 0x8
    addi    t6, t6, -128
    or      a0, a0, t6
    ret
\p\()_szero:
    slli    a0, a2, 15
    ret
\p\()_nan:
    lui     a0, 0x8
    addi    a0, a0, -64
    ret
\p\()_ret_b:
    addi    a0, a1, 0
\p\()_ret_a:
    ret
.endm

# uint16_t bf16_div_v0(uint16_t a, uint16_t b)
# The C loop: 16 restoring steps comparing the dividend ma << 15 with
# mb << (15 - i), the shifted divisor kept in a register.
    .globl  bf16_div_v0
    .type   bf16_div_v0, @function
bf16_div_v0:
    DIV_FRONT d0
    slli    a3, t4, 15            # dividend
    slli    a4, t5, 15            # divisor << 15
    addi    a5, x0, 0             # quotient
    addi    a6, x0, 16
d0_loop:
    slli    a5, a5, 1
    bltu    a3, a4, d0_skip
    sub     a3, a3, a4
    ori     a5, a5, 1
d0_skip:
    srli    a4, a4, 1
    addi    a6, a6, -1
    bne     a6, x0, d0_loop
    DIV_BACK d0
    .size   bf16_div_v0, . - bf16_div_v0

# uint16_t bf16_div_v1(uint16_t a, uint16_t b)
# Step i compares D_i >= mb * 2^(15-i), where the running dividend D_i is a
# multiple of 2^(15-i); dividing by 2^(15-i), the same test reads
# R_i >= mb with R_0 = ma and R_(i+1) = 2 (R_i - [subtracted] mb). So the
# divisor stays put and the remainder shifts left, and a sentinel bit in
# the quotient ends the loop after 16 steps (it reaches bit 16) instead of
# a separate counter: 6 instructions per step instead of 7.
    .globl  bf16_div_v1
    .type   bf16_div_v1, @function
bf16_div_v1:
    DIV_FRONT d1
    addi    a3, t4, 0             # remainder R_0 = ma
    addi    a5, x0, 1             # sentinel
    lui     a6, 0x10              # 0x10000: the sentinel after 16 shifts
d1_loop:
    slli    a5, a5, 1
    bltu    a3, t5, d1_skip
    sub     a3, a3, t5
    ori     a5, a5, 1
d1_skip:
    slli    a3, a3, 1
    bltu    a5, a6, d1_loop
    sub     a5, a5, a6            # drop the sentinel
    DIV_BACK d1
    .size   bf16_div_v1, . - bf16_div_v1

# uint16_t bf16_div_v2(uint16_t a, uint16_t b)
# Remainder and quotient share one register: X = R * 2^17 + Q, where the
# quotient bits Q stay below 2^17. Then X >= mb * 2^17 exactly when
# R >= mb, and subtracting M - 1 = mb * 2^17 - 1 takes mb off R and sets
# the new quotient bit in one instruction; one slli then shifts both.
# A step is bltu, sub, slli (2 or 3 instructions), unrolled 16 times.
# With a normal divisor (mb >= 128) R < 2 mb <= 510 stays below 2^9, so
# X < 2^26; a denormal divisor can make R grow past 2^15 (the C code's
# 16 steps then do not hold the whole quotient), so that rare case takes
# v1's two-register loop instead.
    .globl  bf16_div_v2
    .type   bf16_div_v2, @function
bf16_div_v2:
    DIV_FRONT d2
    beq     t3, x0, d2_slow       # denormal divisor
    slli    a3, t4, 17            # X = ma * 2^17
    slli    a4, t5, 17            # M = mb * 2^17
    addi    a5, a4, -1            # M - 1
    .rept   16
    bltu    a3, a4, 1f
    sub     a3, a3, a5            # R -= mb, quotient bit = 1
1:  slli    a3, a3, 1
    .endr
    srli    a5, a3, 1             # the 16 quotient bits sit at bits 16..1
    slli    a5, a5, 16
    srli    a5, a5, 16
    j       d2_back
d2_slow:
    addi    a3, t4, 0
    addi    a5, x0, 1
    lui     a6, 0x10
d2_loop:
    slli    a5, a5, 1
    bltu    a3, t5, d2_skip
    sub     a3, a3, t5
    ori     a5, a5, 1
d2_skip:
    slli    a3, a3, 1
    bltu    a5, a6, d2_loop
    sub     a5, a5, a6
d2_back:
    DIV_BACK d2
    .size   bf16_div_v2, . - bf16_div_v2

# ---------------------------------------------------------------------
# Square root front end, in the C code's order: Inf/NaN, +-0 -> +0,
# negative -> NaN, denormal -> +0. Falls through with t0 = exp (1..254),
# t1 = mant.
.macro SQRT_FRONT p
    srli    t0, a0, 7
    andi    t0, t0, 0xFF
    andi    t1, a0, 0x7F
    srli    t2, a0, 15
    addi    t3, x0, 0xFF
    bne     t0, t3, \p\()_fin
    bne     t1, x0, \p\()_ret     # NaN propagates
    beq     t2, x0, \p\()_ret     # sqrt(+Inf) = +Inf
    j       \p\()_nan             # sqrt(-Inf) = NaN
\p\()_fin:
    slli    t3, a0, 17
    beq     t3, x0, \p\()_zero    # +-0 -> +0
    bne     t2, x0, \p\()_nan     # negative
    beq     t0, x0, \p\()_zero    # denormal: flushed
.endm

.macro SQRT_TAIL p
\p\()_zero:
    addi    a0, x0, 0
\p\()_ret:
    ret
\p\()_nan:
    lui     a0, 0x8
    addi    a0, a0, -64
    ret
.endm

# uint16_t bf16_sqrt_v0(uint16_t a)
# The C code's shape: binary search over [90, 256] for the largest mid
# with (mid * mid) / 128 <= m, one __mulsi3 call per step, followed by the
# C code's normalization and range checks.
    .globl  bf16_sqrt_v0
    .type   bf16_sqrt_v0, @function
bf16_sqrt_v0:
    SQRT_FRONT s0
    addi    sp, sp, -32
    sw      ra, 28(sp)
    sw      s0, 24(sp)
    sw      s1, 20(sp)
    sw      s2, 16(sp)
    sw      s3, 12(sp)
    sw      s4, 8(sp)
    addi    t2, t0, -127          # e
    ori     s0, t1, 0x80          # m
    andi    t3, t2, 1
    beq     t3, x0, s0_even
    slli    s0, s0, 1             # odd e: m doubled
    addi    t2, t2, -1
s0_even:
    srai    t2, t2, 1
    addi    s4, t2, 127           # new_exp
    addi    s1, x0, 90            # low
    addi    s2, x0, 256           # high
    addi    s3, x0, 128           # result
s0_loop:
    bltu    s2, s1, s0_done
    add     a0, s1, s2
    srli    a0, a0, 1             # mid
    sw      a0, 4(sp)
    addi    a1, a0, 0
    call    __mulsi3
    lw      t0, 4(sp)             # mid
    srli    a0, a0, 7             # sq = mid * mid / 128
    bltu    s0, a0, s0_high
    addi    s3, t0, 0             # result = mid
    addi    s1, t0, 1
    j       s0_loop
s0_high:
    addi    s2, t0, -1
    j       s0_loop
s0_done:
    addi    t0, x0, 256
    bltu    s3, t0, s0_small
    srli    s3, s3, 1
    addi    s4, s4, 1
    j       s0_mant
s0_small:
    addi    t0, x0, 128
    addi    t1, x0, 1
s0_up:                            # while (result < 128 && new_exp > 1)
    bgeu    s3, t0, s0_mant
    bge     t1, s4, s0_mant
    slli    s3, s3, 1
    addi    s4, s4, -1
    j       s0_up
s0_mant:
    andi    s3, s3, 0x7F
    addi    t0, x0, 0xFF
    addi    a0, x0, 0
    bge     x0, s4, s0_out        # underflow: +0
    lui     a0, 0x8
    addi    a0, a0, -128          # overflow: +Inf
    bge     s4, t0, s0_out
    andi    a0, s4, 0xFF
    slli    a0, a0, 7
    or      a0, a0, s3
s0_out:
    lw      ra, 28(sp)
    lw      s0, 24(sp)
    lw      s1, 20(sp)
    lw      s2, 16(sp)
    lw      s3, 12(sp)
    lw      s4, 8(sp)
    addi    sp, sp, 32
    ret
    SQRT_TAIL s0
    .size   bf16_sqrt_v0, . - bf16_sqrt_v0

# uint16_t bf16_sqrt_v1(uint16_t a)
# The search returns the largest r with floor(r^2 / 128) <= m, that is
# r^2 <= 128 m + 127, so r = isqrt(128 m + 127); for m in [128, 510] that
# is always in [128, 255] (tools/gen_bf16_sqrt_tab.py checks every m), so
# the C code's normalization and range checks never fire, and the new
# exponent floor((exp - 127) / 2) + 127 equals (exp + 127) >> 1. The isqrt
# of x < 2^16 is computed digit by digit: one result bit per step, from
# bit 7 down, with a compare and a subtract, no multiply.
    .globl  bf16_sqrt_v1
    .type   bf16_sqrt_v1, @function
bf16_sqrt_v1:
    SQRT_FRONT s1
    ori     t1, t1, 0x80          # m
    andi    t2, t0, 1
    bne     t2, x0, s1_odd        # exp odd <=> e even
    slli    t1, t1, 1             # e odd: m doubled
s1_odd:
    slli    t1, t1, 7
    ori     t1, t1, 127           # x = 128 m + 127
    addi    t2, x0, 0             # r
    lui     t3, 0x4               # bit = 1 << 14
s1_loop:
    add     t4, t2, t3
    srli    t2, t2, 1
    bltu    t1, t4, s1_next
    sub     t1, t1, t4
    add     t2, t2, t3
s1_next:
    srli    t3, t3, 2
    bne     t3, x0, s1_loop
    andi    t2, t2, 0x7F          # r in [128, 255]: drop the implicit bit
    addi    t0, t0, 127
    srli    t0, t0, 1             # new_exp
    slli    t0, t0, 7
    or      a0, t0, t2
    ret
    SQRT_TAIL s1
    .size   bf16_sqrt_v1, . - bf16_sqrt_v1

# uint16_t bf16_sqrt_v2(uint16_t a)
# The result mantissa depends only on the 7-bit mantissa and the parity
# of the exponent: 256 cases, read from a table (256 bytes of .rodata).
    .globl  bf16_sqrt_v2
    .type   bf16_sqrt_v2, @function
bf16_sqrt_v2:
    SQRT_FRONT s2
    andi    t2, t0, 1
    xori    t2, t2, 1             # 1 when exp is even (m doubled)
    slli    t2, t2, 7
    or      t2, t2, t1
    la      t3, sqrt_tab
    add     t3, t3, t2
    lbu     t2, 0(t3)
    addi    t0, t0, 127
    srli    t0, t0, 1
    slli    t0, t0, 7
    or      a0, t0, t2
    ret
    SQRT_TAIL s2
    .size   bf16_sqrt_v2, . - bf16_sqrt_v2
