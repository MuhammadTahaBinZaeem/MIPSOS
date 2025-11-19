# Step 4 – Expand to 4 Tasks, Priorities & States
# Scheduler now tracks READY/RUNNING/BLOCKED states and honours priorities.

    .set noreorder
    .set noat

    .include "../include/kernel_macros.inc"

    .equ MMIO_CONSOLE,      0xffff0000
    .equ TIMER_INTERVAL,    0xffff0010
    .equ TIMER_CONTROL,     0xffff0014

    .equ STACK_SIZE,        512
    .equ NUM_TASKS,         4

    .equ TASK_READY,        0
    .equ TASK_RUNNING,      1
    .equ TASK_BLOCKED,      2

    .equ PCB_PRIORITY,      CTX_SIZE
    .equ PCB_STATE,         CTX_SIZE + 4
    .equ PCB_ID,            CTX_SIZE + 8
    .equ PCB_SIZE,          CTX_SIZE + 12

    .equ STATUS_IE_MASK,    0x00000001
    .equ CAUSE_IP_TIMER,    0x00000400

    .text
    .globl _start
_start:
    la      $sp, kernel_stack_top
    addiu   $sp, $sp, -32
    jal     kmain
    nop

kmain:
    li      $t7, 0
    la      $t6, task_init_table
    la      $t5, task_pcb_ptrs

init_loop:
    slti    $t8, $t7, NUM_TASKS
    beq     $t8, $zero, init_done
    nop

    lw      $t0, 0($t6)               # entry point
    lw      $t1, 4($t6)               # stack top
    lw      $t2, 8($t6)               # priority
    lw      $t3, 12($t6)              # PCB base

    sw      $t1, CTX_SP($t3)
    sw      $t0, CTX_EPC($t3)
    sw      $zero, CTX_STATUS($t3)
    sw      $t2, PCB_PRIORITY($t3)
    li      $t4, TASK_READY
    sw      $t4, PCB_STATE($t3)
    sw      $t7, PCB_ID($t3)

    sw      $t3, 0($t5)

    addiu   $t6, $t6, 16
    addiu   $t5, $t5, 4
    addiu   $t7, $t7, 1
    j       init_loop
    nop

init_done:
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
    li      $t1, TASK_RUNNING
    sw      $t1, PCB_STATE($t0)
    RESTORE_CONTEXT $t0
    li      $t2, STATUS_IE_MASK
    mtc0    $t2, $12
    eret

# ----------------------------------------------------------------------------
# Timer configuration reused from step 3
# ----------------------------------------------------------------------------
timer_init:
    li      $t0, 5000
    sw      $t0, TIMER_INTERVAL
    li      $t1, 1
    sw      $t1, TIMER_CONTROL
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# Interrupt handler updates task states & priorities
# ----------------------------------------------------------------------------
    .ktext 0x80000180
_exception_entry:
    la      $sp, kernel_stack_top
    addiu   $sp, $sp, -128

    la      $k1, current_pcb_ptr
    lw      $k1, 0($k1)
    SAVE_CONTEXT $k1
    li      $t0, TASK_READY
    sw      $t0, PCB_STATE($k1)

    sw      $zero, TIMER_CONTROL       # Ack timer

    jal     scheduler_pick_next
    nop

    move    $k1, $v0
    li      $t1, TASK_RUNNING
    sw      $t1, PCB_STATE($k1)
    RESTORE_CONTEXT $k1
    li      $t2, STATUS_IE_MASK
    mtc0    $t2, $12
    eret

# ----------------------------------------------------------------------------
# Scheduler with priority and round-robin tie breaker
# ----------------------------------------------------------------------------
scheduler_pick_next:
    lw      $t0, current_task_index
    addiu   $t1, $t0, 1
    li      $t2, NUM_TASKS
    slt     $t3, $t1, $t2
    bne     $t3, $zero, 1f
    nop
    move    $t1, $zero
1:
    move    $t4, $t1                    # start index
    li      $t5, -1                     # best priority
    li      $t6, -1                     # best index
    li      $t7, 0                      # loop counter

scan_loop:
    slti    $t8, $t7, NUM_TASKS
    beq     $t8, $zero, scan_done
    nop

    addu    $t9, $t4, $t7
    li      $s0, NUM_TASKS
    slt     $s1, $t9, $s0
    bne     $s1, $zero, 2f
    nop
    addiu   $t9, $t9, -NUM_TASKS
2:
    la      $s2, task_pcb_ptrs
    sll     $s3, $t9, 2
    addu    $s2, $s2, $s3
    lw      $s4, 0($s2)
    lw      $s5, PCB_STATE($s4)
    li      $s6, TASK_READY
    bne     $s5, $s6, skip_entry
    nop

    lw      $s7, PCB_PRIORITY($s4)
    slt     $s1, $t5, $s7
    beq     $s1, $zero, skip_entry
    nop
    move    $t5, $s7
    move    $t6, $t9
    move    $v0, $s4

skip_entry:
    addiu   $t7, $t7, 1
    j       scan_loop
    nop

scan_done:
    slti    $t8, $t6, 0
    beq     $t8, $zero, have_choice
    nop
    # fallback: keep current task pointer
    lw      $v0, current_pcb_ptr
    jr      $ra
    nop

have_choice:
    sw      $t6, current_task_index
    sw      $v0, current_pcb_ptr
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# Tasks C, D added with different priorities
# ----------------------------------------------------------------------------
    .text

task0_start:
    li      $a0, 'A'
    j       character_printer
    nop

task1_start:
    li      $a0, 'B'
    j       character_printer
    nop

task2_start:
    li      $a0, 'C'
    j       character_printer
    nop

task3_start:
    li      $a0, 'D'
    j       character_printer
    nop

character_printer:
    la      $t0, MMIO_CONSOLE
print_loop:
    sb      $a0, 0($t0)
    addiu   $t1, $zero, 5000
wait_loop:
    addiu   $t1, $t1, -1
    bgtz    $t1, wait_loop
    nop
    j       print_loop
    nop

    .data
    .balign 16
current_task_index:
    .word   0
current_pcb_ptr:
    .word   0

# entry, stack, priority, pcb
    .balign 16
task_init_table:
    .word   task0_start, stack0_top, 3, pcb0
    .word   task1_start, stack1_top, 2, pcb1
    .word   task2_start, stack2_top, 1, pcb2
    .word   task3_start, stack3_top, 0, pcb3

    .balign 16
task_pcb_ptrs:
    .word   0,0,0,0

    .balign 16
kernel_stack:
    .space  1024
kernel_stack_top:

stack0:
    .space  STACK_SIZE
stack0_top:
stack1:
    .space  STACK_SIZE
stack1_top:
stack2:
    .space  STACK_SIZE
stack2_top:
stack3:
    .space  STACK_SIZE
stack3_top:

pcb0:
    .space  PCB_SIZE
pcb1:
    .space  PCB_SIZE
pcb2:
    .space  PCB_SIZE
pcb3:
    .space  PCB_SIZE
