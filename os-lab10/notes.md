# Lab 10 Notes: Add Your Own System Call: trace (xv6)
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. The Number and the User Side
- Edits made:
  1. `kernel/syscall.h`: Added `#define SYS_trace 23`.
  2. `user/user.h`: Declared `int trace(int);` after `sync(void)`.
  3. `user/usys.pl`: Added `entry("trace");` generating the ecall assembly stub.
  4. `user/trace.c`: User-space utility that parses `mask`, executes `trace(mask)`, and execs the target command.
  5. `Makefile`: Added `$U/_trace\` to `UPROGS`.
- Check 1 Verification:
  - Invocation: `trace 32 grep hello README`
  - Output:
    ```
    3 trace: unknown sys call 23
    trace: failed
    ```
  - Confirms that the RISC-V `ecall` with register `a7 = 23` successfully traps from userspace into the kernel handler dispatch.

## Part 2. The Kernel Side
- Edits made:
  1. `kernel/proc.h`: Added `int trace_mask;` to `struct proc`.
  2. `kernel/sysproc.c`: Implemented `sys_trace()` handler reading argument `a0` via `argint(0, &mask)` and storing it in `myproc()->trace_mask`.
  3. `kernel/syscall.c`: Registered `sys_trace` in `syscalls[]` table at index `SYS_trace` (23).
  4. `kernel/syscall.c`: Defined `syscallnames[]` string lookup table and added trace output inside `syscall()`:
     ```c
     p->trapframe->a0 = syscalls[num]();
     if ((p->trace_mask >> num) & 1)
       printk("%d: syscall %s -> %ld\n",
              p->pid, syscallnames[num], p->trapframe->a0);
     ```
  5. `kernel/proc.c`: Propagated mask to child processes in `fork()`: `np->trace_mask = p->trace_mask;`, and cleared mask in `freeproc()`.
- Check 2 Verification:
  - Invocation: `trace 32 grep hello README`
  - Output:
    ```
    3: syscall read -> 1023
    3: syscall read -> 965
    3: syscall read -> 453
    3: syscall read -> 0
    ```
  - Byte sum: $1023 + 965 + 453 = 2441$ bytes (exact length of `README`), followed by 0 indicating EOF.

## Part 3. Play with the Mask
- 3.1 All calls (`mask = 2147483647`):
  ```
  $ trace 2147483647 grep hello README
  3: syscall trace -> 0
  3: syscall exec -> 3
  3: syscall open -> 3
  3: syscall read -> 1023
  3: syscall read -> 965
  3: syscall read -> 453
  3: syscall read -> 0
  3: syscall close -> 0
  ```
- 3.2 Only fork (`mask = 2`):
  ```
  $ trace 2 usertests forkforkfork
  usertests starting
  test forkforkfork: 3: syscall fork -> 4
  4: syscall fork -> 5
  5: syscall fork -> 6
  ...
  6: syscall fork -> -1
  5: syscall fork -> -1
  OK
  ```
- 3.3 Only write (`mask = 65536`):
  ```
  $ trace 65536 echo hi
  hi4: syscall write -> 2

  4: syscall write -> 1
  ```

### Answers to Observe Questions:
1. **In trace 32 grep hello README why do you see only read, and not open or close?**
   The mask is evaluated as a bitmask where bit $N$ corresponds to system call $N$. $32 = 2^5$, which sets only bit 5 (`SYS_read`). `SYS_open` is 15 and `SYS_close` is 21; their bits are 0 in the mask, so `((p->trace_mask >> num) & 1)` evaluates to false for them.
2. **In forkforkfork, three different pids print lines. Which line of code from Part 2 makes that possible?**
   The assignment `np->trace_mask = p->trace_mask;` in `kernel/proc.c` inside `fork()`. This copies the parent's trace mask to each newly created child process during process replication.
3. **In trace 65536 echo hi the trace line is printed between "hi" and the new line. Why? (How many times does echo call write?)**
   `echo` calls `write()` twice: first writing the string `"hi"` (`write(1, "hi", 2)`), and second writing the newline `"\n"` (`write(1, "\n", 1)`). Because the kernel prints the trace line immediately after the syscall completes via `printk()`, the trace message for the first write appears before the second write executes.
4. **Which mask traces both open (15) and close (21), and nothing else?**
   $2^{15} + 2^{21} = 32768 + 2097152 = \mathbf{2129920}$ (hex `0x208000`).
