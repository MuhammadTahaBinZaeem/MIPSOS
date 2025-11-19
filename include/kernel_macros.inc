# Common register save/restore helpers for the MIPS OS steps.

    .equ CTX_AT,      0
    .equ CTX_V0,      4
    .equ CTX_V1,      8
    .equ CTX_A0,     12
    .equ CTX_A1,     16
    .equ CTX_A2,     20
    .equ CTX_A3,     24
    .equ CTX_T0,     28
    .equ CTX_T1,     32
    .equ CTX_T2,     36
    .equ CTX_T3,     40
    .equ CTX_T4,     44
    .equ CTX_T5,     48
    .equ CTX_T6,     52
    .equ CTX_T7,     56
    .equ CTX_S0,     60
    .equ CTX_S1,     64
    .equ CTX_S2,     68
    .equ CTX_S3,     72
    .equ CTX_S4,     76
    .equ CTX_S5,     80
    .equ CTX_S6,     84
    .equ CTX_S7,     88
    .equ CTX_T8,     92
    .equ CTX_T9,     96
    .equ CTX_GP,    100
    .equ CTX_SP,    104
    .equ CTX_FP,    108
    .equ CTX_RA,    112
    .equ CTX_HI,    116
    .equ CTX_LO,    120
    .equ CTX_STATUS,124
    .equ CTX_EPC,   128
    .equ CTX_SIZE,  132

    .macro SAVE_CONTEXT base
        sw      $at,    CTX_AT(\base)
        sw      $v0,    CTX_V0(\base)
        sw      $v1,    CTX_V1(\base)
        sw      $a0,    CTX_A0(\base)
        sw      $a1,    CTX_A1(\base)
        sw      $a2,    CTX_A2(\base)
        sw      $a3,    CTX_A3(\base)
        sw      $t0,    CTX_T0(\base)
        sw      $t1,    CTX_T1(\base)
        sw      $t2,    CTX_T2(\base)
        sw      $t3,    CTX_T3(\base)
        sw      $t4,    CTX_T4(\base)
        sw      $t5,    CTX_T5(\base)
        sw      $t6,    CTX_T6(\base)
        sw      $t7,    CTX_T7(\base)
        sw      $s0,    CTX_S0(\base)
        sw      $s1,    CTX_S1(\base)
        sw      $s2,    CTX_S2(\base)
        sw      $s3,    CTX_S3(\base)
        sw      $s4,    CTX_S4(\base)
        sw      $s5,    CTX_S5(\base)
        sw      $s6,    CTX_S6(\base)
        sw      $s7,    CTX_S7(\base)
        sw      $t8,    CTX_T8(\base)
        sw      $t9,    CTX_T9(\base)
        sw      $gp,    CTX_GP(\base)
        sw      $sp,    CTX_SP(\base)
        sw      $fp,    CTX_FP(\base)
        sw      $ra,    CTX_RA(\base)
        mfhi    $k0
        sw      $k0,    CTX_HI(\base)
        mflo    $k0
        sw      $k0,    CTX_LO(\base)
        mfc0    $k0, $12
        sw      $k0,    CTX_STATUS(\base)
        mfc0    $k0, $14
        sw      $k0,    CTX_EPC(\base)
    .endm

    .macro RESTORE_CONTEXT base
        lw      $at,    CTX_AT(\base)
        lw      $v0,    CTX_V0(\base)
        lw      $v1,    CTX_V1(\base)
        lw      $a0,    CTX_A0(\base)
        lw      $a1,    CTX_A1(\base)
        lw      $a2,    CTX_A2(\base)
        lw      $a3,    CTX_A3(\base)
        lw      $t0,    CTX_T0(\base)
        lw      $t1,    CTX_T1(\base)
        lw      $t2,    CTX_T2(\base)
        lw      $t3,    CTX_T3(\base)
        lw      $t4,    CTX_T4(\base)
        lw      $t5,    CTX_T5(\base)
        lw      $t6,    CTX_T6(\base)
        lw      $t7,    CTX_T7(\base)
        lw      $s0,    CTX_S0(\base)
        lw      $s1,    CTX_S1(\base)
        lw      $s2,    CTX_S2(\base)
        lw      $s3,    CTX_S3(\base)
        lw      $s4,    CTX_S4(\base)
        lw      $s5,    CTX_S5(\base)
        lw      $s6,    CTX_S6(\base)
        lw      $s7,    CTX_S7(\base)
        lw      $t8,    CTX_T8(\base)
        lw      $t9,    CTX_T9(\base)
        lw      $gp,    CTX_GP(\base)
        lw      $sp,    CTX_SP(\base)
        lw      $fp,    CTX_FP(\base)
        lw      $ra,    CTX_RA(\base)
        lw      $k0,    CTX_HI(\base)
        mthi    $k0
        lw      $k0,    CTX_LO(\base)
        mtlo    $k0
        lw      $k0,    CTX_STATUS(\base)
        mtc0    $k0, $12
        lw      $k0,    CTX_EPC(\base)
        mtc0    $k0, $14
    .endm
