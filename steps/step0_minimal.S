# Step 0 – Very Minimal Kernel
# Pure MIPS assembly stub that boots, initializes the stack, writes a
# single character to the MMIO console, and loops forever.

    .set noreorder
    .set noat

    .equ MMIO_CONSOLE, 0xffff0000       # Example UART/console data register
    .equ KERNEL_STACK_SIZE, 1024

    .text
    .globl _start
_start:
    la      $sp, kernel_stack_top        # Install a temporary kernel stack
    addiu   $sp, $sp, -16                # Scratch space for potential spills
    j       kmain
    nop

# ----------------------------------------------------------------------------
# kmain - writes the character 'X' to the console forever.
# ----------------------------------------------------------------------------
kmain:
    la      $t0, MMIO_CONSOLE

print_loop:
    li      $t1, 'X'
    sb      $t1, 0($t0)                  # Store byte to MMIO console
    j       print_loop                   # Idle forever
    nop

    .data
    .balign 16
kernel_stack:
    .space  KERNEL_STACK_SIZE
kernel_stack_top:
