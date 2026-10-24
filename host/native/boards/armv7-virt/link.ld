/* link.ld: armv7-virt board memory map (spec decision 11). RAM starts at
 * 0x40000000 on qemu's virt machine; the profile's qemu -m sets its size.
 * Image, then a 1 MB stack, then the heap from __heap_start; its size is
 * the profile's :heap :bytes, which host/native/bare.c gets as
 * -DLG_HEAP_BYTES (zig's linker takes no --defsym). The profile's qemu -m
 * must cover image, stack and heap. */
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x40000000, LENGTH = 1024M }
SECTIONS {
  .text : { KEEP(*(.text.start)) *(.text .text.*) } > RAM
  .rodata : { *(.rodata .rodata.*) } > RAM
  .ARM.exidx : { *(.ARM.exidx*) } > RAM
  .data : { *(.data .data.*) } > RAM
  .bss (NOLOAD) : ALIGN(8) { __bss_start = .; *(.bss .bss.* COMMON) . = ALIGN(8); __bss_end = .; } > RAM
  .stack (NOLOAD) : ALIGN(16) { . += 0x100000; __stack_top = .; } > RAM
  __heap_start = ALIGN(16);
}
