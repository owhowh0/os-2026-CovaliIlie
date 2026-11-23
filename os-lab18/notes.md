# Lab 18 Notes: A User-Level Thread Switch (xv6)
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. The Switch
- Implemented user-level cooperative threading package:
  1. `struct context`: defined with 14 64-bit integer fields (`ra`, `sp`, `s0`..`s11`), representing RISC-V callee-saved registers.
  2. `thread_create(func)`:
     - Finds a `FREE` slot in `all_thread[]`.
     - Marks state as `RUNNABLE`.
     - Sets `ctx.ra = (uint64)func` (entry point).
     - Sets `ctx.sp = (uint64)(t->stack + STACK_SIZE)` (top of 16-byte aligned 8 KiB stack).
  3. `thread_schedule()`:
     - Scans `all_thread[]` round-robin for next `RUNNABLE` thread.
     - If `current_thread != next_thread`: updates states, switches context via `thread_switch(&old->ctx, &next_thread->ctx)`.
  4. `user/uthread_switch.S`:
     - Implements `thread_switch(struct context *old, struct context *new)`.
     - Saves 14 callee-saved registers (`ra`, `sp`, `s0`..`s11`) into `0(a0)`..`104(a0)`.
     - Restores 14 callee-saved registers from `0(a1)`..`104(a1)`.
     - Executes `ret`, returning into the new thread's context.
  5. `Makefile`:
     - Added `$U/_uthread\` to `UPROGS`.
     - Added custom linking rule linking `uthread.o`, `uthread_switch.o`, and `$(ULIB)`.

## Part 2. Run It
- Execution in QEMU:
  ```text
  $ uthread
  thread_a started
  thread_b started
  thread_c started
  thread_c 0
  thread_a 0
  thread_b 0
  thread_c 1
  thread_a 1
  thread_b 1
  ...
  thread_c 99
  thread_a 99
  thread_b 99
  thread_c: exit after 100
  thread_a: exit after 100
  thread_b: exit after 100
  thread_schedule: no runnable threads
  ```
- Three cooperative threads (`thread_a`, `thread_b`, `thread_c`) took turns yielding control via `thread_yield()` until each reached 100 iterations.
- Process terminated cleanly with `thread_schedule: no runnable threads` once all threads marked themselves `FREE`.

## Observe Answer
- **What thread_switch saves and loads:**
  Saves and restores the 14 RISC-V callee-saved registers (`ra`, `sp`, `s0` through `s11`). Caller-saved registers are omitted because the compiler preserves any needed values on the stack prior to calling `thread_switch`.
- **Why ra is the register that makes execution continue in the other thread:**
  `ret` is pseudo-assembly for `jalr x0, 0(ra)`. By replacing `ra` with the destination thread's saved return address (or initial function pointer), executing `ret` transfers control directly to that instruction address. Newly spawned threads begin at `func`, while previously suspended threads resume immediately after the `thread_switch()` call in `thread_schedule()`.
