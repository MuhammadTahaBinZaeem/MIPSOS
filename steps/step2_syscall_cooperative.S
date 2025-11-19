# Step 2 – Cooperative Task Switching via syscall yield
# Two user tasks invoke syscall 1 to yield control. The kernel saves the
# context of the running task and restores the context of the next task.

    .set noreorder
    .set noat

    .include "../include/kernel_macros.inc"

    .equ MMIO_CONSOLE,    0xffff0000
    .equ STACK_SIZE,      512
    .equ NUM_TASKS,       2
    .equ SYSCALL_YIELD,   1

    .equ PCB_CONTEXT,     0
    .equ PCB_SIZE,        CTX_SIZE

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

    jal     scheduler_launch_first
    nop

hang:
    j       hang
    nop

scheduler_launch_first:
    lw      $t0, current_pcb_ptr
    RESTORE_CONTEXT $t0
    eret

# ----------------------------------------------------------------------------
# Exception handler (covers syscall used for cooperative yield)
# ----------------------------------------------------------------------------
    .ktext 0x80000180
_exception_entry:
    la      $sp, kernel_stack_top
    addiu   $sp, $sp, -128

    la      $k1, current_pcb_ptr
    lw      $k1, 0($k1)
    SAVE_CONTEXT $k1

    mfc0    $t0, $13                   # Cause register
    andi    $t0, $t0, 0x3c
    srl     $t0, $t0, 2
    li      $t1, 8                     # Exception code for syscall
    bne     $t0, $t1, unknown_exception
    nop

    lw      $t2, CTX_V0($k1)           # syscall number
    li      $t3, SYSCALL_YIELD
    bne     $t2, $t3, unknown_syscall
    nop

handle_yield:
    lw      $t4, CTX_EPC($k1)
    addiu   $t4, $t4, 4
    sw      $t4, CTX_EPC($k1)

    jal     scheduler_pick_next
    nop

    move    $k1, $v0                   # $v0 = pointer to next PCB
    RESTORE_CONTEXT $k1
    eret

unknown_syscall:
unknown_exception:
    j       unknown_syscall             # Trap forever for debugging
    nop

# ----------------------------------------------------------------------------
# Round-robin scheduler over two tasks.
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
# User tasks
# ----------------------------------------------------------------------------
    .text

task0_start:
    la      $t0, MMIO_CONSOLE
1:
    li      $t1, 'A'
    sb      $t1, 0($t0)
    li      $v0, SYSCALL_YIELD
    syscall
    j       1b
    nop

task1_start:
    la      $t0, MMIO_CONSOLE
1:
    li      $t1, 'B'
    sb      $t1, 0($t0)
    li      $v0, SYSCALL_YIELD
    syscall
    j       1b
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
    .space  PCB_SIZE
pcb1:
    .space  PCB_SIZE
