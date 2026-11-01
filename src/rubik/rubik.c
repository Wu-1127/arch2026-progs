#include "rubik.h"
#include "rubik_tab.h"

/* Optimal 2x2x2 solver: iterative deepening that ends in a table.
 *
 * A state is reduced to two coordinates: p, the Lehmer rank of the seven
 * cubies (0..5039), and o, the twists of the first six positions in base 3
 * (0..728). rubik_pm[p][f] and rubik_om[o][f] give them after a quarter turn
 * of face f; column 3 holds the distance of the coordinate alone, a lower
 * bound on the distance of the state. rubik_near lists every state within five
 * moves with its distance, rubik_far the 2,644 states at distance 11.
 *
 * A state found in rubik_near is solved by walking down the table: some move
 * always leads to a state one closer. Otherwise the distance is d in 6..11.
 * For d = 6..10, a depth-first search of d - 5 moves, pruned by the
 * coordinate distances, looks for a state of rubik_near. A state of rubik_far
 * is at 11: a move to a state outside the table brings it to 10.
 */

#define KEY(p, o) ((uint32_t) (p) << 10 | (uint32_t) (o))

/* Distance of a state within five moves, or -1. */
static int near_dist(uint32_t key)
{
    uint32_t lo = 0, hi = RUBIK_NNEAR;
    while (lo < hi) {
        uint32_t mid = (lo + hi) >> 1;
        uint32_t k = rubik_near[mid] >> 3;
        if (k == key)
            return (int) (rubik_near[mid] & 7);
        if (k < key)
            lo = mid + 1;
        else
            hi = mid;
    }
    return -1;
}

static int is_far(uint32_t key)
{
    uint32_t lo = 0, hi = RUBIK_NFAR;
    while (lo < hi) {
        uint32_t mid = (lo + hi) >> 1;
        uint32_t k = rubik_far[mid];
        if (k == key)
            return 1;
        if (k < key)
            lo = mid + 1;
        else
            hi = mid;
    }
    return 0;
}

static uint8_t path[12];

/* Appends the moves of a state of rubik_near at distance k, from path[g]. */
static void walk(uint32_t p, uint32_t o, int k, int g)
{
    while (k > 0) {
        for (int f = 0; f < 3; f++) {
            uint32_t q = p, r = o;
            int t;
            for (t = 0; t < 3; t++) {
                q = rubik_pm[q][f];
                r = rubik_om[r][f];
                if (near_dist(KEY(q, r)) == k - 1)
                    break;
            }
            if (t < 3) {
                path[g++] = (uint8_t) (3 * f + t);
                p = q;
                o = r;
                k--;
                break;
            }
        }
    }
}

/* Depth-first search for a state of rubik_near after `left` more moves, with
 * at most `bound` moves in all from the root. Returns 1 and fills path[] on
 * success.
 */
static int search(uint32_t p, uint32_t o, int g, int left, int bound, int last)
{
    if (left == 0) {
        int k = near_dist(KEY(p, o));
        if (k < 0)
            return 0;
        walk(p, o, k, g);
        return 1;
    }
    for (int f = 0; f < 3; f++) {
        if (f == last)
            continue;
        uint32_t q = p, r = o;
        for (int t = 0; t < 3; t++) {
            q = rubik_pm[q][f];
            r = rubik_om[r][f];
            int h = rubik_pm[q][3];
            if (rubik_om[r][3] > h)
                h = rubik_om[r][3];
            if (g + 1 + h > bound)
                continue;
            path[g] = (uint8_t) (3 * f + t);
            if (search(q, r, g + 1, left - 1, bound, f))
                return 1;
        }
    }
    return 0;
}

/* Parses and checks the state. Returns 0 and the coordinates, or -1. */
static int parse(const char *s, uint32_t *pp, uint32_t *po)
{
    static const uint16_t weight[7] = {720, 120, 24, 6, 2, 1, 0};
    unsigned seen = 0, sum = 0;
    uint32_t p = 0, o = 0;
    for (int i = 0; i < 7; i++) {
        unsigned c = (unsigned) (s[i] - '1');
        if (c > 6 || (seen >> c & 1))
            return -1;
        seen |= 1u << c;
    }
    for (int i = 7; i < 14; i++) {
        unsigned c = (unsigned) (s[i] - '1');
        if (c > 2)
            return -1;
        sum += c;
        if (i < 13)
            o = o * 3 + c;
    }
    if (s[14] != '\0')
        return -1;
    while (sum >= 3)
        sum -= 3;
    if (sum)
        return -1;
    for (int i = 0; i < 6; i++)
        for (int j = i + 1; j < 7; j++)
            if (s[j] < s[i])
                p += weight[i];
    *pp = p;
    *po = o;
    return 0;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    uint32_t p, o;
    if (parse(state, &p, &o) < 0)
        return -1;
    int n = near_dist(KEY(p, o));
    if (n >= 0) {
        walk(p, o, n, 0);
    } else if (is_far(KEY(p, o))) {
        /* Every move leads to distance 10 or 11; take one out of the table. */
        for (int f = 0, done = 0; f < 3 && !done; f++) {
            uint32_t q = p, r = o;
            for (int t = 0; t < 3; t++) {
                q = rubik_pm[q][f];
                r = rubik_om[r][f];
                if (!is_far(KEY(q, r))) {
                    path[0] = (uint8_t) (3 * f + t);
                    search(q, r, 1, 5, 11, f);
                    done = 1;
                    break;
                }
            }
        }
        n = 11;
    } else {
        for (n = 6; !search(p, o, 0, n - 5, n, 3); n++)
            ;
    }

    /* Output: move names separated by single spaces, then the NUL. */
    static const char name[9][3] = {"R",  "R2", "R'", "B", "B2",
                                    "B'", "D",  "D2", "D'"};
    size_t need = 1;
    for (int i = 0; i < n; i++)
        need += (size_t) ((name[path[i]][1] ? 2 : 1) + (i > 0));
    if (need > cap) {
        if (cap)
            out[0] = '\0';
        return -2;
    }
    char *w = out;
    for (int i = 0; i < n; i++) {
        const char *m = name[path[i]];
        if (i)
            *w++ = ' ';
        *w++ = m[0];
        if (m[1])
            *w++ = m[1];
    }
    *w = '\0';
    return n;
}
