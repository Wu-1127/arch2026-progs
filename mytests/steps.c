/* Optimization steps, measured the way tests/m<prog>.c measures the
 * submission: the same inputs, the same timed loop (BENCH) and the same loop
 * baseline. Every step is first checked against the C version of src/ (built
 * at -O2) on a sweep of inputs; a mismatch is reported as @@check with a
 * nonzero count and fails the run. mytests/steps.py turns the output into the
 * tables of the note. Not part of the graded build.
 */
#include <stddef.h>
#include <stdint.h>

#include "bench.h"
#include "print.h"
#include "rubikvec.h"
#include "src/bf16/bf16.h"
#include "src/fixed/fixed.h"
#include "src/gcd/gcd.h"
#include "src/rubik/rubik.h"

/* mytests/gcd_steps.S */
uint32_t gcd_quiz(uint32_t a, uint32_t b);
uint32_t gcd_v1(uint32_t a, uint32_t b);
uint32_t gcd_v2(uint32_t a, uint32_t b);
uint32_t gcd_v3(uint32_t a, uint32_t b);
uint32_t gcd_v4(uint32_t a, uint32_t b);
uint32_t gcd_v5(uint32_t a, uint32_t b);
uint32_t gcd_v6(uint32_t a, uint32_t b);
uint32_t gcd_v7(uint32_t a, uint32_t b);
uint32_t gcd_v8(uint32_t a, uint32_t b);

/* mytests/fixed_quiz.S and mytests/fixed_steps.S */
uint32_t op1_quiz(uint32_t a, uint32_t b, int *n);
uint32_t op1_v1(uint32_t a, uint32_t b, int *n);
uint32_t op2_quiz(uint32_t a, uint32_t b);
uint32_t op2_v1(uint32_t a, uint32_t b);
uint32_t op3_quiz(uint32_t a, uint32_t b);
uint32_t op3_v1(uint32_t a, uint32_t b);
int32_t q_mul_v0(int32_t a, int32_t b);
int32_t q_mul_v1(int32_t a, int32_t b);
int32_t q_mul_v2(int32_t a, int32_t b);
int32_t q_mul_v3(int32_t a, int32_t b);
int32_t q_mul_v4(int32_t a, int32_t b);
int32_t q_mul_v5(int32_t a, int32_t b);

/* mytests/bf16_steps.S */
uint16_t bf16_mul_v0(uint16_t a, uint16_t b);
uint16_t bf16_mul_v1(uint16_t a, uint16_t b);
uint16_t bf16_sqrt_v0(uint16_t a);
uint16_t bf16_sqrt_v1(uint16_t a);
uint16_t bf16_sqrt_v2(uint16_t a);

/* mytests/rubik_r1.S and mytests/rubik_r2.S */
int rubik_r1(const char *state, char *out, size_t cap);
int rubik_r2(const char *state, char *out, size_t cap);

static int failures;

static void check(const char *fn, const char *impl, unsigned bad)
{
    bm_printf("@@check fn=%s impl=%s mismatches=%u\n", fn, impl, bad);
    if (bad)
        failures++;
}

static uint32_t seed = 0x2545F491u;

static uint32_t rnd(void)
{
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    return seed;
}

/* A random value of random bit length, so short operands are common. */
static uint32_t rnd_len(void)
{
    uint32_t x = rnd();
    return x >> (rnd() & 31);
}

/* ---- gcd --------------------------------------------------------------- */

typedef uint32_t (*gcd_fn)(uint32_t, uint32_t);

static void check_gcd(const char *name, gcd_fn f)
{
    unsigned bad = 0;
    for (uint32_t a = 0; a < 256; a++)
        for (uint32_t b = 0; b < 256; b++)
            bad += f(a, b) != gcd_u32(a, b);
    for (int i = 0; i < 20000; i++) {
        uint32_t a = rnd_len(), b = rnd_len();
        bad += f(a, b) != gcd_u32(a, b);
    }
    check("gcd", name, bad);
}

