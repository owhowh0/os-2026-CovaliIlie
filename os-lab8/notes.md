# Lab 8 Notes: The Same Calls Inside Your Own OS (xv6)
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. run, inside xv6
- Program: `user/run.c`.
- Process steps inside xv6:
  1. `fork()`: clones caller into a child process (PID 4, parent PID 3).
  2. `exec("echo", args)`: replaces child process image with `echo`.
  3. `wait(&status)`: parent blocks until child terminates, collecting status 0.
- Exec variations tested:
  - Default `echo`: prints `hello from the child`, exit status 0.
  - Variant `ls`: lists directory contents from root filesystem, exit status 0.
  - Variant `nosuchprog`: `exec` returns -1 (failure), child prints `exec failed` and calls `exit(1)`; parent receives exit status 1.
- Answers to Observe questions:
  1. **Three calls used:**
     - xv6: `fork()`, `exec()`, `wait(&status)`.
     - Linux (Lab 7): `fork()`, `execlp()` (wrapping `execve`), `waitpid(pid, &status, 0)` (or `wait()`).
     - **What is the same:** The core Unix process abstraction is identical. `fork()` copies the address space and process table structure; `exec()` replaces the memory image with the target binary; `wait()` synchronizes the parent and reaps the child's termination status. Separating creation (`fork`) from execution (`exec`) enables stream plumbing (redirection, pipes) before the new program runs.
  2. **Who prints "hello from the child":**
     `echo` prints it. `exec()` completely replaced the child's code and stack with `/echo`. The code of `run.c` ceased to exist in the child. `echo` iterates over `argv` and prints the strings to stdout.
  3. **Why status is 1 here and 127 on Linux:**
     The exit status returned to the parent via `wait()` reflects the integer argument passed to `exit()`. In Linux Lab 7 `run.c`, the line after exec failure was `exit(127);` (the standard POSIX shell code for command not found). In xv6 Lab 8 `user/run.c`, the line after exec failure is explicitly `exit(1);`. Thus, parent observes status 1.

## Part 2. pingpong
- Program: `user/pingpong.c`.
- Protocol:
  - Parent creates two pipes: `p2c` (parent-to-child) and `c2p` (child-to-parent).
  - Parent writes 1 byte (`'x'`) to `p2c[1]`.
  - Child blocks on `read(p2c[0], &b, 1)`, wakes up on receiving byte, prints `<pid>: received ping`, writes byte back to `c2p[1]`, and exits.
  - Parent blocks on `read(c2p[0], &b, 1)`, wakes up on receiving byte, prints `<pid>: received pong`, calls `wait(0)` and exits.
- QEMU trace:
  ```
  $ pingpong
  6: received ping
  5: received pong
  ```
- Answers to Observe questions:
  1. **Why two pipes are needed:**
     A Unix pipe is strictly unidirectional. If a single bidirectional pipe were used, both parent and child would read and write to the same buffer; the parent could race and immediately read back the byte it just wrote before the child executes, causing deadlock or self-consumption. Two distinct pipes guarantee strict, race-free request-response channels (`p2c` and `c2p`).
  2. **Which call makes the parent wait:**
     `read(c2p[0], &b, 1)`. When the parent invokes `read()` on an empty pipe that still has open write descriptors, the kernel puts the parent to sleep (`sleep()` in `kernel/pipe.c`). The parent only wakes up when the child writes the byte into `c2p[1]`.

