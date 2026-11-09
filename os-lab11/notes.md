# Lab 11 Notes: The Race and the Semaphore
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. See the race
- Program: `race.c`
- Execution:
  - Compiled with `gcc -Wall -pthread -o race race.c` (no `-O2`).
  - Executed three consecutive times:
    - Run 1: `counter = 1013917 (expected 2000000)`
    - Run 2: `counter = 1337324 (expected 2000000)`
    - Run 3: `counter = 1255795 (expected 2000000)`
- Answers to Observe questions:
  1. **counter++ looks like one step. Write the three steps the CPU really does:**
     At the machine assembly level (x86_64), `counter++` is executed as:
     1. `movq counter(%rip), %rax` — Read: loads the current 64-bit value of `counter` from main memory into register `%rax`.
     2. `addq $1, %rax` — Add: increments the value in register `%rax` by 1.
     3. `movq %rax, counter(%rip)` — Write back: stores the incremented register value from `%rax` back into memory at `counter`.
  2. **Describe, with those steps, how two threads can lose one addition:**
     Suppose `counter` is currently 100:
     - Thread A reads `counter` (100) into its register `%rax`.
     - Before Thread A writes back, the OS preempts Thread A (or Thread B runs concurrently on another CPU core).
     - Thread B reads `counter` (still 100) into its register `%rax`.
     - Thread B increments `%rax` to 101 and writes 101 back to memory.
     - Thread A resumes, increments its local `%rax` to 101, and writes 101 back to memory.
     Two additions were performed, but `counter` advanced from 100 to 101 instead of 102. One addition was lost.
  3. **Why is the result different at every run?**
     Thread interleaving depends non-deterministically on dynamic CPU hardware scheduling, OS timer interrupts, thread wakeups, cache hits/misses, and bus arbitration between cores. The exact cycle-by-cycle overlap of memory accesses differs on each run.

## Part 2. Fix it: mutex, then semaphore
- Programs: `mutex.c` and `sem.c`.
- Execution:
  - Both `mutex` and `sem` yield exactly `2000000` on every execution.
- Performance Comparison (`time`):
  - `race`: `real 0.008s` (fastest, but incorrect result: ~1.15 million).
  - `mutex`: `real 0.083s` (correct result: 2,000,000).
  - `sem`: `real 0.084s` (correct result: 2,000,000).
  - `atomic`: `real 0.022s` (correct result: 2,000,000, hardware lock prefix without OS sleep).
- Answers to Observe questions:
  1. **Run mutex and sem three times each. Is the answer always 2 000 000?**
     Yes. Both `pthread_mutex_lock` / `pthread_mutex_unlock` and `sem_wait` / `sem_post` enforce strict mutual exclusion around the critical section `counter++`. At most one thread can be between lock and unlock, preventing overlapping load-modify-store sequences.
  2. **What would happen in sem.c with sem_init(&s, 0, 2)? Try it and explain:**
     When initialized to 2 (`sem_init(&s, 0, 2)`), the semaphore permits up to 2 concurrent threads to acquire the semaphore without blocking (`sem_wait` decrements 2 to 1 and 1 to 0). Consequently, both thread `a` and thread `b` enter the critical section simultaneously, reintroducing the race condition. Tested execution yielded `counter = 1987295 (expected 2000000)`.
  3. **Why is the locked version slower?**
     Each increment requires acquiring and releasing synchronization primitives (2,000,000 lock acquisitions in total). This incurs atomic instruction overhead (`lock cmpxchg`), memory barrier flushes, CPU cache invalidation/traffic between cores (cache coherence protocol MESI), and occasional OS kernel context switches into the futex subsystem when contention occurs.

## Part 3. A semaphore as a signal
- Program: `order.c`.
- Expected behavior: Thread B starts first and waits at `sem_wait(&ready)`. Thread A sleeps 1s, writes `"hello"` to `message`, and calls `sem_post(&ready)`. Thread B wakes up and reads `"hello"`.
- Answers to Observe questions:
  1. **Change the start value to 1 (sem_init(&ready, 0, 1)), compile, run. What does B read now, and why?**
     When initialized to 1, `sem_wait(&ready)` in Thread B succeeds immediately (decrementing 1 to 0) without waiting for Thread A. Thread B reads `message` before Thread A has awakened from `sleep(1)` and written `"hello"`. As a result, Thread B reads an uninitialized/empty string (`B: I read ""`), violating the ordering constraint.
  2. **Put it back to 0. In one sentence: what does a semaphore that starts at 0 mean?**
     A semaphore initialized to 0 represents an unavailable event or closed barrier, forcing any acquiring thread to block until another thread signals that the event has occurred via `sem_post`.

## Part 4. A semaphore as a counter: the parking lot
- Program: `parking.c` (6 cars, 3 parking spots).
- Observation:
  - Cars enter and leave concurrently.
  - The number of cars `inside` increments and decrements, never exceeding 3.
- Answers to Observe questions:
  1. **What is the largest value of "inside" you see? Which line of code guarantees it?**
     The largest value is `3`. It is guaranteed by `sem_init(&places, 0, PLACES)` where `PLACES = 3`, combined with `sem_wait(&places)` before entering the lot, which blocks when the counter reaches 0.
  2. **Set PLACES to 1. What does the semaphore become?**
     The counting semaphore becomes a binary semaphore (mutex lock), permitting strictly one car inside the lot at any moment and enforcing complete serialization.
