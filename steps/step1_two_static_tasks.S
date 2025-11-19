# Step 1 – Two Static Tasks (Cooperative via manual kernel calls)
# The kernel manually switches between two statically defined tasks.

    .set noreorder
    .set noat

    .equ MMIO_CONSOLE, 0xffff0000
    .equ STACK_SIZE,   512

    .text
    .globl _start
_start:
    la      $sp, kernel_stack_top
    addiu   $sp, $sp, -16
    j       kmain
    nop

kmain:
    la      $s0, stack0_top              # Cached task stack pointers
    la      $s1, stack1_top

manual_schedule_loop:
    move    $sp, $s0                     # Activate task 0 stack
    jal     task0_start                  # Run task 0 once
    move    $s0, $sp                     # Save its stack pointer (not used yet)

    move    $sp, $s1
    jal     task1_start
    move    $s1, $sp

    j       manual_schedule_loop         # Repeat forever
    nop

# ----------------------------------------------------------------------------
# Task 0 - prints 'A' once whenever scheduled.
# ----------------------------------------------------------------------------
task0_start:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)

    la      $t0, MMIO_CONSOLE
    li      $t1, 'A'
    sb      $t1, 0($t0)

    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# Task 1 - prints 'B' once whenever scheduled.
# ----------------------------------------------------------------------------
task1_start:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)

    la      $t0, MMIO_CONSOLE
    li      $t1, 'B'
    sb      $t1, 0($t0)

    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop

    .data
    .balign 16
kernel_stack:
    .space  STACK_SIZE
kernel_stack_top:

    .balign 16
stack0:
    .space  STACK_SIZE
stack0_top:

    .balign 16
stack1:
    .space  STACK_SIZE
stack1_top:
