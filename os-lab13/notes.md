# Lab 13 Notes: Semaphores in Your Own Kernel (xv6)
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. The numbers and the user side
- Syscall numbers:
  - `SYS_sem_init`: 24
  - `SYS_sem_down`: 25
  - `SYS_sem_up`: 26
- Registered in:
  - `kernel/syscall.h`: defined constants 24, 25, 26.
  - `user/user.h`: declarations for `sem_init`, `sem_down`, `sem_up`.
  - `user/usys.pl`: assembly entry stubs generating `li a7, SYS_...` and `ecall`.
- Check 1 (Before kernel handlers implemented):
  ```
  $ semtest
  3 semtest: unknown sys call 24
  4 semtest: unknown sys call 25
  child: I ran after the parent
  parent: done, I let the child go
  ```
  Notice: `child` runs before `parent` because without functioning semaphores, `sem_down` returns -1 immediately without sleeping.

## Part 2. The kernel side
- Implementation in `kernel/sem.c`:
  - Static array `sems[8]` of `struct sem` (spinlock + int value).
  - `sys_sem_init`: sets value under spinlock.
  - `sys_sem_down`: checks `value == 0` in while loop, registers wait channel via `sleep_prepare(s)`, releases spinlock, sleeps, re-acquires spinlock, checks `killed()`, decrements value.
  - `sys_sem_up`: increments value under spinlock, calls `wakeup(s)`, releases spinlock.
- Registered in `kernel/syscall.c` and added `sem.o` to `Makefile` `OBJS`.
- Check 2 (`semtest`):
  ```
  $ semtest
  parent: done, I let the child go
  child: I ran after the parent
  ping 1
   pong 1
  ping 2
   pong 2
  ping 3
   pong 3
  semtest: OK
  ```

## Part 3. A semaphore as a lock: mix
- Program: `user/mix.c`.
- Execution:
  - Without lock (`mix`): characters of process A and process B interleave across 31 individual `write(1, p, 1)` syscalls per line on multi-core QEMU (3 CPUs).
  - With lock (`mix lock`): Semaphore 3 (initialized to 1) enforces mutual exclusion around the inner 31-write character loop, guaranteeing whole, uninterrupted lines.
- Answers to Observe questions:
  1. **Without the lock, why do the letters mix? (How many system calls does one line cost?)**
     One line costs 31 separate `write(1, p, 1)` system calls (30 characters + newline). With xv6 running across 3 CPU cores under QEMU and preemptive timer interrupts occurring at arbitrary instruction intervals, the 31 system calls of process A and process B interleave unpredictably on the UART console, mixing the letters.
  2. **With the lock every line is whole. Which two lines of mix.c make one line a critical section?**
     - Line 174: `if (uselock) sem_down(3);` immediately before the per-character printing loop.
     - Line 178: `if (uselock) sem_up(3);` immediately after the loop and newline write.
  3. **In sem_down the test is "while (s->value == 0)", not "if". Why can a process wake up and still find 0?**
     `wakeup(s)` awakens all processes sleeping on channel `s`. If multiple processes were waiting when `sem_up` increments `s->value` from 0 to 1, all waiting processes wake up and contend for `s->lock`. The first to acquire `s->lock` consumes the permit by decrementing `s->value` back to 0. When subsequent awakened processes acquire `s->lock`, they find `s->value == 0`. The `while` loop forces them to re-evaluate the predicate and sleep again.
  4. **sem_down calls release(&s->lock) BEFORE sleep(). What would go wrong if it slept holding the spinlock?**
     Deadlock. Holding a spinlock disables interrupts on that CPU. If the process went to sleep while holding `s->lock`, no process could acquire `s->lock` to call `sem_up` and increment the value. Furthermore, any process on another CPU core attempting to acquire `s->lock` would spin in an infinite busy-wait loop with interrupts disabled, completely freezing the operating system kernel.
