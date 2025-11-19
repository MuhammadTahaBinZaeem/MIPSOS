# Step 7 – IPC: Semaphores & Message Queues

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
    .equ PCB_BLOCK_REASON,  CTX_SIZE + 16
    .equ PCB_BLOCK_OBJ,     CTX_SIZE + 20
    .equ PCB_WAIT_NEXT,     CTX_SIZE + 24
    .equ PCB_PENDING_VALUE, CTX_SIZE + 28
    .equ PCB_SIZE,          CTX_SIZE + 32

    .equ BLOCK_NONE,        0
    .equ BLOCK_SLEEP,       1
    .equ BLOCK_SEM,         2
    .equ BLOCK_MSG_RECV,    3
    .equ BLOCK_MSG_SEND,    4

    .equ STATUS_IE_MASK,    0x00000001
    .equ CAUSE_IP_TIMER,    0x00000400
    .equ CAUSE_EXCCODE_MASK,0x0000007c
    .equ CAUSE_EXCCODE_SHIFT,2
    .equ EXCCODE_SYSCALL,   8

    .equ SYSCALL_WRITE_CHAR,0
    .equ SYSCALL_YIELD,     1
    .equ SYSCALL_SLEEP,     2
    .equ SYSCALL_GET_TICKS, 3
    .equ SYSCALL_ALLOC,     4
    .equ SYSCALL_FREE,      5
    .equ SYSCALL_SEM_WAIT,  6
    .equ SYSCALL_SEM_POST,  7
    .equ SYSCALL_MSG_SEND,  8
    .equ SYSCALL_MSG_RECV,  9

    .equ NUM_SEMAPHORES,    2
    .equ NUM_MSG_QUEUES,    1
    .equ SEM_VALUE,         0
    .equ SEM_WAIT_HEAD,     4
    .equ SEM_WAIT_TAIL,     8
    .equ SEM_SIZE,          12

    .equ MSG_HEAD,          0
    .equ MSG_TAIL,          4
    .equ MSG_COUNT,         8
    .equ MSG_WAIT_HEAD,    12
    .equ MSG_WAIT_TAIL,    16
    .equ MSG_BUFFER,       20
    .equ MSG_DEPTH,         8
    .equ MSG_SIZE,          MSG_BUFFER + (MSG_DEPTH * 4)

    .equ HEAP_SIZE,         4096

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
    sw      $zero, PCB_BLOCK_REASON($t3)
    sw      $zero, PCB_BLOCK_OBJ($t3)
    sw      $zero, PCB_WAIT_NEXT($t3)
    sw      $zero, PCB_PENDING_VALUE($t3)

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
    la      $t1, heap_region
    sw      $t1, heap_free_ptr

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

    li      $t9, SYSCALL_ALLOC
    beq     $t8, $t9, sys_alloc
    nop

    li      $t9, SYSCALL_FREE
    beq     $t8, $t9, sys_free
    nop

    li      $t9, SYSCALL_SEM_WAIT
    beq     $t8, $t9, sys_sem_wait
    nop

    li      $t9, SYSCALL_SEM_POST
    beq     $t8, $t9, sys_sem_post
    nop

    li      $t9, SYSCALL_MSG_SEND
    beq     $t8, $t9, sys_msg_send
    nop

    li      $t9, SYSCALL_MSG_RECV
    beq     $t8, $t9, sys_msg_recv
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
    sw      $zero, PCB_BLOCK_REASON($k1)
    sw      $zero, PCB_BLOCK_OBJ($k1)
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
    li      $t6, BLOCK_SLEEP
    sw      $t6, PCB_BLOCK_REASON($k1)
    sw      $zero, PCB_BLOCK_OBJ($k1)
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

sys_alloc:
    lw      $t0, CTX_A0($k1)          # requested size
    addiu   $t0, $t0, 7
    li      $t1, -8
    and     $t0, $t0, $t1              # align to 8 bytes
    lw      $t2, heap_free_ptr
    addu    $t3, $t2, $t0
    la      $t4, heap_end
    sltu    $t5, $t4, $t3
    bne     $t5, $zero, alloc_fail
    nop
    sw      $t3, heap_free_ptr
    sw      $t2, CTX_V0($k1)
    lw      $t6, CTX_EPC($k1)
    addiu   $t6, $t6, 4
    sw      $t6, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    li      $t7, STATUS_IE_MASK
    mtc0    $t7, $12
    eret

