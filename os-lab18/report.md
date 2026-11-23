---
papersize: a4
geometry: "left=25mm,right=25mm,top=25mm,bottom=25mm"
monofont: "DejaVu Sans Mono"
---

# Operating Systems · FCIM / FAF · UTM · 2026-2027
## Lab 18 · Build a User-Level Thread Switch

### Metadata & Environment
- **Course:** Operating Systems, FCIM / FAF, UTM, Academic Year 2026-2027
- **Lab Work:** Lab 18 (Track B: A User-Level Thread Switch, xv6)
- **Author:** Ilie Covali (st. gr. FAF-243)
- **Verified by:** Reițman Patricia
- **Host OS:** Linux (CachyOS x86_64, Kernel 7.3.1-1-cachyos)
- **Target Architecture:** RISC-V 64-bit (`riscv64-elf-gcc` 14.2.0)
- **Emulator:** QEMU System Emulator (`qemu-system-riscv64` 10.1.0)
- **Source Tree:** `/home/ilie/xv6-riscv`
- **Workspace:** `/home/ilie/Documents/SO/os-lab18` (`~/os-lab18`)

---

## Purpose of the Work
1. Construct a cooperative user-level threading library (green threads / coroutines) executing entirely within user space on the RISC-V xv6 operating system.
2. Examine the mechanics of CPU context switching without invoking operating system kernel primitives, hardware interrupt vectors, or privilege transitions (`ecall` / `sret`).
3. Analyze the RISC-V 64-bit calling convention, identifying the exact division between caller-saved and callee-saved registers across function boundaries.
4. Define a user-space context structure (`struct context`) encapsulating the 14 callee-saved registers: `ra`, `sp`, and `s0` through `s11`.
5. Implement low-level assembly switching (`user/uthread_switch.S`), saving the executing thread's register state to its context buffer and restoring the incoming thread's register state.
6. Initialize thread runtime environments in `thread_create()`, configuring synthetic stack pointers (`sp`) and function entry points (`ra`) to bootstrap execution seamlessly upon initial context switch.
7. Implement cooperative round-robin scheduling (`thread_schedule()` and `thread_yield()`), verifying interleaved multi-threaded execution across three concurrent tasks in xv6 under QEMU.

---

## Part 1. The Switch

### 1. User-Level vs Kernel-Level Threads
In modern computing systems, threads can be managed at two primary layers:
- **Kernel-level threads (1:1 model)**: The operating system kernel manages thread control blocks (TCBs), schedules threads across multiple physical CPU cores, and performs preemptive context switches triggered by timer interrupts. Each context switch incurs the overhead of trapping into Supervisor Mode (Ring 0 / S-mode), saving complete trap frames, and executing scheduler code in the kernel.
- **User-level threads (M:1 model / coroutines)**: A user-space runtime library multiplexes multiple user threads onto a single process execution context. Thread creation, scheduling, and switching happen entirely within User Mode (Ring 3 / U-mode). Because the kernel is unaware of user threads, context switching requires zero system call overhead, no TLB flushes, and no privilege mode transitions. However, user threads must yield cooperatively (`thread_yield()`) unless a user-space signal mechanism is implemented.

In this laboratory work, we implement a user-level thread switcher modeled directly after the xv6 kernel's own `swtch.S`, demonstrating that the core mechanism of context switching is fundamentally identical inside and outside the kernel.

### 2. RISC-V Register Classification and Calling Convention
Under the standard RISC-V calling convention (RV64 standard), general-purpose registers (`x0` through `x31`) are partitioned according to ownership responsibility across function calls:

| Register Name | ABI Mnemonic | Category | Preserved Across Call? | Role in Context Switch |
|:---:|:---:|:---:|:---:|:---|
| `x1` | `ra` | Return Address | **Callee-saved** | Target instruction address on switch |
| `x2` | `sp` | Stack Pointer | **Callee-saved** | Private stack top pointer |
| `x8` | `s0` / `fp` | Saved / Frame Pointer | **Callee-saved** | Preserved local frame register |
| `x9` | `s1` | Saved Register | **Callee-saved** | Preserved variable register |
| `x18`–`x27` | `s2`–`s11` | Saved Registers | **Callee-saved** | Preserved variable registers (10 total) |
| `x5`–`x7`, `x28`–`x31` | `t0`–`t6` | Temporaries | **Caller-saved** | Volatile; compiler preserves if needed |
| `x10`–`x17` | `a0`–`a7` | Arguments / Returns | **Caller-saved** | Volatile; argument passing registers |

