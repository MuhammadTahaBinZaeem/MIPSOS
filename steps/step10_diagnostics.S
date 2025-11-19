# Step 10 – Diagnostics & Protection
# Shell-based kernel extended with task statistics and simple validation.

    .set noreorder
    .set noat

    .include "../include/kernel_macros.inc"

    .equ MMIO_CONSOLE,      0xffff0000
    .equ STACK_SIZE,        512
    .equ NUM_TASKS,         4              # shell + 3 utilities

    .equ TASK_READY,        0
    .equ TASK_RUNNING,      1
    .equ TASK_BLOCKED,      2

    .equ SYSCALL_WRITE_CHAR,0
    .equ SYSCALL_YIELD,     1
    .equ SYSCALL_SPAWN,     2
    .equ SYSCALL_TASK_EXIT, 3
    .equ SYSCALL_PS,        4

    .text
    .globl _start
_start:
    la      $sp, kernel_stack_top
    addiu   $sp, $sp, -32
    jal     kmain
    nop

kmain:
    li      $t0, 0
init_loop:
    slti    $t1, $t0, NUM_TASKS
    beq     $t1, $zero, init_done
    nop
    la      $t2, pcb_table
    mul     $t3, $t0, CTX_SIZE
    addu    $t2, $t2, $t3
    la      $t4, stack_table
    mul     $t5, $t0, STACK_SIZE
    addu    $t4, $t4, $t5
    addiu   $t6, $t4, STACK_SIZE
    sw      $t6, CTX_SP($t2)
    la      $t7, task_entries
    sll     $t8, $t0, 2
    addu    $t7, $t7, $t8
    lw      $t9, 0($t7)
    sw      $t9, CTX_EPC($t2)
    la      $s1, task_states
    addu    $s1, $s1, $t8
    li      $s0, TASK_BLOCKED
    sw      $s0, 0($s1)
    addiu   $t0, $t0, 1
    j       init_loop
    nop
init_done:
    li      $t0, 0
    la      $t1, task_states
    sw      $zero, 0($t1)
    sw      $zero, current_task_index
    la      $t2, pcb_table
    sw      $t2, current_pcb_ptr

    jal     scheduler_launch_first
    nop

halt:
    j       halt
    nop

scheduler_launch_first:
    lw      $t0, current_pcb_ptr
    RESTORE_CONTEXT $t0
    eret

# ----------------------------------------------------------------------------
# Exception handler
# ----------------------------------------------------------------------------
    .ktext 0x80000180
_exception_entry:
    la      $sp, kernel_stack_top
    addiu   $sp, $sp, -128

    la      $k1, current_pcb_ptr
    lw      $k1, 0($k1)
    SAVE_CONTEXT $k1

    lw      $t7, current_task_index
    la      $t8, task_syscalls
    sll     $t9, $t7, 2
    addu    $t8, $t8, $t9
    lw      $s0, 0($t8)
    addiu   $s0, $s0, 1
    sw      $s0, 0($t8)

    mfc0    $t0, $13
    andi    $t1, $t0, 0x3c
    srl     $t1, $t1, 2
    li      $t2, 8
    bne     $t1, $t2, fault_halt
    nop

    lw      $t3, CTX_V0($k1)
    li      $t4, SYSCALL_WRITE_CHAR
    beq     $t3, $t4, sys_write_char
    nop
    li      $t4, SYSCALL_YIELD
    beq     $t3, $t4, sys_yield
    nop
    li      $t4, SYSCALL_SPAWN
    beq     $t3, $t4, sys_spawn
    nop
    li      $t4, SYSCALL_TASK_EXIT
    beq     $t3, $t4, sys_task_exit
    nop
    li      $t4, SYSCALL_PS
    beq     $t3, $t4, sys_ps
    nop

    j       fault_halt
    nop

sys_write_char:
    la      $t0, MMIO_CONSOLE
    lw      $t1, CTX_A0($k1)
    sb      $t1, 0($t0)
    lw      $t2, CTX_EPC($k1)
    addiu   $t2, $t2, 4
    sw      $t2, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    eret

sys_yield:
    lw      $t0, CTX_EPC($k1)
    addiu   $t0, $t0, 4
    sw      $t0, CTX_EPC($k1)
    lw      $t1, current_task_index
    la      $t2, task_states
    sll     $t3, $t1, 2
    addu    $t2, $t2, $t3
    li      $t4, TASK_READY
    sw      $t4, 0($t2)
    la      $t5, task_ticks
    sll     $t6, $t1, 2
    addu    $t5, $t5, $t6
    lw      $t7, 0($t5)
    addiu   $t7, $t7, 1
    sw      $t7, 0($t5)
    jal     scheduler_pick_next
    nop
    move    $k1, $v0
    RESTORE_CONTEXT $k1
    eret