alloc_fail:
    sw      $zero, CTX_V0($k1)
    lw      $t6, CTX_EPC($k1)
    addiu   $t6, $t6, 4
    sw      $t6, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    li      $t7, STATUS_IE_MASK
    mtc0    $t7, $12
    eret

sys_free:
    lw      $t0, CTX_EPC($k1)
    addiu   $t0, $t0, 4
    sw      $t0, CTX_EPC($k1)
    sw      $zero, CTX_V0($k1)
    RESTORE_CONTEXT $k1
    li      $t1, STATUS_IE_MASK
    mtc0    $t1, $12
    eret

sys_sem_wait:
    lw      $t0, CTX_A0($k1)
    bltz    $t0, sem_invalid
    slti    $t1, $t0, NUM_SEMAPHORES
    beq     $t1, $zero, sem_invalid
    nop
    la      $t2, semaphore_table
    sll     $t3, $t0, 2
    addu    $t2, $t2, $t3
    lw      $t4, 0($t2)
    lw      $t5, SEM_VALUE($t4)
    addiu   $t5, $t5, -1
    sw      $t5, SEM_VALUE($t4)
    bgez    $t5, sem_wait_success
    nop
    move    $a0, $t4
    move    $a1, $k1
    jal     sem_enqueue
    nop
    li      $t6, TASK_BLOCKED
    sw      $t6, PCB_STATE($k1)
    li      $t7, BLOCK_SEM
    sw      $t7, PCB_BLOCK_REASON($k1)
    sw      $t4, PCB_BLOCK_OBJ($k1)
    lw      $t8, CTX_EPC($k1)
    addiu   $t8, $t8, 4
    sw      $t8, CTX_EPC($k1)
    jal     scheduler_pick_next
    nop
    move    $k1, $v0
    li      $t9, TASK_RUNNING
    sw      $t9, PCB_STATE($k1)
    RESTORE_CONTEXT $k1
    li      $s0, STATUS_IE_MASK
    mtc0    $s0, $12
    eret

sem_wait_success:
    sw      $zero, CTX_V0($k1)
    lw      $s1, CTX_EPC($k1)
    addiu   $s1, $s1, 4
    sw      $s1, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    li      $s2, STATUS_IE_MASK
    mtc0    $s2, $12
    eret

sem_invalid:
    li      $s3, -1
    sw      $s3, CTX_V0($k1)
    lw      $s4, CTX_EPC($k1)
    addiu   $s4, $s4, 4
    sw      $s4, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    li      $s5, STATUS_IE_MASK
    mtc0    $s5, $12
    eret

sys_sem_post:
    lw      $t0, CTX_A0($k1)
    bltz    $t0, sem_invalid
    slti    $t1, $t0, NUM_SEMAPHORES
    beq     $t1, $zero, sem_invalid
    nop
    la      $t2, semaphore_table
    sll     $t3, $t0, 2
    addu    $t2, $t2, $t3
    lw      $t4, 0($t2)
    lw      $t5, SEM_VALUE($t4)
    addiu   $t5, $t5, 1
    sw      $t5, SEM_VALUE($t4)
    move    $a0, $t4
    jal     sem_dequeue
    nop
    move    $t6, $v0
    beq     $t6, $zero, sem_post_return
    nop
    li      $t7, TASK_READY
    sw      $t7, PCB_STATE($t6)
    sw      $zero, PCB_BLOCK_REASON($t6)
    sw      $zero, PCB_BLOCK_OBJ($t6)
    sw      $zero, PCB_WAIT_NEXT($t6)

sem_post_return:
    sw      $zero, CTX_V0($k1)
    lw      $t8, CTX_EPC($k1)
    addiu   $t8, $t8, 4
    sw      $t8, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    li      $t9, STATUS_IE_MASK
    mtc0    $t9, $12
    eret

