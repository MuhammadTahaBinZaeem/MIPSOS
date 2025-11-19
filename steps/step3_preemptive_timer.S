# Step 3 – Timer Interrupt & Preemptive Scheduling
# A periodic timer interrupt preempts the currently running task and the
# kernel performs a round-robin context switch without user cooperation.

    .set noreorder
    .set noat

    .include "../include/kernel_macros.inc"

    .equ MMIO_CONSOLE,      0xffff0000
    .equ TIMER_INTERVAL,    0xffff0010
    .equ TIMER_CONTROL,     0xffff0014

    .equ STACK_SIZE,        512
    .equ NUM_TASKS,         2

    .equ CAUSE_EXCCODE_MASK, 0x0000007c
    .equ CAUSE_IP_TIMER,     0x00000400      # Using IP[2] as timer bit
    .equ STATUS_IE_MASK,     0x00000001

    .text
    .globl _start
_start:
    la      $sp, kernel_stack_top
    addiu   $sp, $sp, -32
    jal     kmain
    nop

kmain:
    la      $t0, pcb0
    la      $t1, stack0_top
    sw      $t1, CTX_SP($t0)
    la      $t2, task0_start
    sw      $t2, CTX_EPC($t0)
    sw      $zero, CTX_STATUS($t0)

    la      $t0, pcb1
    la      $t1, stack1_top
    sw      $t1, CTX_SP($t0)
    la      $t2, task1_start
    sw      $t2, CTX_EPC($t0)
    sw      $zero, CTX_STATUS($t0)

    sw      $zero, current_task_index
    la      $t0, pcb0
    sw      $t0, current_pcb_ptr

    jal     timer_init
    nop

    jal     scheduler_launch_first
    nop

halt:
    j       halt
    nop

scheduler_launch_first:
    lw      $t0, current_pcb_ptr
    RESTORE_CONTEXT $t0
    li      $t1, STATUS_IE_MASK
    mtc0    $t1, $12                  # Enable interrupts, run in kernel mode
    eret

# ----------------------------------------------------------------------------
# Timer configuration
# ----------------------------------------------------------------------------
timer_init:
    li      $t0, 5000                 # Arbitrary tick interval
    sw      $t0, TIMER_INTERVAL
    li      $t1, 1
    sw      $t1, TIMER_CONTROL        # Start timer
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# Exception handler – handles timer interrupt preemption.
# ----------------------------------------------------------------------------
    .ktext 0x80000180
_exception_entry:
    la      $sp, kernel_stack_top
    addiu   $sp, $sp, -128

    la      $k1, current_pcb_ptr
    lw      $k1, 0($k1)
    SAVE_CONTEXT $k1

    mfc0    $t0, $13                   # Cause register
    andi    $t2, $t0, CAUSE_IP_TIMER
    beq     $t2, $zero, unknown_interrupt
    nop

    sw      $zero, TIMER_CONTROL       # Acknowledge timer (auto-reload)

    jal     scheduler_pick_next
    nop

    move    $k1, $v0
    RESTORE_CONTEXT $k1
    li      $t1, STATUS_IE_MASK
    mtc0    $t1, $12
    eret

unknown_interrupt:
    j       unknown_interrupt
    nop

# ----------------------------------------------------------------------------
# Scheduler helper – identical to step 2.
# ----------------------------------------------------------------------------
scheduler_pick_next:
    la      $t0, current_task_index
    lw      $t1, 0($t0)
    addiu   $t1, $t1, 1
    li      $t2, NUM_TASKS
    slt     $t3, $t1, $t2
    bne     $t3, $zero, 1f
    nop
    move    $t1, $zero
1:
    sw      $t1, 0($t0)

    la      $t4, task_pcb_table
    sll     $t5, $t1, 2
    addu    $t4, $t4, $t5
    lw      $v0, 0($t4)
    sw      $v0, current_pcb_ptr
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# User tasks – busy loops that never voluntarily yield.
# ----------------------------------------------------------------------------
    .text

task0_start:
    la      $t0, MMIO_CONSOLE
loop0:
    li      $t1, 'A'
    sb      $t1, 0($t0)
    addiu   $t2, $zero, 1000
1:
    addiu   $t2, $t2, -1
    bgtz    $t2, 1b
    nop
    j       loop0
    nop

task1_start:
    la      $t0, MMIO_CONSOLE
loop1:
    li      $t1, 'B'
    sb      $t1, 0($t0)
    addiu   $t2, $zero, 1000
1:
    addiu   $t2, $t2, -1
    bgtz    $t2, 1b
    nop
    j       loop1
    nop

    .data
    .balign 16
current_task_index:
    .word   0
current_pcb_ptr:
    .word   0

task_pcb_table:
    .word   pcb0
    .word   pcb1

    .balign 16
kernel_stack:
    .space  1024
kernel_stack_top:

    .balign 16
stack0:
    .space  STACK_SIZE
stack0_top:

    .balign 16
stack1:
    .space  STACK_SIZE
stack1_top:

pcb0:
    .space  CTX_SIZE
pcb1:
    .space  CTX_SIZE
