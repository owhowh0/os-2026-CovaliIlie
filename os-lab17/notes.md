# Lab 17 Notes: Threads Share Memory, and Race
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. Shared and racing
- Program: `fire.c`.
  - Global variable `counter = 0` shared in process address space.
  - Two POSIX threads (`pthread_create`), each executing loop `for (int i = 0; i < N; i++) counter++;` with $N = 1\,000\,000$.
  - Compiled with: `gcc -Wall -Wextra -pthread -o fire fire.c`
- Execution runs:
  - Run 1:
    ```
    thread 1 sees counter = 0
    thread 2 sees counter = 0
    expected: 2000000
    counter:  1308806   (lost updates: the race)
    ```
  - Run 2:
    ```
    thread 1 sees counter = 0
    thread 2 sees counter = 9638
    expected: 2000000
    counter:  1379538   (lost updates: the race)
    ```
  - Run 3:
    ```
    thread 1 sees counter = 0
    thread 2 sees counter = 0
    expected: 2000000
    counter:  1277104   (lost updates: the race)
    ```
- Disassembly of `counter++` (`objdump -d -M intel fire`):
  ```assembly
  11a8:   mov    rax, QWORD PTR [rip+0x2e89]   # Read from memory <counter> into %rax
  11af:   add    rax, 0x1                      # Add 1 in CPU register %rax
  11b3:   mov    QWORD PTR [rip+0x2e7e], rax   # Write updated value back to <counter>
  ```
- Answers to Observe questions:
  1. **Thread 2 prints a non-zero counter at the start. What does that prove about the memory of the two threads?**
     It proves that threads created within the same process share a single, unified virtual address space (specifically the Data/BSS segments where global variables reside). Unlike distinct processes that each receive isolated virtual memory maps upon `fork()`, changes made by Thread 1 to `counter` are immediately visible in the memory of Thread 2 without any inter-process communication mechanisms.
  2. **Why is the final counter less than 2000000, and different each run? Explain with the three steps of counter++.**
     The operation `counter++` is not atomic at the CPU hardware level; it consists of three separate instructions:
     - Step 1 (**Read**): `mov rax, [counter]` loads the current memory value into register `rax`.
     - Step 2 (**Add**): `add rax, 1` increments the register value.
     - Step 3 (**Write**): `mov [counter], rax` writes the register back to memory.
     When two threads run concurrently on multiple CPU cores, their memory accesses interleave:
     If Thread A reads `counter` (value $k$), and before Thread A writes back $k+1$, Thread B also reads `counter` (still seeing $k$), both threads subsequently write $k+1$ into memory. Two increments occurred, but the counter increased by only 1, resulting in a lost update. Because OS thread scheduling, core migration, and cache coherence timing are non-deterministic, the overlapping interleaving windows vary between runs, causing the final count to be unpredictably below 2,000,000.

## Part 2. Make it worse, then think
- Program: `fire4.c` (4 threads, each incrementing $1\,000\,000$ times, expected $4\,000\,000$).
- Execution runs:
  - Run 1:
    ```
    thread 1 sees counter = 0
    thread 3 sees counter = 0
    thread 2 sees counter = 0
    thread 4 sees counter = 50675
    expected: 4000000
    counter:  1724786   (lost updates: the race)
    ```
  - Run 2:
    ```
    thread 1 sees counter = 0
    thread 4 sees counter = 5675
    thread 2 sees counter = 0
    thread 3 sees counter = 0
    expected: 4000000
    counter:  1694983   (lost updates: the race)
    ```
  - Run 3:
    ```
    thread 1 sees counter = 0
    thread 2 sees counter = 0
    thread 4 sees counter = 6338
    thread 3 sees counter = 6386
    expected: 4000000
    counter:  1297130   (lost updates: the race)
    ```
- Scaling analysis:
  - With 2 threads: ~600,000 to 700,000 updates lost (~30–35% loss).
  - With 4 threads: ~2,300,000 to 2,700,000 updates lost (~57–67% loss).
  - Higher thread counts significantly increase contention on shared cache lines and CPU pipeline collisions, vastly magnifying the frequency of lost updates.
- Answer to Observe question:
  3. **In one sentence: what single idea would stop the lost updates?**
     Enforcing mutual exclusion (using a mutex lock or hardware atomic instructions) so that only one thread can execute the read-modify-write critical section on `counter` at any given instant.
