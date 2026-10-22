# Lab 7 Notes: Three Small Programs (Processes, Redirection, a Pipe)
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. fork + exec + wait
- Program: `run.c`.
- Execution flow:
  1. `fork()` copies parent address space into a child process.
  2. Child prints PID and PPID via `getpid()` and `getppid()`.
  3. `execlp("ls", "ls", "-l", NULL)` replaces child process image with `ls`.
  4. Parent waits with `waitpid(pid, &status, 0)` and reports child exit code.
- Test variations:
  - Default `ls`: child exits with status `0`.
  - Variant `date`: child executes `date` and exits with status `0`.
  - Variant `nosuchprog`: `execlp` fails, prints `exec: No such file or directory` via `perror`, exits with status `127`.
- Answers to Observe questions:
  1. `perror("exec")` runs only with `nosuchprog` because on successful `execlp()`, the process image is completely overwritten by the new program; execution never returns. Only if `exec` fails does it return `-1` to the subsequent instructions.
  2. Child prints parent PID via `getppid()`, which matches the PID printed by the parent process (`getpid()`).
  3. Exit status with `ls` is `0` (success); exit status with `nosuchprog` is `127` (command not found/exec failure).

## Part 2. A zombie, on purpose
- Program: `zombie.c`.
- Delay mechanism: inserted `sleep(20)` in parent before calling `waitpid()`.
- Process table observation (`ps -o pid,ppid,stat,cmd`):
  - While parent sleeps:
    - Parent: `PID 659861`, `STAT S<+` (sleeping).
    - Child: `PID 659863`, `STAT Z<+`, command `[ls] <defunct>`, `PPID 659861`.
  - After 20 seconds:
    - Parent calls `waitpid()`, reaps child termination state.
    - Child entry disappears from process table.
- Answers to Observe questions:
  1. The letter `Z` in the `STAT` column indicates a Zombie (defunct) process. The child has terminated execution, but its exit metadata is preserved in the kernel's process table until the parent reads it.
  2. After 20 seconds, `[ls] <defunct>` disappears. The line `waitpid(pid, &status, 0);` reaps the zombie and frees its entry in the kernel process table.

## Part 3. Redirection: ls -l > out.txt
- Program: `redirect.c`.
- Redirection mechanism:
  - Child calls `close(1)` to release file descriptor 1 (`stdout`).
  - Child calls `open("out.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644)`.
  - Kernel allocates the lowest free descriptor, which is guaranteed to be 1.
  - `execlp("ls", "ls", "-l", NULL)` runs with descriptor 1 pointing to `out.txt`.
- Verification:
  - `fprintf(stderr, ...)` logs `open gave descriptor 1`.
  - `out.txt` contains directory listing identical to `ls -l`.
- Answers to Observe questions:
  1. `open()` returned descriptor `1`. Under POSIX/Linux rules, `open()` always allocates the lowest-numbered file descriptor currently available. Since 1 was closed just before `open()`, 1 was the smallest available index.
  2. `ls` writes to file descriptor 1 by default. Because descriptor 1 was redirected to `out.txt` before `exec`, `ls` writes its output to the file instead of the terminal display.
  3. To redirect standard error (`2> err.txt`), close file descriptor `2` (`STDERR_FILENO`) before `open()`.

## Part 4. A pipe: ls /etc | wc -l
- Program: `pipeline.c`.
- Pipeline mechanism:
  - `pipe(p)` creates kernel buffer: `p[0]` (read) and `p[1]` (write).
  - Child 1 (`ls`): closes 1, `dup(p[1])` assigns `p[1]` to 1, closes `p[0]` and `p[1]`, executes `ls /etc`.
  - Child 2 (`wc`): closes 0, `dup(p[0])` assigns `p[0]` to 0, closes `p[0]` and `p[1]`, executes `wc -l`.
  - Parent closes both `p[0]` and `p[1]` and calls `wait(NULL)` twice.
- Verification:
  - `./pipeline` output: `259`.
  - Shell `ls /etc | wc -l`: `259`.
- Break on purpose (`/* close(p[1]); */` in parent):
  - Program hangs indefinitely.
- Answers to Observe questions:
  1. Yes, `./pipeline` and `ls /etc | wc -l` both output `259`.
  2. After commenting out `close(p[1]);` in the parent, the second child (`wc`) never ends (`ls` completes normally).
  3. In one sentence: `wc` is waiting for EOF on its standard input (`p[0]`), which the kernel will never deliver because the parent process still holds a write descriptor (`p[1]`) open.
