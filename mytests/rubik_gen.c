/* Host generator for the minirubik tables (not part of the submission build).
 *
 *   cc -O2 -o rubik_gen mytests/rubik_gen.c && ./rubik_gen src/rubik
 *
 * writes src/rubik/rubik_tab.h (C arrays) and src/rubik/rubik_tab.inc (the
 * same data as assembler directives). The cube model is the one of
 * tests/trubik.c (sysprog21/minirubik solver.c): quarter turn of a face sends
 * the cubie and twist at source[face][i] to position i, adding twist[face][i].
 *
 * Coordinates: p = Lehmer rank of the seven cubies (0..5039, 0 = solved),
 * o = twists of positions 0..5 in base 3, most significant first (0..728);
 * the seventh twist follows from the sum. The key of a state is p << 10 | o.
 *
 * Tables:
 *   pm[p][f]  f < 3: p after a quarter turn of face f; pm[p][3]: the distance
 *             of the permutation alone (all nine moves)
 *   om[o][f]  the same for the orientation
 *   near[]    sorted key << 3 | distance, every state within 5 moves
 *   far[]     sorted keys of the states at distance 11
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { NP = 5040, NO = 729, N = NP * NO };

static const int source[3][7] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const int twist[3][7] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

static int rank_perm(const int *c)
{
    static const int w[7] = {720, 120, 24, 6, 2, 1, 0};
    int p = 0;
    for (int i = 0; i < 7; i++)
        for (int j = i + 1; j < 7; j++)
            if (c[j] < c[i])
                p += w[i];
    return p;
}

static void unrank_perm(int p, int *c)
{
    static const int w[7] = {720, 120, 24, 6, 2, 1, 1};
    int used[7] = {0}, d[7];
    for (int i = 0; i < 7; i++) {
        d[i] = p / w[i];
        p %= w[i];
    }
    for (int i = 0; i < 7; i++) {
        int k = d[i];
        for (int v = 0; v < 7; v++) {
            if (used[v])
                continue;
            if (k-- == 0) {
                c[i] = v;
                used[v] = 1;
                break;
            }
        }
    }
}

static int rank_orient(const int *t)
{
    int o = 0;
    for (int i = 0; i < 6; i++)
        o = o * 3 + t[i];
    return o;
}

static void unrank_orient(int o, int *t)
{
    int s = 0;
    for (int i = 5; i >= 0; i--) {
        t[i] = o % 3;
        o /= 3;
        s += t[i];
    }
    t[6] = (3 - s % 3) % 3;
}

static uint16_t pm[NP][4], om[NO][4];
static uint8_t dist[N];

static int key(int p, int o)
{
    return p << 10 | o;
}

static int cmp_u32(const void *a, const void *b)
{
    uint32_t x = *(const uint32_t *) a, y = *(const uint32_t *) b;
    return x < y ? -1 : x > y;
}

/* Distance of one coordinate alone, by breadth-first search over 9 moves. */
static void coord_dist(uint16_t (*t)[4], int n)
{
    for (int i = 0; i < n; i++)
        t[i][3] = 0xff;
    t[0][3] = 0;
    for (int d = 0, more = 1; more; d++) {
        more = 0;
        for (int i = 0; i < n; i++) {
            if (t[i][3] != d)
                continue;
            for (int f = 0; f < 3; f++) {
                int x = i;
                for (int k = 0; k < 3; k++) {
                    x = t[x][f];
                    if (t[x][3] == 0xff) {
                        t[x][3] = (uint16_t) (d + 1);
                        more = 1;
                    }
                }
            }
        }
    }
}