\begin{center}
\textit{Figure 1.1 -- RISC-V register classification under standard calling conventions}
\end{center}

Because `thread_switch` is invoked as a standard C function call (`thread_switch(&old->ctx, &new->ctx)`), the C compiler automatically saves any live caller-saved registers (`t0`..`t6`, `a0`..`a7`) onto the thread's stack *prior* to issuing the call. Therefore, `thread_switch` needs to preserve only the **14 callee-saved registers** (`ra`, `sp`, `s0` through `s11`).

### 3. Implementation: Data Structures (`user/uthread.c`)
We define `struct context` containing exactly 14 64-bit integer fields:

```c
/* the registers a thread must keep across a switch (callee-saved) */
struct context {
  uint64 ra;
  uint64 sp;
  uint64 s0;
  uint64 s1;
  uint64 s2;
  uint64 s3;
  uint64 s4;
  uint64 s5;
  uint64 s6;
  uint64 s7;
  uint64 s8;
  uint64 s9;
  uint64 s10;
  uint64 s11;
};

struct thread {
  struct context ctx;                                           /* saved registers */
  char       stack[STACK_SIZE] __attribute__((aligned(16)));    /* thread's own stack */
  int        state;                                             /* FREE, RUNNING, RUNNABLE */
};
struct thread all_thread[MAX_THREAD];
struct thread *current_thread;
```
\begin{center}
\textit{Figure 1.2 -- Definition of struct context and struct thread in user/uthread.c}
\end{center}

Each thread receives an independent 8 KiB stack (`STACK_SIZE = 8192`) aligned to a 16-byte boundary as mandated by the RISC-V ABI.

### 4. Implementation: Assembly Context Switch (`user/uthread_switch.S`)
We implement `thread_switch(struct context *old, struct context *new)` in RISC-V assembly. Register `a0` contains the address of `old->ctx`, and register `a1` contains the address of `new->ctx`:

```assembly
.globl thread_switch
thread_switch:
        sd ra, 0(a0)
        sd sp, 8(a0)
        sd s0, 16(a0)
        sd s1, 24(a0)
        sd s2, 32(a0)
        sd s3, 40(a0)
        sd s4, 48(a0)
        sd s5, 56(a0)
        sd s6, 64(a0)
        sd s7, 72(a0)
        sd s8, 80(a0)
        sd s9, 88(a0)
        sd s10, 96(a0)
        sd s11, 104(a0)

        ld ra, 0(a1)
        ld sp, 8(a1)
        ld s0, 16(a1)
        ld s1, 24(a1)
        ld s2, 32(a1)
        ld s3, 40(a1)
        ld s4, 48(a1)
        ld s5, 56(a1)
        ld s6, 64(a1)
        ld s7, 72(a1)
        ld s8, 80(a1)
        ld s9, 88(a1)
        ld s10, 96(a1)
        ld s11, 104(a1)

        ret
```
\begin{center}
\textit{Figure 1.3 -- Assembly implementation of thread\_switch in user/uthread\_switch.S}
\end{center}

The sequence executes three logical phases:
1. **Store Phase**: Stores all 14 callee-saved registers of the currently running thread into `old->ctx` via `sd` (store doubleword) at offsets $0, 8, \dots, 104$.
2. **Load Phase**: Loads all 14 callee-saved registers for the target thread from `new->ctx` via `ld` (load doubleword) at matching offsets.
3. **Transfer Phase**: Executes `ret`. Under RISC-V, `ret` expands to `jalr x0, 0(ra)`. Because register `ra` was loaded with `new->ctx.ra`, the CPU immediately begins executing instructions at the address specified by the incoming thread.

### 5. Thread Initialization and Scheduling (`user/uthread.c`)

#### Thread Creation
When creating a thread, we must initialize its context so that when `thread_switch` jumps to it for the first time, it starts executing the thread's function on its private stack:

```c
void thread_create(void (*func)())
{
  struct thread *t;

  for (t = all_thread; t < all_thread + MAX_THREAD; t++) {
    if (t->state == FREE) break;
  }
  t->state = RUNNABLE;
  t->ctx.ra = (uint64)func;
  t->ctx.sp = (uint64)(t->stack + STACK_SIZE);
}
```
\begin{center}
\textit{Figure 1.4 -- Thread creation bootstrapping in thread\_create}
\end{center}

