# Step 8 – Simple Filesystem in RAM
# Minimal cooperative kernel with syscalls to open/write/read/close files.

    .set noreorder
    .set noat

    .include "../include/kernel_macros.inc"

    .equ MMIO_CONSOLE,      0xffff0000
    .equ STACK_SIZE,        512
    .equ NUM_TASKS,         2

    .equ SYSCALL_WRITE_CHAR,0
    .equ SYSCALL_YIELD,     1
    .equ SYSCALL_OPEN,      2
    .equ SYSCALL_WRITE,     3
    .equ SYSCALL_READ,      4
    .equ SYSCALL_CLOSE,     5

    .equ MAX_FILES,         4
    .equ FILENAME_LEN,      8
    .equ FILE_DATA_SIZE,    64

    .equ FILE_NAME_OFF,     0
    .equ FILE_SIZE_OFF,     8
    .equ FILE_DATA_OFF,     12
    .equ FILE_ENTRY_SIZE,   FILE_DATA_OFF + FILE_DATA_SIZE

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
    la      $t2, task_writer
    sw      $t2, CTX_EPC($t0)

    la      $t0, pcb1
    la      $t1, stack1_top
    sw      $t1, CTX_SP($t0)
    la      $t2, task_reader
    sw      $t2, CTX_EPC($t0)

    sw      $zero, current_task_index
    la      $t0, pcb0
    sw      $t0, current_pcb_ptr

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
# Exception handler (syscall only)
# ----------------------------------------------------------------------------
    .ktext 0x80000180
_exception_entry:
    la      $sp, kernel_stack_top
    addiu   $sp, $sp, -128

    la      $k1, current_pcb_ptr
    lw      $k1, 0($k1)
    SAVE_CONTEXT $k1

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
    li      $t4, SYSCALL_OPEN
    beq     $t3, $t4, sys_open
    nop
    li      $t4, SYSCALL_WRITE
    beq     $t3, $t4, sys_write
    nop
    li      $t4, SYSCALL_READ
    beq     $t3, $t4, sys_read
    nop
    li      $t4, SYSCALL_CLOSE
    beq     $t3, $t4, sys_close
    nop

    j       fault_halt
    nop

# ----------------------------------------------------------------------------
# Syscalls
# ----------------------------------------------------------------------------
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
    jal     scheduler_pick_next
    nop
    move    $k1, $v0
    RESTORE_CONTEXT $k1
    eret

sys_open:
    lw      $t0, CTX_A0($k1)      # pointer to filename
    lw      $t1, CTX_A1($k1)      # flags (bit0=create)
    addiu   $sp, $sp, -32
    sw      $ra, 28($sp)
    move    $a0, $t0
    jal     fs_find_file
    nop
    move    $t2, $v0
    bgez    $t2, open_return_existing
    nop
    andi    $t3, $t1, 1
    beq     $t3, $zero, open_fail
    nop
    move    $a0, $t0
    jal     fs_create_file
    nop
    move    $t2, $v0
    bltz    $t2, open_fail
    nop
open_return_existing:
    sw      $t2, CTX_V0($k1)
    lw      $ra, 28($sp)
    addiu   $sp, $sp, 32
    lw      $t4, CTX_EPC($k1)
    addiu   $t4, $t4, 4
    sw      $t4, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    eret

open_fail:
    li      $t5, -1
    sw      $t5, CTX_V0($k1)
    lw      $ra, 28($sp)
    addiu   $sp, $sp, 32
    lw      $t4, CTX_EPC($k1)
    addiu   $t4, $t4, 4
    sw      $t4, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    eret

sys_close:
    lw      $t0, CTX_EPC($k1)
    addiu   $t0, $t0, 4
    sw      $t0, CTX_EPC($k1)
    sw      $zero, CTX_V0($k1)
    RESTORE_CONTEXT $k1
    eret

sys_write:
    lw      $t0, CTX_A0($k1)      # fd
    lw      $t1, CTX_A1($k1)      # buffer
    lw      $t2, CTX_A2($k1)      # len
    addiu   $sp, $sp, -32
    sw      $ra, 28($sp)
    move    $a0, $t0
    jal     fs_get_entry
    nop
    move    $t3, $v0
    bltz    $t3, write_fail
    nop
    move    $a0, $t3
    move    $a1, $t1
    move    $a2, $t2
    jal     fs_append
    nop
    move    $t4, $v0
    sw      $t4, CTX_V0($k1)
    lw      $ra, 28($sp)
    addiu   $sp, $sp, 32
    lw      $t5, CTX_EPC($k1)
    addiu   $t5, $t5, 4
    sw      $t5, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    eret