sys_spawn:
    lw      $t0, CTX_A0($k1)          # task id
    bltz    $t0, spawn_error
    slti    $t10, $t0, NUM_TASKS
    beq     $t10, $zero, spawn_error
    beq     $t0, $zero, spawn_error
    nop
    la      $t1, task_states
    sll     $t2, $t0, 2
    addu    $t1, $t1, $t2
    la      $t3, pcb_table
    mul     $t4, $t0, CTX_SIZE
    addu    $t3, $t3, $t4
    la      $t5, task_entries
    addu    $t5, $t5, $t2
    lw      $t6, 0($t5)
    sw      $t6, CTX_EPC($t3)
    la      $t7, stack_table
    mul     $t8, $t0, STACK_SIZE
    addu    $t7, $t7, $t8
    addiu   $t7, $t7, STACK_SIZE
    sw      $t7, CTX_SP($t3)
    li      $t9, TASK_READY
    sw      $t9, 0($t1)
    lw      $t4, CTX_EPC($k1)
    addiu   $t4, $t4, 4
    sw      $t4, CTX_EPC($k1)
    sw      $zero, CTX_V0($k1)
    RESTORE_CONTEXT $k1
    eret

spawn_error:
    li      $t0, -1
    sw      $t0, CTX_V0($k1)
    lw      $t1, CTX_EPC($k1)
    addiu   $t1, $t1, 4
    sw      $t1, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    eret

sys_task_exit:
    lw      $t0, CTX_EPC($k1)
    addiu   $t0, $t0, 4
    sw      $t0, CTX_EPC($k1)
    lw      $t1, current_task_index
    la      $t2, task_states
    sll     $t3, $t1, 2
    addu    $t2, $t2, $t3
    li      $t4, TASK_BLOCKED
    sw      $t4, 0($t2)
    la      $t5, task_ticks
    sll     $t6, $t1, 2
    addu    $t5, $t5, $t6
    lw      $t7, 0($t5)
    addiu   $t7, $t7, 1
    sw      $t7, 0($t5)
    jal     scheduler_mark_blocked
    nop
    move    $k1, $v0
    RESTORE_CONTEXT $k1
    eret

sys_ps:
    lw      $t0, CTX_EPC($k1)
    addiu   $t0, $t0, 4
    sw      $t0, CTX_EPC($k1)
    jal     kernel_print_tasks
    nop
    RESTORE_CONTEXT $k1
    eret

fault_halt:
    j       fault_halt
    nop

scheduler_mark_blocked:
    lw      $t0, current_task_index
    la      $t1, task_states
    sll     $t2, $t0, 2
    addu    $t1, $t1, $t2
    li      $t3, TASK_BLOCKED
    sw      $t3, 0($t1)
    jal     scheduler_pick_next
    nop
    jr      $ra
    nop

scheduler_pick_next:
    lw      $t0, current_task_index
next_idx:
    addiu   $t0, $t0, 1
    li      $t1, NUM_TASKS
    slt     $t2, $t0, $t1
    bne     $t2, $zero, 1f
    nop
    move    $t0, $zero
1:
    la      $t3, task_states
    sll     $t4, $t0, 2
    addu    $t3, $t3, $t4
    lw      $t5, 0($t3)
    li      $t6, TASK_READY
    bne     $t5, $t6, next_idx
    nop
    sw      $t0, current_task_index
    la      $t7, pcb_table
    mul     $t8, $t0, CTX_SIZE
    addu    $v0, $t7, $t8
    li      $t9, TASK_RUNNING
    sw      $t9, 0($t3)
    sw      $v0, current_pcb_ptr
    la      $s0, task_switches
    sll     $s1, $t0, 2
    addu    $s0, $s0, $s1
    lw      $s2, 0($s0)
    addiu   $s2, $s2, 1
    sw      $s2, 0($s0)
    jr      $ra
    nop

kernel_print_tasks:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    li      $t0, 0
print_loop:
    slti    $t1, $t0, NUM_TASKS
    beq     $t1, $zero, print_done
    nop
    la      $t2, task_names
    sll     $t3, $t0, 2
    addu    $t2, $t2, $t3
    lw      $a0, 0($t2)
    jal     kernel_print_string
    nop
    la      $t4, task_states
    sll     $t5, $t0, 2
    addu    $t4, $t4, $t5
    lw      $t6, 0($t4)
    move    $a0, $t6
    jal     kernel_print_state
    nop
    la      $a0, stat_ticks_text
    jal     kernel_print_string
    nop
    la      $t7, task_ticks
    addu    $t7, $t7, $t3
    lw      $a0, 0($t7)
    jal     kernel_print_decimal
    nop
    la      $a0, stat_sys_text
    jal     kernel_print_string
    nop
    la      $t8, task_syscalls
    addu    $t8, $t8, $t3
    lw      $a0, 0($t8)
    jal     kernel_print_decimal
    nop
    la      $a0, stat_sw_text
    jal     kernel_print_string
    nop
    la      $t9, task_switches
    addu    $t9, $t9, $t3
    lw      $a0, 0($t9)
    jal     kernel_print_decimal
    nop
    la      $a0, newline_text
    jal     kernel_print_string
    nop
    addiu   $t0, $t0, 1
    j       print_loop
    nop