sys_msg_send:
    lw      $t0, CTX_A0($k1)
    bltz    $t0, msg_invalid
    slti    $t1, $t0, NUM_MSG_QUEUES
    beq     $t1, $zero, msg_invalid
    nop
    la      $t2, msg_queue_table
    sll     $t3, $t0, 2
    addu    $t2, $t2, $t3
    lw      $t4, 0($t2)
    lw      $t5, CTX_A1($k1)
    move    $a0, $t4
    jal     msg_dequeue_waiter
    nop
    move    $t6, $v0
    beq     $t6, $zero, msg_store_value
    nop
    sw      $t5, CTX_V0($t6)
    li      $t7, TASK_READY
    sw      $t7, PCB_STATE($t6)
    sw      $zero, PCB_BLOCK_REASON($t6)
    sw      $zero, PCB_BLOCK_OBJ($t6)
    sw      $zero, PCB_WAIT_NEXT($t6)
    sw      $zero, PCB_PENDING_VALUE($t6)
    j       msg_send_success
    nop

msg_store_value:
    lw      $t7, MSG_COUNT($t4)
    li      $t8, MSG_DEPTH
    slt     $t9, $t7, $t8
    beq     $t9, $zero, msg_send_fail
    nop
    lw      $s0, MSG_TAIL($t4)
    addiu   $s1, $t4, MSG_BUFFER
    sll     $s2, $s0, 2
    addu    $s1, $s1, $s2
    sw      $t5, 0($s1)
    addiu   $s0, $s0, 1
    li      $s3, MSG_DEPTH
    bne     $s0, $s3, 1f
    nop
    move    $s0, $zero
1:
    addiu   $t7, $t7, 1
    sw      $s0, MSG_TAIL($t4)
    sw      $t7, MSG_COUNT($t4)

msg_send_success:
    sw      $zero, CTX_V0($k1)
    lw      $s4, CTX_EPC($k1)
    addiu   $s4, $s4, 4
    sw      $s4, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    li      $s5, STATUS_IE_MASK
    mtc0    $s5, $12
    eret

msg_send_fail:
    li      $s6, -1
    sw      $s6, CTX_V0($k1)
    lw      $s7, CTX_EPC($k1)
    addiu   $s7, $s7, 4
    sw      $s7, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    li      $s5, STATUS_IE_MASK
    mtc0    $s5, $12
    eret

msg_invalid:
    li      $s6, -1
    sw      $s6, CTX_V0($k1)
    lw      $s7, CTX_EPC($k1)
    addiu   $s7, $s7, 4
    sw      $s7, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    li      $s5, STATUS_IE_MASK
    mtc0    $s5, $12
    eret

sys_msg_recv:
    lw      $t0, CTX_A0($k1)
    bltz    $t0, msg_invalid
    slti    $t1, $t0, NUM_MSG_QUEUES
    beq     $t1, $zero, msg_invalid
    nop
    la      $t2, msg_queue_table
    sll     $t3, $t0, 2
    addu    $t2, $t2, $t3
    lw      $t4, 0($t2)
    lw      $t5, MSG_COUNT($t4)
    beq     $t5, $zero, msg_block_receiver
    nop
    lw      $t6, MSG_HEAD($t4)
    addiu   $t7, $t4, MSG_BUFFER
    sll     $t8, $t6, 2
    addu    $t7, $t7, $t8
    lw      $t9, 0($t7)
    addiu   $t6, $t6, 1
    li      $s0, MSG_DEPTH
    bne     $t6, $s0, 2f
    nop
    move    $t6, $zero
2:
    addiu   $t5, $t5, -1
    sw      $t6, MSG_HEAD($t4)
    sw      $t5, MSG_COUNT($t4)
    sw      $t9, CTX_V0($k1)
    lw      $s1, CTX_EPC($k1)
    addiu   $s1, $s1, 4
    sw      $s1, CTX_EPC($k1)
    RESTORE_CONTEXT $k1
    li      $s2, STATUS_IE_MASK
    mtc0    $s2, $12
    eret

