# Step 5 – Syscall API Expansion (write, yield, sleep, get_ticks)

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
    .equ PCB_WAKE_TICK,     CTX_SIZE + 12
    .equ PCB_SIZE,          CTX_SIZE + 16

    .equ STATUS_IE_MASK,    0x00000001
    .equ CAUSE_IP_TIMER,    0x00000400
    .equ CAUSE_EXCCODE_MASK,0x0000007c
    .equ CAUSE_EXCCODE_SHIFT,2
    .equ EXCCODE_SYSCALL,   8

    .equ SYSCALL_WRITE_CHAR,0
    .equ SYSCALL_YIELD,     1
    .equ SYSCALL_SLEEP,     2
    .equ SYSCALL_GET_TICKS, 3

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

    lw      $t0, 0($t6)               # entry
    lw      $t1, 4($t6)               # stack
    lw      $t2, 8($t6)               # priority
    lw      $t3, 12($t6)              # pcb

    sw      $t1, CTX_SP($t3)
    sw      $t0, CTX_EPC($t3)
    sw      $zero, CTX_STATUS($t3)
    sw      $t2, PCB_PRIORITY($t3)
    li      $t4, TASK_READY
    sw      $t4, PCB_STATE($t3)
    sw      $t7, PCB_ID($t3)
    sw      $zero, PCB_WAKE_TICK($t3)

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
    sw      $zero, system_ticks

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
# Timer init
# ----------------------------------------------------------------------------
timer_init:
    li      $t0, 5000
    sw      $t0, TIMER_INTERVAL
    li      $t1, 1
    sw      $t1, TIMER_CONTROL
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# Exception handler – handles timer + syscall dispatch.
# ----------------------------------------------------------------------------
    .ktext 0x80000180
_exception_entry:
    la      $sp, kernel_stack_top
    addiu   $sp, $sp, -128

    la      $k1, current_pcb_ptr
    lw      $k1, 0($k1)
    SAVE_CONTEXT $k1

    mfc0    $t0, $13                   # Cause
    andi    $t1, $t0, CAUSE_IP_TIMER
    bne     $t1, $zero, handle_timer
    nop

    andi    $t2, $t0, CAUSE_EXCCODE_MASK
    srl     $t2, $t2, CAUSE_EXCCODE_SHIFT
    li      $t3, EXCCODE_SYSCALL
    beq     $t2, $t3, handle_syscall
    nop

    j       fault_halt
    nop

handle_timer:
    sw      $zero, TIMER_CONTROL
    lw      $t4, system_ticks
    addiu   $t4, $t4, 1
    sw      $t4, system_ticks

    li      $t5, TASK_READY
    sw      $t5, PCB_STATE($k1)

    jal     wake_sleepers
    nop

    jal     scheduler_pick_next
    nop

    move    $k1, $v0
    li      $t6, TASK_RUNNING
    sw      $t6, PCB_STATE($k1)
    RESTORE_CONTEXT $k1
    li      $t7, STATUS_IE_MASK
    mtc0    $t7, $12
    eret

handle_syscall:
    lw      $t8, CTX_V0($k1)
    li      $t9, SYSCALL_WRITE_CHAR
    beq     $t8, $t9, sys_write_char
    nop

    li      $t9, SYSCALL_YIELD
    beq     $t8, $t9, sys_yield
    nop

    li      $t9, SYSCALL_SLEEP
    beq     $t8, $t9, sys_sleep
    nop

    li      $t9, SYSCALL_GET_TICKS
    beq     $t8, $t9, sys_get_ticks
    nop

    j       fault_halt
    nop

sys_write_char:
    lw      $t0, CTX_A0($k1)
    la      $t1, MMIO_CONSOLE
    sb      $t0, 0($t1)
    lw      $t2, CTX_EPC($k1)
    addiu   $t2, $t2, 4
    sw      $t2, CTX_EPC($k1)
    sw      $zero, CTX_V0($k1)
    RESTORE_CONTEXT $k1
    li      $t3, STATUS_IE_MASK
    mtc0    $t3, $12
    eret

sys_get_ticks:
    lw      $t0, system_ticks
    sw      $t0, CTX_V0($k1)
    lw      $t1, CTX_EPC($k1)
    addiu   $t1, $t1, 4
    sw      $t1, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    li      $t2, STATUS_IE_MASK
    mtc0    $t2, $12
    eret

sys_yield:
    lw      $t0, CTX_EPC($k1)
    addiu   $t0, $t0, 4
    sw      $t0, CTX_EPC($k1)
    li      $t1, TASK_READY
    sw      $t1, PCB_STATE($k1)
    jal     scheduler_pick_next
    nop
    move    $k1, $v0
    li      $t2, TASK_RUNNING
    sw      $t2, PCB_STATE($k1)
    RESTORE_CONTEXT $k1
    li      $t3, STATUS_IE_MASK
    mtc0    $t3, $12
    eret