Because stacks grow downward in RISC-V, `t->ctx.sp` is initialized to `t->stack + STACK_SIZE` (the highest address of the stack buffer).

#### Cooperative Scheduling
When a thread voluntarily relinquishes the CPU (`thread_yield()`), it sets its state to `RUNNABLE` and invokes `thread_schedule()`:

```c
void thread_schedule(void)
{
  struct thread *t, *next_thread;

  /* find another runnable thread, round robin */
  next_thread = 0;
  t = current_thread + 1;
  for(int i = 0; i < MAX_THREAD; i++){
    if(t >= all_thread + MAX_THREAD)
      t = all_thread;
    if(t->state == RUNNABLE) {
      next_thread = t;
      break;
    }
    t = t + 1;
  }

  if (next_thread == 0) {
    printf("thread_schedule: no runnable threads\n");
    exit(-1);
  }

  if (current_thread != next_thread) {         /* switch threads?  */
    struct thread *old = current_thread;
    current_thread = next_thread;
    current_thread->state = RUNNING;
    thread_switch(&old->ctx, &next_thread->ctx);
  }
}
```
\begin{center}
\textit{Figure 1.5 -- Cooperative round-robin scheduling algorithm in thread\_schedule}
\end{center}

### 6. Build Integration (`Makefile`)
In xv6's `Makefile`, we add `$U/_uthread\` to `UPROGS` and configure custom rules to assemble `user/uthread_switch.S` and link both object files into the final user binary:

```make
$U/uthread_switch.o : $U/uthread_switch.S
	$(CC) $(CFLAGS) -c -o $U/uthread_switch.o $U/uthread_switch.S

$U/_uthread: $U/uthread.o $U/uthread_switch.o $(ULIB) $U/user.ld
	$(LD) $(LDFLAGS) -T $U/user.ld -o $U/_uthread $U/uthread.o $U/uthread_switch.o $(ULIB)
	$(OBJDUMP) -S $U/_uthread > $U/uthread.asm
```
\begin{center}
\textit{Figure 1.6 -- Makefile targets linking uthread and uthread\_switch}
\end{center}

---

## Part 2. Run It