print_done:
    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop

kernel_print_state:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    la      $t0, state_strings
    sll     $t1, $a0, 2
    addu    $t0, $t0, $t1
    lw      $a0, 0($t0)
    jal     kernel_print_string
    nop
    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop

kernel_print_string:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    move    $t0, $a0
    la      $t2, MMIO_CONSOLE
print_str_loop:
    lbu     $t1, 0($t0)
    beq     $t1, $zero, print_str_done
    nop
    sb      $t1, 0($t2)
    addiu   $t0, $t0, 1
    j       print_str_loop
    nop
print_str_done:
    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop

kernel_print_decimal:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    move    $t0, $a0
    la      $t1, decimal_buffer
    addiu   $t1, $t1, 15
    sb      $zero, 0($t1)
    addiu   $t1, $t1, -1
    bne     $t0, $zero, dec_loop
    nop
    li      $t2, '0'
    sb      $t2, 0($t1)
    addiu   $t1, $t1, -1
    j       dec_done
    nop
dec_loop:
    li      $t3, 10
    divu    $t0, $t3
    mfhi    $t4
    mflo    $t0
    addiu   $t4, $t4, '0'
    sb      $t4, 0($t1)
    addiu   $t1, $t1, -1
    bne     $t0, $zero, dec_loop
    nop
dec_done:
    addiu   $t1, $t1, 1
    move    $a0, $t1
    jal     kernel_print_string
    nop
    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# User tasks (shell + utilities)
# ----------------------------------------------------------------------------
    .text

shell_task:
    la      $s0, command_script
shell_loop:
    lbu     $t0, 0($s0)
    beq     $t0, $zero, shell_done
    nop
    la      $a0, prompt_text
    jal     kernel_print_string
    nop
    la      $t1, command_names
    sll     $t2, $t0, 2
    addu    $t1, $t1, $t2
    lw      $a0, 0($t1)
    jal     kernel_print_string
    nop
    li      $v0, SYSCALL_SPAWN
    move    $a0, $t0
    syscall
wait_for_completion:
    li      $v0, SYSCALL_YIELD
    syscall
    la      $t3, task_states
    sll     $t4, $t0, 2
    addu    $t3, $t3, $t4
    lw      $t5, 0($t3)
    bne     $t5, $zero, wait_for_completion
    nop
    addiu   $s0, $s0, 1
    j       shell_loop
    nop
shell_done:
    j       shell_done
    nop

ps_task:
    li      $v0, SYSCALL_PS
    syscall
    li      $v0, SYSCALL_TASK_EXIT
    syscall

semtest_task:
    la      $a0, semtest_text
    jal     kernel_print_string
    nop
    li      $v0, SYSCALL_TASK_EXIT
    syscall

fstest_task:
    la      $a0, fstest_text
    jal     kernel_print_string
    nop
    li      $v0, SYSCALL_TASK_EXIT
    syscall

# ----------------------------------------------------------------------------
# Data
# ----------------------------------------------------------------------------
    .data
current_task_index:
    .word   0
current_pcb_ptr:
    .word   0

task_entries:
    .word shell_task
    .word ps_task
    .word semtest_task
    .word fstest_task

    .balign 16
pcb_table:
    .space  NUM_TASKS * CTX_SIZE
stack_table:
    .space  NUM_TASKS * STACK_SIZE

task_states:
    .word   0,0,0,0
task_ticks:
    .word   0,0,0,0
task_switches:
    .word   0,0,0,0
task_syscalls:
    .word   0,0,0,0

command_script:
    .byte   1,2,3,0
command_names:
    .word   ps_name
    .word   ps_name
    .word   semtest_name
    .word   fstest_name
task_names:
    .word   shell_name
    .word   ps_name
    .word   semtest_name
    .word   fstest_name

ps_name:
    .asciiz "ps\n"
semtest_name:
    .asciiz "semtest\n"
fstest_name:
    .asciiz "fstest\n"
shell_name:
    .asciiz "shell\n"
prompt_text:
    .asciiz "> "
semtest_text:
    .asciiz "Semaphore demo complete\n"
fstest_text:
    .asciiz "Filesystem demo complete\n"
state_strings:
    .word state_ready
    .word state_running
    .word state_blocked
state_ready:
    .asciiz " READY\n"
state_running:
    .asciiz " RUNNING\n"
state_blocked:
    .asciiz " BLOCKED\n"
stat_ticks_text:
    .asciiz " ticks="
stat_sys_text:
    .asciiz " syscalls="
stat_sw_text:
    .asciiz " switches="
decimal_buffer:
    .space  16
newline_text:
    .asciiz "\n"
