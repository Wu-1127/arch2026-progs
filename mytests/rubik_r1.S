# Step r1 of the rubik assembly, measured by mytests/steps.c; not graded.
# The submitted src/rubik/rubik.S with the unrolled search of rubik_near
# replaced by a plain binary search loop, and the coordinates kept as
# indices p and o instead of row addresses: every row access computes
# table + 8 * index.

# The rest follows src/rubik/rubik.S; see its header for the method.

    .include "src/rubik/rubik_tab.inc"

    .section .rodata
    .align  1
# Lehmer weights 6!, 5!, ..., 1!
weights:
    .half   720, 120, 24, 6, 2, 1
# Move names, two bytes each, NUL padded: R R2 R' B B2 B' D D2 D'
names:
    .ascii  "R\0R2R'B\0B2B'D\0D2D'"

    .equ    PATH, 0                 # path[12]
    .equ    OUT, 12
    .equ    CAP, 16
    .equ    ROOTQ, 20               # root rows across the searches
    .equ    ROOTR, 24
    .equ    LVL, 32                 # level frames, 32 bytes each, 6 levels
    .equ    L_BQ, 0                 # base row addresses of the level's node
    .equ    L_BR, 4
    .equ    L_Q, 8                  # saved child state while a level deeper
    .equ    L_R, 12
    .equ    L_F, 16
    .equ    L_T, 20
    .equ    L_LAST, 24
    .equ    SAVE, 224
    .equ    FRAME, 288

# t0 = key = p << 10 | o of the rows in s1, s2
.macro KEY
    slli    t0, s1, 10
    or      t0, t0, s2
.endm

# One step of the binary search of rubik_near: t4 = address of the last
# entry known to be <= t3; try the entry \bytes further.
.macro NSTEP bytes
.if \bytes < 2048
    lw      t1, \bytes(t4)
    bltu    t3, t1, 1f
    addi    t4, t4, \bytes
1:
.else
    li      t2, \bytes
    add     t2, t4, t2
    lw      t1, 0(t2)
    bltu    t3, t1, 1f
    mv      t4, t2
1:
.endif
.endm

# Quarter turn of face s3 (byte offset) on the rows s1, s2.
.macro TURN
    slli    t0, s1, 3
    add     t0, t0, s8
    add     t0, t0, s3
    lhu     s1, 0(t0)
    slli    t1, s2, 3
    add     t1, t1, s9
    add     t1, t1, s3
    lhu     s2, 0(t1)
.endm

    .text

    .globl  rubik_r1
    .type   rubik_r1, @function
    .align  2
rubik_r1:
    addi    sp, sp, -FRAME
    sw      ra, SAVE+0(sp)
    sw      s0, SAVE+4(sp)
    sw      s1, SAVE+8(sp)
    sw      s2, SAVE+12(sp)
    sw      s3, SAVE+16(sp)
    sw      s4, SAVE+20(sp)
    sw      s5, SAVE+24(sp)
    sw      s6, SAVE+28(sp)
    sw      s7, SAVE+32(sp)
    sw      s8, SAVE+36(sp)
    sw      s9, SAVE+40(sp)
    sw      s10, SAVE+44(sp)
    sw      s11, SAVE+48(sp)
    sw      a1, OUT(sp)
    sw      a2, CAP(sp)
    addi    s0, sp, PATH
    la      s8, rubik_pm
    la      s9, rubik_om
    la      s10, rubik_near

# Parse: seven distinct cubies '1'..'7', seven twists '1'..'3' summing to a
# multiple of 3, then the NUL. A NUL never passes a digit test, so nothing
# past the end of a short string is read.
    li      t5, 0                   # cubies seen (bit mask)
    li      t2, 0
    li      t6, 7
parse_perm:
    add     t0, a0, t2
    lbu     t0, 0(t0)
    addi    t0, t0, -'1'
    bgeu    t0, t6, invalid
    li      t1, 1
    sll     t1, t1, t0
    and     t3, t5, t1
    bnez    t3, invalid
    or      t5, t5, t1
    addi    t2, t2, 1
    bne     t2, t6, parse_perm

    li      t4, 0                   # sum of the twists
    li      t5, 0                   # o
    li      t6, 3
parse_twist:
    add     t0, a0, t2
    lbu     t0, 0(t0)
    addi    t0, t0, -'1'
    bgeu    t0, t6, invalid
    add     t4, t4, t0
    li      t1, 13
    beq     t2, t1, 1f              # the seventh twist is implied
    slli    t1, t5, 1
    add     t5, t5, t1              # o * 3
    add     t5, t5, t0
1:
    addi    t2, t2, 1
    li      t1, 14
    bne     t2, t1, parse_twist
    lbu     t0, 14(a0)
    bnez    t0, invalid
    li      t0, 0x1249              # bits 0, 3, 6, 9, 12: multiples of 3
    srl     t0, t0, t4
    andi    t0, t0, 1
    beqz    t0, invalid