write_fail:
    li      $t4, -1
    sw      $t4, CTX_V0($k1)
    lw      $ra, 28($sp)
    addiu   $sp, $sp, 32
    lw      $t5, CTX_EPC($k1)
    addiu   $t5, $t5, 4
    sw      $t5, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    eret

sys_read:
    lw      $t0, CTX_A0($k1)      # fd
    lw      $t1, CTX_A1($k1)      # buffer
    addiu   $sp, $sp, -32
    sw      $ra, 28($sp)
    move    $a0, $t0
    jal     fs_get_entry
    nop
    move    $t2, $v0
    bltz    $t2, read_fail
    nop
    move    $a0, $t2
    move    $a1, $t1
    jal     fs_copy_to_user
    nop
    move    $t3, $v0
    sw      $t3, CTX_V0($k1)
    lw      $ra, 28($sp)
    addiu   $sp, $sp, 32
    lw      $t4, CTX_EPC($k1)
    addiu   $t4, $t4, 4
    sw      $t4, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    eret

read_fail:
    li      $t3, -1
    sw      $t3, CTX_V0($k1)
    lw      $ra, 28($sp)
    addiu   $sp, $sp, 32
    lw      $t4, CTX_EPC($k1)
    addiu   $t4, $t4, 4
    sw      $t4, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    eret

fault_halt:
    j       fault_halt
    nop

# ----------------------------------------------------------------------------
# Filesystem helpers
# ----------------------------------------------------------------------------
fs_find_file:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    li      $t0, 0
find_loop:
    slti    $t1, $t0, MAX_FILES
    beq     $t1, $zero, find_not_found
    nop
    la      $t2, file_table
    mul     $t3, $t0, FILE_ENTRY_SIZE
    addu    $t2, $t2, $t3
    move    $a1, $t2
    move    $a2, $a0
    jal     fs_compare_name
    nop
    beq     $v0, $zero, next_file
    nop
    move    $v0, $t0
    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop
next_file:
    addiu   $t0, $t0, 1
    j       find_loop
    nop
find_not_found:
    li      $v0, -1
    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop

fs_create_file:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    li      $t0, 0
create_loop:
    slti    $t1, $t0, MAX_FILES
    beq     $t1, $zero, create_fail
    nop
    la      $t2, file_table
    mul     $t3, $t0, FILE_ENTRY_SIZE
    addu    $t2, $t2, $t3
    lw      $t4, FILE_SIZE_OFF($t2)
    bne     $t4, $zero, next_slot
    nop
    move    $a1, $t2
    move    $a2, $a0
    jal     fs_set_name
    nop
    sw      $zero, FILE_SIZE_OFF($t2)
    move    $v0, $t0
    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop
next_slot:
    addiu   $t0, $t0, 1
    j       create_loop
    nop
create_fail:
    li      $v0, -1
    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop

fs_get_entry:
    slti    $t0, $a0, 0
    bne     $t0, $zero, get_fail
    nop
    slti    $t0, $a0, MAX_FILES
    beq     $t0, $zero, get_fail
    nop
    la      $t1, file_table
    mul     $t2, $a0, FILE_ENTRY_SIZE
    addu    $v0, $t1, $t2
    jr      $ra
    nop
get_fail:
    li      $v0, -1
    jr      $ra
    nop

fs_append:
    # a0=entry, a1=src, a2=len
    lw      $t0, FILE_SIZE_OFF($a0)
    li      $t1, FILE_DATA_SIZE
    subu    $t2, $t1, $t0
    slt     $t3, $t2, $a2
    beq     $t3, $zero, have_space
    nop
    move    $a2, $t2
have_space:
    addiu   $t4, $a0, FILE_DATA_OFF
    addu    $t4, $t4, $t0
copy_loop:
    blez    $a2, append_done
    nop
    lbu     $t5, 0($a1)
    sb      $t5, 0($t4)
    addiu   $a1, $a1, 1
    addiu   $t4, $t4, 1
    addiu   $a2, $a2, -1
    addiu   $t0, $t0, 1
    j       copy_loop
    nop