int main(int argc, char **argv)
{
    const char *dir = argc > 1 ? argv[1] : ".";
    for (int p = 0; p < NP; p++) {
        int c[7], n[7];
        unrank_perm(p, c);
        if (rank_perm(c) != p)
            abort();
        for (int f = 0; f < 3; f++) {
            for (int i = 0; i < 7; i++)
                n[i] = c[source[f][i]];
            pm[p][f] = (uint16_t) rank_perm(n);
        }
    }
    for (int o = 0; o < NO; o++) {
        int t[7], n[7];
        unrank_orient(o, t);
        for (int f = 0; f < 3; f++) {
            for (int i = 0; i < 7; i++)
                n[i] = (t[source[f][i]] + twist[f][i]) % 3;
            om[o][f] = (uint16_t) rank_orient(n);
        }
    }
    coord_dist(pm, NP);
    coord_dist(om, NO);

    /* Full breadth-first search over p * 729 + o. */
    memset(dist, 0xff, sizeof dist);
    dist[0] = 0;
    long count[16] = {1};
    int maxd = 0;
    for (int d = 0;; d++) {
        long found = 0;
        for (int s = 0; s < N; s++) {
            if (dist[s] != d)
                continue;
            int p = s / NO, o = s % NO;
            for (int f = 0; f < 3; f++) {
                int q = p, r = o;
                for (int k = 0; k < 3; k++) {
                    q = pm[q][f];
                    r = om[r][f];
                    int u = q * NO + r;
                    if (dist[u] == 0xff) {
                        dist[u] = (uint8_t) (d + 1);
                        found++;
                    }
                }
            }
        }
        if (!found)
            break;
        count[d + 1] = found;
        maxd = d + 1;
    }
    for (int d = 0; d <= maxd; d++)
        fprintf(stderr, "distance %2d: %7ld\n", d, count[d]);

    int nnear = 0, nfar = 0;
    for (int d = 0; d <= 5; d++)
        nnear += (int) count[d];
    nfar = (int) count[11];
    uint32_t *near = malloc(sizeof(uint32_t) * nnear);
    uint32_t *far = malloc(sizeof(uint32_t) * nfar);
    if (!near || !far)
        return 1;
    int a = 0, b = 0;
    for (int s = 0; s < N; s++) {
        int p = s / NO, o = s % NO;
        if (dist[s] <= 5)
            near[a++] = (uint32_t) key(p, o) << 3 | dist[s];
        else if (dist[s] == 11)
            far[b++] = (uint32_t) key(p, o);
    }
    qsort(near, nnear, sizeof *near, cmp_u32);
    qsort(far, nfar, sizeof *far, cmp_u32);

    char path[512];
    snprintf(path, sizeof path, "%s/rubik_tab.h", dir);
    FILE *h = fopen(path, "w");
    snprintf(path, sizeof path, "%s/rubik_tab.inc", dir);
    FILE *s = fopen(path, "w");
    if (!h || !s)
        return 1;

    fprintf(h,
            "/* Generated by mytests/rubik_gen.c. Do not edit. */\n"
            "#pragma once\n\n#include <stdint.h>\n\n"
            "#define RUBIK_NNEAR %d\n#define RUBIK_NFAR %d\n\n",
            nnear, nfar);
    fprintf(s,
            "# Generated by mytests/rubik_gen.c. Do not edit.\n"
            "    .equ    RUBIK_NNEAR, %d\n    .equ    RUBIK_NFAR, %d\n\n"
            "    .section .rodata\n",
            nnear, nfar);

    /* C: four values per line for the 4-wide rows, eight keys per line. */
    fprintf(h, "static const uint16_t rubik_pm[%d][4] = {\n", NP);
    for (int p = 0; p < NP; p++)
        fprintf(h, "    {%u, %u, %u, %u},\n", pm[p][0], pm[p][1], pm[p][2],
                pm[p][3]);
    fprintf(h, "};\n\nstatic const uint16_t rubik_om[%d][4] = {\n", NO);
    for (int o = 0; o < NO; o++)
        fprintf(h, "    {%u, %u, %u, %u},\n", om[o][0], om[o][1], om[o][2],
                om[o][3]);
    fprintf(h, "};\n\nstatic const uint32_t rubik_near[RUBIK_NNEAR] = {\n");
    for (int i = 0; i < nnear; i++)
        fprintf(h, "%s%uu,%s", i % 6 ? " " : "    ", near[i],
                i % 6 == 5 || i == nnear - 1 ? "\n" : "");
    fprintf(h, "};\n\nstatic const uint32_t rubik_far[RUBIK_NFAR] = {\n");
    for (int i = 0; i < nfar; i++)
        fprintf(h, "%s%uu,%s", i % 6 ? " " : "    ", far[i],
                i % 6 == 5 || i == nfar - 1 ? "\n" : "");
    fprintf(h, "};\n");

    fprintf(s, "    .align  2\nrubik_pm:\n");
    for (int p = 0; p < NP; p++)
        fprintf(s, "    .half   %u, %u, %u, %u\n", pm[p][0], pm[p][1], pm[p][2],
                pm[p][3]);
    fprintf(s, "    .align  2\nrubik_om:\n");
    for (int o = 0; o < NO; o++)
        fprintf(s, "    .half   %u, %u, %u, %u\n", om[o][0], om[o][1], om[o][2],
                om[o][3]);
    fprintf(s, "    .align  2\nrubik_near:\n");
    for (int i = 0; i < nnear; i += 8) {
        fprintf(s, "    .word   ");
        for (int j = i; j < i + 8 && j < nnear; j++)
            fprintf(s, "%s%u", j > i ? ", " : "", near[j]);
        fprintf(s, "\n");
    }
    fprintf(s, "    .align  2\nrubik_far:\n");
    for (int i = 0; i < nfar; i += 8) {
        fprintf(s, "    .word   ");
        for (int j = i; j < i + 8 && j < nfar; j++)
            fprintf(s, "%s%u", j > i ? ", " : "", far[j]);
        fprintf(s, "\n");
    }
    fclose(h);
    fclose(s);
    return 0;
}