### 1. Execution in QEMU
We compile the modified xv6 filesystem and run `uthread` inside QEMU:

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
thread_c 2
thread_a 2
thread_b 2
thread_c 3
thread_a 3
thread_b 3
...
thread_c 98
thread_a 98
thread_b 98
thread_c 99
thread_a 99
thread_b 99
thread_c: exit after 100
thread_a: exit after 100
thread_b: exit after 100
thread_schedule: no runnable threads
```
\begin{center}
\textit{Figure 2.1 -- QEMU console trace showing interleaved execution of user-level threads}
\end{center}

### 2. Execution Flow Analysis
The execution strictly conforms to the cooperative design:
1. **Startup Synchronization**: In `main()`, three threads are created. `main` marks itself `FREE` and triggers `thread_schedule()`. Each thread starts, announces its initiation (`thread_x started`), and loops calling `thread_yield()` until all three threads have set their `started` flags to 1.
2. **Round-Robin Interleaving**: Once all three threads are synchronized, each thread prints its identifier and current loop counter, increments its local accumulator, and calls `thread_yield()`. The scheduler cycles deterministically through `thread_c`, `thread_a`, and `thread_b` from iteration 0 up to iteration 99.
3. **Graceful Termination**: Upon completing 100 iterations, each thread logs its completion (`exit after 100`), transitions its state to `FREE`, and yields control. Once all worker threads are `FREE`, `thread_schedule()` detects no remaining runnable threads, prints `thread_schedule: no runnable threads`, and cleanly calls `exit(-1)`.

---

## Observe Questions & Detailed Analysis

### Observe Question
**What exactly does `thread_switch` save and load? Why is `ra` the register that makes execution continue in the other thread?**

### Technical Answer

#### 1. What `thread_switch` Saves and Loads
`thread_switch` explicitly saves and loads the **14 callee-saved registers** defined by the standard RISC-V 64-bit ABI:
- **`ra` (`x1`)**: Return address register.
- **`sp` (`x2`)**: Stack pointer register.
- **`s0` / `fp` (`x8`)**: Frame pointer / saved register 0.
- **`s1` (`x9`)**: Saved register 1.
- **`s2`–`s11` (`x18`–`x27`)**: Saved registers 2 through 11.

It **does not save caller-saved registers** (`t0`–`t6`, `a0`–`a7`). Because `thread_switch` is invoked as a standard C function call within `thread_schedule()`, the C compiler assumes all caller-saved registers are volatile across the call boundary and has already spilled any values needed later onto the calling thread's own stack. Preserving only callee-saved registers minimizes context switch latency while fully maintaining program correctness.

#### 2. Why `ra` Enables Resumption in the Target Thread
In RISC-V assembly, the function return instruction `ret` is a pseudo-instruction for:
$$\text{jalr } \text{x0}, 0(\text{ra})$$
This instruction unconditionally branches to the memory address currently stored in register `ra` while discarding the link register (`x0`).

When `thread_switch(old, new)` executes:
1. It saves the executing thread's current return address into `old->ctx.ra`.
2. It loads `new->ctx.ra` from the incoming thread's saved context into register `ra`.
3. It loads `new->ctx.sp` from the incoming thread's context into register `sp`.
4. It executes `ret`.

Because `ra` holds the destination thread's resumption address, executing `ret` jumps directly to that address in the target thread's context:
- **For a newly created thread**: During `thread_create()`, `ctx.ra` was explicitly initialized to the function pointer of the thread body:
  $$\text{t->ctx.ra} = (\text{uint64})\text{func}$$
  When `thread_switch` executes `ret`, the CPU jumps straight to the first instruction of `func`, beginning execution on the thread's newly allocated stack pointer (`t->ctx.sp`).
- **For an existing thread returning from a yield**: Register `ra` holds the instruction address immediately following the call to `thread_switch(&old->ctx, &next_thread->ctx)` inside `thread_schedule()`. When `ret` executes, the CPU resumes execution immediately after `thread_switch`, returning from `thread_schedule()` and `thread_yield()` right back to where the thread left off.

Thus, `ra` is the singular architectural register that directs the instruction pointer (`pc`) to the exact continuation point of the switched thread.

---

## Evaluation Criteria Compliance

| Criterion | Target Points | Status | Verification & Evidence |
|:---|:---:|:---:|:---|
| **`thread_switch` saves/loads registers** | 4 p | Met | Implemented in `user/uthread_switch.S`; saves/restores 14 callee-saved registers (`ra`, `sp`, `s0`..`s11`); compiles and links cleanly. |
| **`thread_create` sets `ra` and `sp`** | 3 p | Met | Initialized `t->ctx.ra = (uint64)func` and `t->ctx.sp = (uint64)(t->stack + STACK_SIZE)` with 16-byte alignment. |
| **`uthread` runs, threads take turns** | 2 p | Met | Executed in QEMU; three threads (`thread_a`, `thread_b`, `thread_c`) took turns counting to 99 and exited after 100 iterations. |
| **`Observe` answered** | 1 p | Met | Answered in `notes.txt`, `notes.md`, and report; explained callee-saved registers and the mechanics of `ra` and `ret`. |
| **Source Tree**: Committed to git | Required | Met | Committed in `/home/ilie/xv6-riscv` (commit `1b7b5bf`). |
| **Total** | **10 p** | **Met** | **Full score target satisfied.** |

---

## Conclusions

In this laboratory work, we designed and implemented a cooperative user-level threading library within the xv6 educational operating system.

Through Part 1, we established how user-level threads achieve lightweight concurrency by managing thread execution contexts directly in user space. By mapping `struct context` to the 14 RISC-V callee-saved registers (`ra`, `sp`, `s0`..`s11`), we constructed `thread_switch` in assembly to perform register swapping between thread structures. Furthermore, by properly configuring the initial stack pointer (`sp`) and return address (`ra`) during `thread_create()`, we enabled newly spawned threads to bootstrap their execution cleanly without kernel intervention.

Through Part 2, we validated cooperative scheduling in QEMU across three concurrent tasks (`thread_a`, `thread_b`, `thread_c`), demonstrating deterministic round-robin interleaving via `thread_yield()` and graceful resource deallocation upon completion. Finally, we demonstrated that context switching fundamentally relies on the return address register (`ra`) and `ret` instruction to seamlessly redirect CPU execution flow into alternate thread stacks.