# Lehmer rank: p += weight[i] for each later cubie smaller than cubie i.
    li      t3, 0                   # p
    li      t2, 0                   # i
    la      t6, weights
rank_i:
    add     t0, a0, t2
    lbu     t0, 0(t0)
    slli    t1, t2, 1
    add     t1, t1, t6
    lhu     t1, 0(t1)               # weight[i]
    addi    a3, t2, 1               # j
rank_j:
    add     a4, a0, a3
    lbu     a4, 0(a4)
    bgeu    a4, t0, 1f
    add     t3, t3, t1
1:
    addi    a3, a3, 1
    li      a4, 7
    bne     a3, a4, rank_j
    addi    t2, t2, 1
    li      a4, 6
    bne     t2, a4, rank_i

    mv      s1, t3
    mv      s2, t5

# Within five moves: walk down rubik_near.
    jal     t6, near
    bltz    a3, not_near
    mv      s11, a3
    mv      a2, a3
    mv      a6, s0
    jal     ra, walk
    j       format

not_near:
    jal     t6, far
    beqz    a3, iddfs
# Distance 11: the first move that leaves rubik_far reaches distance 10.
    li      s11, 11
    mv      a0, s1
    mv      a1, s2
    li      s3, 0
far_face:
    mv      s1, a0
    mv      s2, a1
    li      s4, 0
far_turn:
    TURN
    jal     t6, far
    beqz    a3, far_found
    addi    s4, s4, 1
    li      t0, 3
    bne     s4, t0, far_turn
    addi    s3, s3, 2
    j       far_face
far_found:
    srli    t0, s3, 1
    add     t0, t0, s3              # 3 * f
    add     t0, t0, s4
    sb      t0, 0(s0)
    mv      a0, s1
    mv      a1, s2
    mv      s6, s3
    li      s7, 9                   # bound 11, children at g = 2
    addi    a6, s0, 1
    jal     ra, dfs
    j       format

# Distances 6 to 10: a search of n - 5 moves for each n in turn.
iddfs:
    li      s11, 6
    sw      s1, ROOTQ(sp)
    sw      s2, ROOTR(sp)
iddfs_next:
    lw      a0, ROOTQ(sp)
    lw      a1, ROOTR(sp)
    li      s6, 6                   # no last face
    addi    s7, s11, -1
    mv      a6, s0
    jal     ra, dfs
    bnez    a0, format
    addi    s11, s11, 1
    j       iddfs_next

# Output: names separated by single spaces, then the NUL. The length is
# 2 * n (n names, n - 1 spaces, the NUL) plus one per two-letter name, or 1
# for the solved cube.
format:
    lw      a1, OUT(sp)
    lw      a2, CAP(sp)
    la      t6, names
    li      t2, 1
    beqz    s11, fmt_check
    slli    t2, s11, 1
    li      t3, 0
fmt_len:
    add     t0, s0, t3
    lbu     t0, 0(t0)
    slli    t0, t0, 1
    add     t0, t0, t6
    lbu     t0, 1(t0)
    beqz    t0, 1f
    addi    t2, t2, 1
1:
    addi    t3, t3, 1
    bne     t3, s11, fmt_len
fmt_check:
    bgeu    a2, t2, fmt_write
    li      a0, -2
    beqz    a2, done
    sb      zero, 0(a1)
    j       done
fmt_write:
    li      t3, 0
    li      t4, ' '
    beqz    s11, fmt_end
fmt_move:
    add     t0, s0, t3
    lbu     t0, 0(t0)
    slli    t0, t0, 1
    add     t0, t0, t6
    lbu     t1, 0(t0)
    sb      t1, 0(a1)
    addi    a1, a1, 1
    lbu     t1, 1(t0)
    beqz    t1, 1f
    sb      t1, 0(a1)
    addi    a1, a1, 1
1:
    addi    t3, t3, 1
    beq     t3, s11, fmt_end
    sb      t4, 0(a1)
    addi    a1, a1, 1
    j       fmt_move
fmt_end:
    sb      zero, 0(a1)
    mv      a0, s11
    j       done

invalid:
    li      a0, -1
done:
    lw      ra, SAVE+0(sp)
    lw      s0, SAVE+4(sp)
    lw      s1, SAVE+8(sp)
    lw      s2, SAVE+12(sp)
    lw      s3, SAVE+16(sp)
    lw      s4, SAVE+20(sp)
    lw      s5, SAVE+24(sp)
    lw      s6, SAVE+28(sp)
    lw      s7, SAVE+32(sp)
    lw      s8, SAVE+36(sp)
    lw      s9, SAVE+40(sp)
    lw      s10, SAVE+44(sp)
    lw      s11, SAVE+48(sp)
    addi    sp, sp, FRAME
    ret
    .size   rubik_r1, .-rubik_r1

# near: a3 = distance of the state s1, s2 if it is within five moves, else
# -1. Plain binary search loop for the last entry <= key << 3 | 7.
    .type   near, @function