msg_block_receiver:
    move    $a0, $t4
    move    $a1, $k1
    jal     msg_enqueue_waiter
    nop
    li      $s3, TASK_BLOCKED
    sw      $s3, PCB_STATE($k1)
    li      $s4, BLOCK_MSG_RECV
    sw      $s4, PCB_BLOCK_REASON($k1)
    sw      $t4, PCB_BLOCK_OBJ($k1)
    lw      $s5, CTX_EPC($k1)
    addiu   $s5, $s5, 4
    sw      $s5, CTX_EPC($k1)
    jal     scheduler_pick_next
    nop
    move    $k1, $v0
    li      $s6, TASK_RUNNING
    sw      $s6, PCB_STATE($k1)
    RESTORE_CONTEXT $k1
    li      $s7, STATUS_IE_MASK
    mtc0    $s7, $12
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

    lw      $t8, PCB_BLOCK_REASON($t4)
    li      $t9, BLOCK_SLEEP
    bne     $t8, $t9, skip_wake
    nop

    lw      $t8, PCB_WAKE_TICK($t4)
    slt     $t9, $t7, $t8
    bne     $t9, $zero, skip_wake
    nop
    li      $s0, TASK_READY
    sw      $s0, PCB_STATE($t4)
    sw      $zero, PCB_BLOCK_REASON($t4)

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
# Semaphore wait queue helpers
# ----------------------------------------------------------------------------
sem_enqueue:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    lw      $t0, SEM_WAIT_HEAD($a0)
    beq     $t0, $zero, sem_empty
    nop
    lw      $t1, SEM_WAIT_TAIL($a0)
    sw      $a1, PCB_WAIT_NEXT($t1)
    sw      $a1, SEM_WAIT_TAIL($a0)
    j       sem_done
    nop
sem_empty:
    sw      $a1, SEM_WAIT_HEAD($a0)
    sw      $a1, SEM_WAIT_TAIL($a0)
sem_done:
    sw      $zero, PCB_WAIT_NEXT($a1)
    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop

sem_dequeue:
    lw      $t0, SEM_WAIT_HEAD($a0)
    beq     $t0, $zero, sem_no_waiters
    nop
    lw      $t1, PCB_WAIT_NEXT($t0)
    sw      $t1, SEM_WAIT_HEAD($a0)
    bne     $t1, $zero, 1f
    nop
    sw      $zero, SEM_WAIT_TAIL($a0)
1:
    move    $v0, $t0
    sw      $zero, PCB_WAIT_NEXT($t0)
    jr      $ra
    nop
sem_no_waiters:
    move    $v0, $zero
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# Message queue wait list helpers
# ----------------------------------------------------------------------------
msg_enqueue_waiter:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    lw      $t0, MSG_WAIT_HEAD($a0)
    beq     $t0, $zero, msg_wait_empty
    nop
    lw      $t1, MSG_WAIT_TAIL($a0)
    sw      $a1, PCB_WAIT_NEXT($t1)
    sw      $a1, MSG_WAIT_TAIL($a0)
    j       msg_wait_done
    nop
msg_wait_empty:
    sw      $a1, MSG_WAIT_HEAD($a0)
    sw      $a1, MSG_WAIT_TAIL($a0)
msg_wait_done:
    sw      $zero, PCB_WAIT_NEXT($a1)
    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
    nop

msg_dequeue_waiter:
    lw      $t0, MSG_WAIT_HEAD($a0)
    beq     $t0, $zero, msg_wait_none
    nop
    lw      $t1, PCB_WAIT_NEXT($t0)
    sw      $t1, MSG_WAIT_HEAD($a0)
    bne     $t1, $zero, 1f
    nop
    sw      $zero, MSG_WAIT_TAIL($a0)
1:
    sw      $zero, PCB_WAIT_NEXT($t0)
    move    $v0, $t0
    jr      $ra
    nop
msg_wait_none:
    move    $v0, $zero
    jr      $ra
    nop

# ----------------------------------------------------------------------------
# Example user tasks: string writer & sleeper
# ----------------------------------------------------------------------------
    .text