static const uint32_t gcd_in[] = {
    1u,     2u,          6u,          48u,        1071u,      462u,
    65536u, 0xffffffffu, 0x80000000u, 123456789u, 987654321u, 0x7fffffffu,
    270u,   192u,        17u,         0u,
};
#define GCD_N (sizeof(gcd_in) / sizeof(gcd_in[0]))

#define BENCH_GCD(name, f) \
    BENCH("gcd", "gcd", name, gcd_in, GCD_N, f(in, (in >> 7) | 1u))

static void steps_gcd(void)
{
    static const struct {
        const char *name;
        gcd_fn f;
    } v[] = {
        {"quiz", gcd_quiz},   {"v1", gcd_v1}, {"v2", gcd_v2},
        {"v3", gcd_v3},       {"v4", gcd_v4}, {"v5", gcd_v5},
        {"v6", gcd_v6},       {"v7", gcd_v7}, {"v8", gcd_v8},
        {"asm", gcd_u32_asm},
    };
    for (size_t i = 0; i < sizeof v / sizeof v[0]; i++)
        check_gcd(v[i].name, v[i].f);
    BENCH_GCD("c", gcd_u32);
    BENCH_GCD("quiz", gcd_quiz);
    BENCH_GCD("v1", gcd_v1);
    BENCH_GCD("v2", gcd_v2);
    BENCH_GCD("v3", gcd_v3);
    BENCH_GCD("v4", gcd_v4);
    BENCH_GCD("v5", gcd_v5);
    BENCH_GCD("v6", gcd_v6);
    BENCH_GCD("v7", gcd_v7);
    BENCH_GCD("v8", gcd_v8);
    BENCH_GCD("asm", gcd_u32_asm);
}

/* ---- fixed ------------------------------------------------------------- */

static const uint32_t fixed_in[] = {
    0u,          0x00100000u, 0xfff00000u, 0x00180000u,
    0x7fffffffu, 0x80000000u, 0x000fffffu, 0xfff00001u,
    0x00080000u, 0xfff80000u, 0x00000001u, 0xffffffffu,
    0x01234567u, 0xfedcba98u, 0x40000000u, 0xc0000000u,
};
#define FIXED_N (sizeof(fixed_in) / sizeof(fixed_in[0]))

typedef uint32_t (*op1_fn)(uint32_t, uint32_t, int *);
typedef uint32_t (*op_fn)(uint32_t, uint32_t);
typedef int32_t (*qmul_fn)(int32_t, int32_t);

static uint32_t pair_a(int i)
{
    return i < 64 ? fixed_in[i & 15] + (uint32_t) (i >> 4) : rnd_len();
}

static void check_op1(const char *name, op1_fn f)
{
    unsigned bad = 0;
    for (int i = 0; i < 20000; i++) {
        uint32_t a = pair_a(i), b = rnd_len();
        int n1, n2;
        uint32_t r1 = f(a, b, &n1), r2 = op1(a, b, &n2);
        bad += r1 != r2 || n1 != n2;
    }
    check("op1", name, bad);
}

static void check_op(const char *fn, const char *name, op_fn f, op_fn ref)
{
    unsigned bad = 0;
    for (int i = 0; i < 20000; i++) {
        uint32_t a = pair_a(i), b = rnd_len();
        bad += f(a, b) != ref(a, b);
    }
    check(fn, name, bad);
}

static void check_qmul(const char *name, qmul_fn f)
{
    unsigned bad = 0;
    for (size_t i = 0; i < FIXED_N; i++)
        for (size_t j = 0; j < FIXED_N; j++) {
            int32_t a = (int32_t) fixed_in[i], b = (int32_t) fixed_in[j];
            bad += f(a, b) != q_mul(a, b);
        }
    for (int i = 0; i < 20000; i++) {
        int32_t a = (int32_t) rnd_len(), b = (int32_t) rnd_len();
        if (rnd() & 1)
            a = -a;
        if (rnd() & 1)
            b = -b;
        bad += f(a, b) != q_mul(a, b);
    }
    check("q_mul", name, bad);
}