append_done:
    sw      $t0, FILE_SIZE_OFF($a0)
    move    $v0, $t0
    jr      $ra
    nop

fs_copy_to_user:
    # a0=entry, a1=dest
    lw      $t0, FILE_SIZE_OFF($a0)
    addiu   $t1, $a0, FILE_DATA_OFF
    move    $t2, $t0
copy_out_loop:
    blez    $t2, copy_out_done
    nop
    lbu     $t3, 0($t1)
    sb      $t3, 0($a1)
    addiu   $t1, $t1, 1
    addiu   $a1, $a1, 1
    addiu   $t2, $t2, -1
    j       copy_out_loop
    nop
copy_out_done:
    sb      $zero, 0($a1)
    move    $v0, $t0
    jr      $ra
    nop

fs_compare_name:
    # a1=entry, a2=string ptr
    addiu   $t0, $a1, FILE_NAME_OFF
    li      $t1, FILENAME_LEN
cmp_loop:
    beq     $t1, $zero, cmp_equal
    nop
    lbu     $t2, 0($t0)
    lbu     $t3, 0($a2)
    beq     $t2, $zero, cmp_equal
    nop
    bne     $t2, $t3, cmp_not
    nop
    addiu   $t0, $t0, 1
    addiu   $a2, $a2, 1
    addiu   $t1, $t1, -1
    j       cmp_loop
    nop
cmp_equal:
    li      $v0, 1
    jr      $ra
    nop
cmp_not:
    move    $v0, $zero
    jr      $ra
    nop

fs_set_name:
    addiu   $t0, $a1, FILE_NAME_OFF
    li      $t1, FILENAME_LEN
set_loop:
    beq     $t1, $zero, set_done
    nop
    lbu     $t2, 0($a2)
    sb      $t2, 0($t0)
    beq     $t2, $zero, set_done
    nop
    addiu   $t0, $t0, 1
    addiu   $a2, $a2, 1
    addiu   $t1, $t1, -1
    j       set_loop
    nop
set_done:
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# Scheduler – round robin
# ----------------------------------------------------------------------------
scheduler_pick_next:
    la      $t0, current_task_index
    lw      $t1, 0($t0)
    xori    $t1, $t1, 1
    sw      $t1, 0($t0)
    beq     $t1, $zero, pick_pcb0
    nop
    la      $v0, pcb1
    sw      $v0, current_pcb_ptr
    jr      $ra
    nop
pick_pcb0:
    la      $v0, pcb0
    sw      $v0, current_pcb_ptr
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# User tasks demonstrating filesystem
# ----------------------------------------------------------------------------
    .text

task_writer:
    la      $a0, filename_log
    li      $a1, 1
    li      $v0, SYSCALL_OPEN
    syscall
    move    $s0, $v0
    la      $t0, message_log
write_loop:
    li      $v0, SYSCALL_WRITE
    move    $a0, $s0
    move    $a1, $t0
    li      $a2, 12
    syscall
    li      $v0, SYSCALL_WRITE_CHAR
    li      $a0, '.'
    syscall
    li      $v0, SYSCALL_YIELD
    syscall
    j       write_loop
    nop

task_reader:
    la      $a0, filename_log
    li      $a1, 0
    li      $v0, SYSCALL_OPEN
    syscall
    move    $s0, $v0
    la      $s1, read_buffer
read_loop:
    li      $v0, SYSCALL_READ
    move    $a0, $s0
    move    $a1, $s1
    syscall
    li      $v0, SYSCALL_WRITE_CHAR
    lbu     $a0, 0($s1)
    syscall
    li      $v0, SYSCALL_YIELD
    syscall
    j       read_loop
    nop

# ----------------------------------------------------------------------------
# Data
# ----------------------------------------------------------------------------
    .data
    .balign 16
current_task_index:
    .word   0
current_pcb_ptr:
    .word   0

filename_log:
    .asciiz "log.txt"
message_log:
    .asciiz "HELLO WORLD"
read_buffer:
    .space  64

    .balign 16
file_table:
    .space  MAX_FILES * FILE_ENTRY_SIZE

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

pcb0:
    .space  CTX_SIZE
pcb1:
    .space  CTX_SIZE