task0_start:
    addiu   $sp, $sp, -32
    sw      $ra, 28($sp)
    li      $v0, SYSCALL_ALLOC
    li      $a0, 32
    syscall
    move    $s0, $v0                  # keep pointer in $s0
    beq     $s0, $zero, task0_error
    nop
    la      $a0, alloc_template
    move    $a1, $s0
    jal     copy_string
    nop
    move    $a0, $s0
    jal     sys_write_string
    nop
    lw      $ra, 28($sp)
    addiu   $sp, $sp, 32
    j       task0_loop
    nop

task0_loop:
    move    $a0, $s0
    jal     sys_write_string
    nop
    li      $v0, SYSCALL_SLEEP
    li      $a0, 50
    syscall
    j       task0_loop
    nop

task0_error:
    j       task0_error
    nop

task1_start:
    li      $a0, 'S'
    jal     semaphore_printer
    nop
    j       task1_start
    nop

task2_start:
    li      $a0, 'T'
    jal     producer_task
    nop
    j       task2_start
    nop

task3_start:
    jal     consumer_task
    nop
    j       task3_start
    nop

copy_string:
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    move    $t0, $a0                  # src
    move    $t1, $a1                  # dst
copy_loop:
    lbu     $t2, 0($t0)
    sb      $t2, 0($t1)
    addiu   $t0, $t0, 1
    addiu   $t1, $t1, 1
    bne     $t2, $zero, copy_loop
    nop
    lw      $ra, 12($sp)
    addiu   $sp, $sp, 16
    jr      $ra
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

semaphore_printer:
    move    $s0, $a0
sem_loop:
    li      $v0, SYSCALL_SEM_WAIT
    li      $a0, 0
    syscall
    li      $v0, SYSCALL_WRITE_CHAR
    move    $a0, $s0
    syscall
    li      $v0, SYSCALL_SEM_POST
    li      $a0, 0
    syscall
    li      $v0, SYSCALL_SLEEP
    li      $a0, 20
    syscall
    j       sem_loop
    nop

producer_task:
    move    $s0, $a0
    move    $s1, $zero
prod_loop:
    li      $v0, SYSCALL_SEM_WAIT
    li      $a0, 0
    syscall
    li      $v0, SYSCALL_WRITE_CHAR
    move    $a0, $s0
    syscall
    li      $v0, SYSCALL_SEM_POST
    li      $a0, 0
    syscall
    li      $v0, SYSCALL_MSG_SEND
    move    $a0, $zero
    move    $a1, $s1
    syscall
    addiu   $s1, $s1, 1
    slti    $t0, $s1, 10
    bne     $t0, $zero, prod_sleep
    nop
    move    $s1, $zero
prod_sleep:
    li      $v0, SYSCALL_SLEEP
    li      $a0, 30
    syscall
    j       prod_loop
    nop

consumer_task:
cons_loop:
    li      $v0, SYSCALL_MSG_RECV
    move    $a0, $zero
    syscall
    addiu   $t0, $v0, '0'
    li      $v0, SYSCALL_WRITE_CHAR
    move    $a0, $t0
    syscall
    li      $v0, SYSCALL_SLEEP
    li      $a0, 40
    syscall
    j       cons_loop
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

    .balign 16
heap_region:
    .space  HEAP_SIZE
heap_end:
    .balign 4
heap_free_ptr:
    .word   0

alloc_template:
    .asciiz "BUFFER OK"

    .balign 16
task_init_table:
    .word task0_start, stack0_top, 3, pcb0
    .word task1_start, stack1_top, 2, pcb1
    .word task2_start, stack2_top, 1, pcb2
    .word task3_start, stack3_top, 1, pcb3

    .balign 16
task_pcb_ptrs:
    .word 0,0,0,0

semaphore_table:
    .word semaphore0
    .word semaphore1

semaphore0:
    .word 1                      # console lock
    .word 0
    .word 0
semaphore1:
    .word 0                      # generic sync
    .word 0
    .word 0

msg_queue_table:
    .word msg_queue0

msg_queue0:
    .word 0                      # head
    .word 0                      # tail
    .word 0                      # count
    .word 0                      # wait head
    .word 0                      # wait tail
msg_queue0_buffer:
    .space MSG_DEPTH * 4

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