static uint32_t run_op1(op1_fn f, uint32_t a, uint32_t b)
{
    int n;
    uint32_t r = f(a, b, &n);
    return r + (uint32_t) n;
}

#define BENCH_OP1(name, f) \
    BENCH("fixed", "op1", name, fixed_in, FIXED_N, run_op1(f, in, in >> 3))
#define BENCH_OP(fn, name, f) \
    BENCH("fixed", fn, name, fixed_in, FIXED_N, f(in, in >> 3))
#define BENCH_QMUL(name, f)                          \
    BENCH("fixed", "q_mul", name, fixed_in, FIXED_N, \
          f((int32_t) in, (int32_t) (in >> 5)))

static void steps_fixed(void)
{
    check_op1("quiz", op1_quiz);
    check_op1("v1", op1_v1);
    check_op1("asm", op1_asm);
    check_op("op2", "quiz", op2_quiz, op2);
    check_op("op2", "v1", op2_v1, op2);
    check_op("op2", "asm", op2_asm, op2);
    check_op("op3", "quiz", op3_quiz, op3);
    check_op("op3", "v1", op3_v1, op3);
    check_op("op3", "asm", op3_asm, op3);
    check_qmul("v0", q_mul_v0);
    check_qmul("v1", q_mul_v1);
    check_qmul("v2", q_mul_v2);
    check_qmul("v3", q_mul_v3);
    check_qmul("v4", q_mul_v4);
    check_qmul("v5", q_mul_v5);
    check_qmul("asm", q_mul_asm);

    BENCH_OP1("c", op1);
    BENCH_OP1("quiz", op1_quiz);
    BENCH_OP1("v1", op1_v1);
    BENCH_OP1("asm", op1_asm);
    BENCH_OP("op2", "c", op2);
    BENCH_OP("op2", "quiz", op2_quiz);
    BENCH_OP("op2", "v1", op2_v1);
    BENCH_OP("op2", "asm", op2_asm);
    BENCH_OP("op3", "c", op3);
    BENCH_OP("op3", "quiz", op3_quiz);
    BENCH_OP("op3", "v1", op3_v1);
    BENCH_OP("op3", "asm", op3_asm);
    BENCH_QMUL("c", q_mul);
    BENCH_QMUL("v0", q_mul_v0);
    BENCH_QMUL("v1", q_mul_v1);
    BENCH_QMUL("v2", q_mul_v2);
    BENCH_QMUL("v3", q_mul_v3);
    BENCH_QMUL("v4", q_mul_v4);
    BENCH_QMUL("v5", q_mul_v5);
    BENCH_QMUL("asm", q_mul_asm);
}

/* ---- bf16 -------------------------------------------------------------- */

static const uint32_t bf16_in[] = {
    0x3f803f80u, 0x40004000u, 0x3fc04040u, 0x7f807f80u,
    0x00800080u, 0xbf80bf80u, 0x3f000000u, 0x42280000u,
    0x3dcd3dcdu, 0x41204120u, 0x7f7f7f7fu, 0x00010001u,
    0x80008000u, 0x7fc07fc0u, 0x40490fdbu, 0x3f9a3f9au,
};
#define BF16_N (sizeof(bf16_in) / sizeof(bf16_in[0]))

typedef uint16_t (*mul_fn)(uint16_t, uint16_t);
typedef uint16_t (*sqrt_fn)(uint16_t);

static void check_mul(const char *name, mul_fn f)
{
    unsigned bad = 0;
    for (uint32_t i = 0; i < 65536; i++) {
        uint16_t a = (uint16_t) i, b = (uint16_t) (rnd() >> 16);
        bad += f(a, b) != bf16_mul(a, b);
    }
    for (size_t i = 0; i < BF16_N; i++)
        for (size_t j = 0; j < BF16_N; j++) {
            uint16_t a = (uint16_t) (bf16_in[i] >> 16);
            uint16_t b = (uint16_t) bf16_in[j];
            bad += f(a, b) != bf16_mul(a, b);
        }
    check("mul", name, bad);
}

static void check_sqrt(const char *name, sqrt_fn f)
{
    unsigned bad = 0;
    for (uint32_t i = 0; i < 65536; i++)
        bad += f((uint16_t) i) != bf16_sqrt((uint16_t) i);
    check("sqrt", name, bad);
}

#define BENCH_MUL(name, f)                      \
    BENCH("bf16", "mul", name, bf16_in, BF16_N, \
          f((uint16_t) (in >> 16), (uint16_t) (in & 0xffff)))
#define BENCH_SQRT(name, f) \
    BENCH("bf16", "sqrt", name, bf16_in, BF16_N, f((uint16_t) (in & 0xffff)))

static void steps_bf16(void)
{
    check_mul("v0", bf16_mul_v0);
    check_mul("v1", bf16_mul_v1);
    check_mul("asm", bf16_mul_asm);
    check_sqrt("v0", bf16_sqrt_v0);
    check_sqrt("v1", bf16_sqrt_v1);
    check_sqrt("v2", bf16_sqrt_v2);
    check_sqrt("asm", bf16_sqrt_asm);

    BENCH_MUL("c", bf16_mul);
    BENCH_MUL("v0", bf16_mul_v0);
    BENCH_MUL("v1", bf16_mul_v1);
    BENCH_MUL("asm", bf16_mul_asm);
    BENCH_SQRT("c", bf16_sqrt);
    BENCH_SQRT("v0", bf16_sqrt_v0);
    BENCH_SQRT("v1", bf16_sqrt_v1);
    BENCH_SQRT("v2", bf16_sqrt_v2);
    BENCH_SQRT("asm", bf16_sqrt_asm);
}

/* ---- rubik ------------------------------------------------------------- */

typedef int (*solve_fn)(const char *, char *, size_t);

static int same_text(const char *a, const char *b)
{
    while (*a && *a == *b) {
        a++;
        b++;
    }
    return *a == *b;
}

static void check_solve(const char *name, solve_fn f)
{
    static char out1[64], out2[64];
    unsigned bad = 0;
    for (size_t i = 0; i < sizeof rubik_cases / sizeof rubik_cases[0]; i++) {
        int n1 = f(rubik_cases[i].state, out1, sizeof out1);
        int n2 = rubik_solve(rubik_cases[i].state, out2, sizeof out2);
        bad +=
            n1 != n2 || n1 != rubik_cases[i].distance || !same_text(out1, out2);
    }
    check("solve", name, bad);
}

static const char *const rubik_states[] = {
    "12345671111111", "46253172123131", "43562713121333",
    "72465131321333", "62345713133111", "24513763133333",
};
static const uint32_t rubik_in[] = {0, 1, 2, 3, 4, 5};
#define RUBIK_N (sizeof(rubik_in) / sizeof(rubik_in[0]))
static char buf[64];

#define BENCH_SOLVE(name, f)                         \
    BENCH("rubik", "solve", name, rubik_in, RUBIK_N, \
          f(rubik_states[in], buf, sizeof buf))

static void steps_rubik(void)
{
    check_solve("r1", rubik_r1);
    check_solve("r2", rubik_r2);
    check_solve("asm", rubik_solve_asm);
    BENCH_SOLVE("c", rubik_solve);
    BENCH_SOLVE("r1", rubik_r1);
    BENCH_SOLVE("r2", rubik_r2);
    BENCH_SOLVE("asm", rubik_solve_asm);
}

int main(void)
{
    steps_gcd();
    steps_fixed();
    steps_bf16();
    steps_rubik();
    bm_printf("@@steps failures=%d\n", failures);
    return failures != 0;
}
