/* start.S: armv7-virt board entry (spec decision 11). qemu -M virt -kernel
 * loads the ELF into RAM at 0x40000000 and enters _start in SVC mode with
 * the MMU and caches off. Set the stack, give cp10/cp11 (VFP/NEON) full
 * access and enable the FPU (the hard-float ABI uses its registers), clear
 * .bss, run the program. lg_bare_main never returns: it exits through
 * semihosting. */
    .syntax unified
    .arm
    .section .text.start, "ax"
    .global _start
_start:
    ldr     sp, =__stack_top
    mrc     p15, 0, r0, c1, c0, 2
    orr     r0, r0, #(0xF << 20)
    mcr     p15, 0, r0, c1, c0, 2
    isb
    mov     r0, #0x40000000
    vmsr    fpexc, r0
    ldr     r0, =__bss_start
    ldr     r1, =__bss_end
    mov     r2, #0
1:  cmp     r0, r1
    strlo   r2, [r0], #4
    blo     1b
    bl      lg_bare_main
2:  b       2b