near:
    KEY
    slli    t3, t0, 3
    ori     t3, t3, 7
    mv      t4, s10
    li      t5, RUBIK_NNEAR         # entries left, the first at t4
near_loop:
    srli    t2, t5, 1
    beqz    t2, near_end
    slli    t1, t2, 2
    add     t1, t1, t4
    lw      a3, 0(t1)
    sub     t5, t5, t2
    bltu    t3, a3, near_loop
    mv      t4, t1
    j       near_loop
near_end:
    lw      t1, 0(t4)
    srli    t2, t1, 3
    li      a3, -1
    bne     t2, t0, 1f
    andi    a3, t1, 7
1:
    jr      t6
    .size   near, .-near

# far: a3 = 1 if the state s1, s2 is at distance 11, else 0.
    .type   far, @function
far:
    KEY
    la      t4, rubik_far
    li      t5, RUBIK_NFAR          # entries left, the first at t4
far_loop:
    srli    t2, t5, 1
    beqz    t2, far_end
    slli    t3, t2, 2
    add     t3, t3, t4
    lw      t1, 0(t3)
    sub     t5, t5, t2
    bltu    t0, t1, far_loop
    mv      t4, t3
    j       far_loop
far_end:
    lw      t1, 0(t4)
    sub     t1, t1, t0
    seqz    a3, t1
    jr      t6
    .size   far, .-far

# walk: append the a2 moves that bring the state s1, s2 (within five moves,
# at distance a2) to solved, at a6. Some move always leads one closer.
# Returns a0 = 1 through ra; clobbers a0, a1, s1-s4, t0-t6, a3.
    .type   walk, @function
walk:
    beqz    a2, walk_end
    mv      a0, s1
    mv      a1, s2
    addi    a2, a2, -1
    li      s3, 0
walk_face:
    mv      s1, a0
    mv      s2, a1
    li      s4, 0
walk_turn:
    TURN
    jal     t6, near
    beq     a3, a2, walk_step
    addi    s4, s4, 1
    li      t0, 3
    bne     s4, t0, walk_turn
    addi    s3, s3, 2
    j       walk_face
walk_step:
    srli    t0, s3, 1
    add     t0, t0, s3
    add     t0, t0, s4
    sb      t0, 0(a6)
    addi    a6, a6, 1
    j       walk
walk_end:
    li      a0, 1
    ret
    .size   walk, .-walk

# dfs: search from the rows a0, a1 for a state of rubik_near; s6 = the last
# face (byte offset, 6 for none), s7 = slack of the first children, a6 = their
# path slot. Returns a0 = 1 with the path filled (through walk), or 0.
    .type   dfs, @function
dfs:
    addi    s5, sp, LVL
    mv      a7, s5                  # the root frame
    sw      a0, L_BQ(s5)
    sw      a1, L_BR(s5)
    li      s3, -2
dfs_face:
    addi    s3, s3, 2
    li      t0, 6
    beq     s3, t0, dfs_up
    beq     s3, s6, dfs_face
    lw      s1, L_BQ(s5)
    lw      s2, L_BR(s5)
    li      s4, 0
dfs_turn:
    li      t0, 3
    beq     s4, t0, dfs_face
    addi    s4, s4, 1
    TURN
    slli    t2, s1, 3
    add     t2, t2, s8
    lhu     t2, 6(t2)               # distance of p alone
    slli    t3, s2, 3
    add     t3, t3, s9
    lhu     t3, 6(t3)               # distance of o alone
    bgeu    t2, t3, 1f
    mv      t2, t3
1:
    bltu    s7, t2, dfs_turn        # g + h > bound
    srli    t0, s3, 1
    add     t0, t0, s3
    add     t0, t0, s4
    addi    t0, t0, -1              # move = 3 * f + turns - 1
    sb      t0, 0(a6)
    li      t0, 5
    beq     s7, t0, dfs_leaf
    sw      s1, L_Q(s5)             # one level down
    sw      s2, L_R(s5)
    sw      s3, L_F(s5)
    sw      s4, L_T(s5)
    sw      s6, L_LAST(s5)
    mv      s6, s3
    addi    s5, s5, 32
    sw      s1, L_BQ(s5)
    sw      s2, L_BR(s5)
    addi    s7, s7, -1
    addi    a6, a6, 1
    li      s3, -2
    j       dfs_face
dfs_leaf:
    jal     t6, near
    bltz    a3, dfs_turn
    mv      a2, a3
    addi    a6, a6, 1
    j       walk                    # returns 1 to the caller of dfs
dfs_up:
    beq     s5, a7, dfs_fail
    addi    s5, s5, -32
    lw      s1, L_Q(s5)
    lw      s2, L_R(s5)
    lw      s3, L_F(s5)
    lw      s4, L_T(s5)
    lw      s6, L_LAST(s5)
    addi    s7, s7, 1
    addi    a6, a6, -1
    j       dfs_turn
dfs_fail:
    li      a0, 0
    ret
    .size   dfs, .-dfs
