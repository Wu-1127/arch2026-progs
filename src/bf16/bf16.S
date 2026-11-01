# BFloat16 (Quiz 1 Problem B), hand-written RV32I, bit-exact with the C
# version (the quiz's code), its truncating multiply included.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)
# uint16_t bf16_sqrt_asm(uint16_t a)
#
# A bfloat16 travels as a zero-extended uint16_t in a0/a1. Fields: sign =
# bit 15, exponent = bits 14..7, mantissa = bits 6..0.
# RV32I only: no mul, div, rem, no floating point. Tests: tests/tbf16.c.

    .section .rodata
    .align  2
# isqrt(128 m + 127) & 0x7F, the result mantissa of the square root, for
# index (exp even) << 7 | mant, m = (0x80 | mant) << (exp even). The quiz's
# binary search over [90, 256] for the largest mid with mid * mid / 128 <= m
# returns exactly isqrt(128 m + 127), always in [128, 255], for every m the
# code produces (checked for all 256 cases when the table was generated).
sqrt_tab:
# index (exp even) << 7 | mant, m = (0x80 | mant) << (exp even).
    .byte   0x00, 0x00, 0x01, 0x01, 0x02, 0x02, 0x03, 0x03, 0x04, 0x04, 0x05, 0x05, 0x06, 0x06, 0x07, 0x07
    .byte   0x08, 0x08, 0x09, 0x09, 0x0a, 0x0a, 0x0b, 0x0b, 0x0b, 0x0c, 0x0c, 0x0d, 0x0d, 0x0e, 0x0e, 0x0f
    .byte   0x0f, 0x0f, 0x10, 0x10, 0x11, 0x11, 0x12, 0x12, 0x13, 0x13, 0x13, 0x14, 0x14, 0x15, 0x15, 0x16
    .byte   0x16, 0x16, 0x17, 0x17, 0x18, 0x18, 0x19, 0x19, 0x19, 0x1a, 0x1a, 0x1b, 0x1b, 0x1b, 0x1c, 0x1c
    .byte   0x1d, 0x1d, 0x1d, 0x1e, 0x1e, 0x1f, 0x1f, 0x1f, 0x20, 0x20, 0x21, 0x21, 0x21, 0x22, 0x22, 0x23
    .byte   0x23, 0x23, 0x24, 0x24, 0x25, 0x25, 0x25, 0x26, 0x26, 0x27, 0x27, 0x27, 0x28, 0x28, 0x28, 0x29
    .byte   0x29, 0x2a, 0x2a, 0x2a, 0x2b, 0x2b, 0x2b, 0x2c, 0x2c, 0x2d, 0x2d, 0x2d, 0x2e, 0x2e, 0x2e, 0x2f
    .byte   0x2f, 0x2f, 0x30, 0x30, 0x31, 0x31, 0x31, 0x32, 0x32, 0x32, 0x33, 0x33, 0x33, 0x34, 0x34, 0x35
    .byte   0x35, 0x36, 0x36, 0x37, 0x38, 0x38, 0x39, 0x3a, 0x3a, 0x3b, 0x3c, 0x3c, 0x3d, 0x3e, 0x3e, 0x3f
    .byte   0x40, 0x40, 0x41, 0x42, 0x42, 0x43, 0x44, 0x44, 0x45, 0x46, 0x46, 0x47, 0x48, 0x48, 0x49, 0x4a
    .byte   0x4a, 0x4b, 0x4b, 0x4c, 0x4d, 0x4d, 0x4e, 0x4f, 0x4f, 0x50, 0x50, 0x51, 0x52, 0x52, 0x53, 0x53
    .byte   0x54, 0x55, 0x55, 0x56, 0x56, 0x57, 0x58, 0x58, 0x59, 0x59, 0x5a, 0x5b, 0x5b, 0x5c, 0x5c, 0x5d
    .byte   0x5d, 0x5e, 0x5f, 0x5f, 0x60, 0x60, 0x61, 0x61, 0x62, 0x63, 0x63, 0x64, 0x64, 0x65, 0x65, 0x66
    .byte   0x67, 0x67, 0x68, 0x68, 0x69, 0x69, 0x6a, 0x6a, 0x6b, 0x6b, 0x6c, 0x6d, 0x6d, 0x6e, 0x6e, 0x6f
    .byte   0x6f, 0x70, 0x70, 0x71, 0x71, 0x72, 0x72, 0x73, 0x73, 0x74, 0x75, 0x75, 0x76, 0x76, 0x77, 0x77
    .byte   0x78, 0x78, 0x79, 0x79, 0x7a, 0x7a, 0x7b, 0x7b, 0x7c, 0x7c, 0x7d, 0x7d, 0x7e, 0x7e, 0x7f, 0x7f

    .text

# bf16_from_f32_asm: Inf and NaN (exponent all ones) keep their top half;
# everything else rounds to nearest, ties to even: add 0x7FFF plus the lowest
# kept bit, then drop the low half. (f32bits << 1) >= 0xFF000000 tests the
# exponent in two instructions.
    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
bf16_from_f32_asm:
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
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

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

# bf16_mul_asm: both significands have bit 7 set after normalization, so
# ma * mb = (ma << 7) + ma * (mb & 0x7F): a shift for the implicit bit and a
# 7-bit shift-and-add that stops when no set bit is left (1.0, 2.0 and 0.5
# cost no iteration). No call, no stack frame.
    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
bf16_mul_asm:
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
    .size   bf16_mul_asm, .-bf16_mul_asm

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

# bf16_sqrt_asm: the result depends only on the 7-bit mantissa and the parity
# of the exponent, so it is read from the 256-entry table above; the new
# exponent floor((exp - 127) / 2) + 127 equals (exp + 127) >> 1.
    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
bf16_sqrt_asm:
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
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