sys_sleep:
    lw      $t0, system_ticks
    lw      $t1, CTX_A0($k1)
    addu    $t0, $t0, $t1
    sw      $t0, PCB_WAKE_TICK($k1)
    li      $t2, TASK_BLOCKED
    sw      $t2, PCB_STATE($k1)
    lw      $t3, CTX_EPC($k1)
    addiu   $t3, $t3, 4
    sw      $t3, CTX_EPC($k1)
    jal     scheduler_pick_next
    nop
    move    $k1, $v0
    li      $t4, TASK_RUNNING
    sw      $t4, PCB_STATE($k1)
    RESTORE_CONTEXT $k1
    li      $t5, STATUS_IE_MASK
    mtc0    $t5, $12
    eret

fault_halt:
    j       fault_halt
    nop

# ----------------------------------------------------------------------------
# Wake blocked sleepers whose deadline expired
# ----------------------------------------------------------------------------
wake_sleepers:
    li      $t0, 0
    lw      $t7, system_ticks
loop_wake:
    slti    $t1, $t0, NUM_TASKS
    beq     $t1, $zero, wake_done
    nop

    la      $t2, task_pcb_ptrs
    sll     $t3, $t0, 2
    addu    $t2, $t2, $t3
    lw      $t4, 0($t2)
    lw      $t5, PCB_STATE($t4)
    li      $t6, TASK_BLOCKED
    bne     $t5, $t6, skip_wake
    nop

    lw      $t8, PCB_WAKE_TICK($t4)
    slt     $t9, $t7, $t8
    bne     $t9, $zero, skip_wake
    nop
    li      $s0, TASK_READY
    sw      $s0, PCB_STATE($t4)

skip_wake:
    addiu   $t0, $t0, 1
    j       loop_wake
    nop

wake_done:
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# Scheduler identical to step4.
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
    move    $t4, $t1
    li      $t5, -1
    li      $t6, -1
    li      $t7, 0

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
    lw      $v0, current_pcb_ptr
    jr      $ra
    nop

have_choice:
    sw      $t6, current_task_index
    sw      $v0, current_pcb_ptr
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# Example user tasks: string writer & sleeper
# ----------------------------------------------------------------------------
    .text

task0_start:
    la      $a0, task0_msg
    jal     sys_write_string
    nop
    j       task0_loop
    nop

task0_loop:
    la      $a0, task0_msg
    jal     sys_write_string
    nop
    li      $v0, SYSCALL_SLEEP
    li      $a0, 50
    syscall
    j       task0_loop
    nop

task1_start:
    li      $a0, 'B'
    j       periodic_char_task
    nop

task2_start:
    li      $a0, 'C'
    j       periodic_char_task
    nop

task3_start:
    li      $a0, 'D'
    j       periodic_char_task
    nop

sys_write_string:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    move    $t1, $a0
loop_str:
    lbu     $t0, 0($t1)
    beq     $t0, $zero, end_str
    nop
    li      $v0, SYSCALL_WRITE_CHAR
    move    $a0, $t0
    syscall
    addiu   $t1, $t1, 1
    j       loop_str
    nop
end_str:
    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop

periodic_char_task:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
char_loop:
    li      $v0, SYSCALL_WRITE_CHAR
    syscall
    li      $v0, SYSCALL_SLEEP
    li      $a0, 10
    syscall
    j       char_loop
    nop

# ----------------------------------------------------------------------------
# Data regions
# ----------------------------------------------------------------------------
    .data
    .balign 16
current_task_index:
    .word   0
current_pcb_ptr:
    .word   0
system_ticks:
    .word   0

task0_msg:
    .asciiz "TaskA"

    .balign 16
task_init_table:
    .word task0_start, stack0_top, 3, pcb0
    .word task1_start, stack1_top, 2, pcb1
    .word task2_start, stack2_top, 1, pcb2
    .word task3_start, stack3_top, 1, pcb3

    .balign 16
task_pcb_ptrs:
    .word 0,0,0,0

kernel_stack:
    .space  1024
kernel_stack_top:

stack0:
    .space STACK_SIZE
stack0_top:
stack1:
    .space STACK_SIZE
stack1_top:
stack2:
    .space STACK_SIZE
stack2_top:
stack3:
    .space STACK_SIZE
stack3_top:

pcb0:
    .space PCB_SIZE
pcb1:
    .space PCB_SIZE
pcb2:
    .space PCB_SIZE
pcb3:
    .space PCB_SIZE
