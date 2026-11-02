# Lab 9 Notes: Watching System Calls with strace
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. See the calls of a real command
- Command: `strace -f -e trace=openat,read,write,close ls -l`
- Observation of execution flow:
  - Burst of initialization calls:
    - `openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 4` / `close(4)`
    - `openat` and `read` for shared libraries (`libcap.so.2`, `libc.so.6`, `libnss_systemd.so.2`, `libgcc_s.so.1`)
    - Locale and identity queries: `locale.alias`, `/etc/nsswitch.conf`, `/etc/passwd`, `/etc/group`, `/run/systemd/userdb/`
    - Directory reading: `openat(AT_FDCWD, ".", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = 4`
    - Timezone resolution: `openat(AT_FDCWD, "/etc/localtime", ...)`
  - Output burst:
    - Series of `write` system calls outputting formatted file records to file descriptor 1 (`stdout`).
    - Trailing cleanup: `close(1)`, `close(2)`.
  - Approximate call count: 40–50 system calls for `openat`, `read`, `write`, `close` on a simple directory listing.
- Answers to Observe questions:
  1. **Which system call does ls use to print to the screen?**
     `ls` uses the `write` system call (e.g., `write(1, "total 340\n", 10)` and `write(1, "lrwxrwxrwx ...", ...)`).
  2. **To which descriptor does it write?**
     It writes to file descriptor `1` (`STDOUT_FILENO`), the standard output stream connected to the terminal.

## Part 2. A program that calls the kernel directly
- Program: `syscalls.c`.
  - Uses direct system calls: `open()` (mapped by glibc to `openat`), `write()`, `read()`, `close()`.
  - Writes `"hello, kernel\n"` (14 bytes) to `note.txt` (`O_CREAT | O_WRONLY | O_TRUNC, 0644`).
  - Reads the 14 bytes back into a 64-byte stack buffer and displays it via `printf`.
- Compilation & execution:
  ```bash
  $ gcc -Wall -Wextra -O2 -o syscalls syscalls.c
  $ ./syscalls
  open returned descriptor 3
  write sent 14 bytes
  read got 14 bytes: hello, kernel
  ```
- Tracing with strace:
  ```bash
  $ strace -e trace=openat,write,read,close ./syscalls
  openat(AT_FDCWD, "note.txt", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3
  write(1, "open returned descriptor 3\n", 27) = 27
  write(3, "hello, kernel\n", 14)         = 14
  write(1, "write sent 14 bytes\n", 20)   = 20
  close(3)                                = 0
  openat(AT_FDCWD, "note.txt", O_RDONLY)  = 3
  read(3, "hello, kernel\n", 63)          = 14
  write(1, "read got 14 bytes: hello, kernel\n", 33) = 33
  close(3)                                = 0
  ```
- Answers to Observe questions:
  1. **Why are descriptors 0, 1, and 2 already taken?**
     By Unix/POSIX convention, file descriptors 0, 1, and 2 are pre-allocated and inherited by every child process from its parent shell:
     - `0`: Standard Input (`stdin`)
     - `1`: Standard Output (`stdout`)
     - `2`: Standard Error (`stderr`)
     Under POSIX rules, `open()`/`openat()` is guaranteed to allocate the lowest-numbered file descriptor currently available. Because 0, 1, and 2 are active, the first descriptor assigned to the program is 3. (Note: in subshell environments or test harnesses where extra pipes or sockets are inherited, the lowest free descriptor may be 4 or higher unless inherited descriptors are closed).

## Part 3. Count one kind of call
- Command: `strace -c cat syscalls.c > /dev/null`
- Summary table:
  ```
  % time     seconds  usecs/call     calls    errors syscall
  ------ ----------- ----------- --------- --------- ----------------
   16.83    0.000017           5         3           mprotect
   13.86    0.000014           3         4           openat
   12.87    0.000013           1        10           mmap
   11.88    0.000012           2         6           close
    8.91    0.000009           3         3           read
    8.91    0.000009           1         5           fstat
    7.92    0.000008           8         1           munmap
    7.92    0.000008           2         3           brk
    2.97    0.000003           3         1           write
    ...
  ------ ----------- ----------- --------- --------- ----------------
  100.00    0.000101           2        48         1 total
  ```
- Detailed breakdown with `strace -e trace=read cat syscalls.c > /dev/null`:
  - Call 1: `read(4, "\177ELF...", 1024) = 1024` (dynamic linker reading ELF header of `libc.so.6`)
  - Call 2: `read(4, "/* syscalls.c...", 262144) = 1158` (reading target file content into memory buffer)
  - Call 3: `read(4, "", 262144) = 0` (detecting EOF condition)
- Answers to Observe questions:
  1. **How many read calls did cat make?**
     From the summary table, `cat` made **3** `read` system calls in total (1 for runtime dynamic library loading, and 2 directly operating on `syscalls.c`).
  2. **Explain in one sentence why reading a file needs more than one read:**
     A file is read in fixed-size buffer chunks, so after loading the data, the program must issue an additional `read` call that returns 0 bytes to verify that the end-of-file (EOF) has been reached.
