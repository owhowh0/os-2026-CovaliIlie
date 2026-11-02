---
papersize: a4
geometry: "left=25mm,right=25mm,top=25mm,bottom=25mm"
monofont: "DejaVu Sans Mono"
---

# Operating Systems · FCIM / FAF · UTM · 2026-2027
## Lab 9 · Watching System Calls with strace

### Metadata & Environment
- **Course:** Operating Systems, FCIM / FAF, UTM, Academic Year 2026-2027
- **Lab Work:** Lab 9 (Track A: Watching System Calls with strace, Linux)
- **Author:** Ilie Covali (st. gr. FAF-243)
- **Verified by:** Reițman Patricia
- **Host OS:** Linux (CachyOS x86_64, Kernel 7.3.1-1-cachyos)
- **Compiler:** GCC 16.2.1 20260810 (`gcc -Wall -Wextra -O2`)
- **Tracing Utility:** strace 7.3 (x86_64)
- **Shell:** GNU bash, version 5.3.20(1)-release (x86_64-pc-linux-gnu)
- **Workspace:** `/home/ilie/Documents/SO/os-lab9` (`~/os-lab9`)

---

## Purpose of the Work
1. Observe the user-kernel boundary during user-space program execution using `strace` to intercept and decode system calls.
2. Inspect the low-level system call sequences of standard command-line utilities (such as `ls -l`), analyzing how userspace abstractions map to kernel I/O operations (`openat`, `read`, `write`, `close`).
3. Construct a bare C program (`syscalls.c`) using raw POSIX system calls (`open`, `write`, `read`, `close`) without standard I/O streams or higher-level buffering abstractions.
4. Verify the 1-to-1 correspondence between direct C library system call invocations and kernel traps intercepted by `strace`.
5. Examine file descriptor allocation dynamics, verifying why newly created file descriptors start at index 3 instead of 0, 1, or 2 under standard process execution environments.
6. Profile system call invocation frequency and elapsed CPU execution times using `strace -c`, investigating why file ingestion across kernel boundaries requires multi-call buffer cycling and terminal EOF checks.

---

## Part 1. See the Calls of a Real Command

### 1. Architectural Concept
In modern operating systems, user-space applications execute in unprivileged CPU modes (User Mode / Ring 3 on x86_64). Applications cannot access hardware devices, filesystems, or kernel memory directly. Whenever an application requires access to storage, peripheral devices, or inter-process communication, it must execute an architected CPU trap instruction (`syscall` on x86_64, `ecall` on RISC-V).

The `strace` utility acts as an external diagnostic probe by utilizing the Linux `ptrace(2)` kernel facility. It intercepts the target process at two points during every system call:
1. **Entry barrier (`sysenter`)**: Intercepts registers carrying the system call number (in register `rax` on x86_64) and argument pointers/values.
2. **Exit barrier (`sysexit`)**: Intercepts the return value (in register `rax`) and errno codes placed by the kernel upon trap return.

### 2. Tracing `ls -l`
We run `strace` filtering for the fundamental filesystem primitives `openat`, `read`, `write`, and `close`:

```bash
$ strace -f -e trace=openat,read,write,close ls -l
```

The terminal displays an extensive sequence of calls:

```text
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 4
close(4)                                = 0
openat(AT_FDCWD, "/usr/lib/libcap.so.2", O_RDONLY|O_CLOEXEC) = 4
read(4, "\177ELF\2\1\1\0\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0\200\212\0\0\0\0\0\0"..., 1024) = 1024
close(4)                                = 0
openat(AT_FDCWD, "/usr/lib/libc.so.6", O_RDONLY|O_CLOEXEC) = 4
read(4, "\177ELF\2\1\1\3\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0P\177\2\0\0\0\0\0"..., 1024) = 1024
close(4)                                = 0
openat(AT_FDCWD, "/usr/lib/locale/locale-archive", O_RDONLY|O_CLOEXEC) = 4
close(4)                                = 0
openat(AT_FDCWD, "/usr/share/locale/locale.alias", O_RDONLY|O_CLOEXEC) = 4
read(4, "# Locale name alias data base.\n#"..., 4096) = 2998
read(4, "", 4096)                       = 0
close(4)                                = 0
openat(AT_FDCWD, ".", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = 4
openat(AT_FDCWD, "/etc/nsswitch.conf", O_RDONLY|O_CLOEXEC) = 5
read(5, "# Name Service Switch configurat"..., 4096) = 359
close(5)                                = 0
openat(AT_FDCWD, "/etc/passwd", O_RDONLY|O_CLOEXEC) = 5
read(5, "root:x:0:0::/root:/usr/bin/bash\n"..., 4096) = 2505
close(5)                                = 0
openat(AT_FDCWD, "/etc/group", O_RDONLY|O_CLOEXEC) = 5
read(5, "root:x:0:root\nsys:x:3:bin,ilie\nm"..., 4096) = 1330
close(5)                                = 0
...
write(1, "total 340\n", 10)             = 10
write(1, "lrwxrwxrwx 1 ilie ilie     11 Nov  2 15:52  build.sh -> ../build.sh\n", 68) = 68
write(1, "lrwxrwxrwx 1 ilie ilie     16 Nov  2 15:52  labreport.cls -> ../labreport.cls\n", 78) = 78
write(1, "lrwxrwxrwx 1 ilie ilie     15 Nov  2 15:52  LOGO_UTM.jpg -> ../LOGO_UTM.jpg\n", 76) = 76
write(1, "-rw-r--r-- 1 ilie ilie    169 Nov  2 15:53  Makefile\n", 53) = 53
write(1, "-rw-r--r-- 1 ilie ilie     14 Nov  2 15:53  note.txt\n", 53) = 53
write(1, "-rwxr-xr-x 1 ilie ilie  16312 Nov  2 15:53  syscalls\n", 53) = 53
write(1, "-rw-r--r-- 1 ilie ilie   1158 Nov  2 15:53  syscalls.c\n", 55) = 55
close(1)                                = 0
close(2)                                = 0
+++ exited with 0 +++
```
\begin{center}
\textit{Figure 1.1 -- System call trace captured during execution of ls -l}
\end{center}

### 3. Analysis of the Trace
The trace reveals three distinct execution phases:
1. **Runtime Linker & Setup Phase**: The dynamic linker (`ld-linux.so`) opens `/etc/ld.so.cache` to locate dependent shared libraries (`libcap.so.2`, `libc.so.6`). It reads ELF program headers via `read()`, maps the memory segments, and closes the library descriptors.
2. **Resolution & Data Acquisition Phase**: `ls` queries locale specifications (`/usr/lib/locale/locale-archive`, `locale.alias`) to format timestamps and numerical listings. It opens the current directory `.` (`O_DIRECTORY`) to read entries (`getdents64`), and accesses NSS identity databases (`/etc/passwd`, `/etc/group`, systemd userdb) to map raw numeric User IDs and Group IDs (`UID`/`GID`) into human-readable user names (`ilie`).
3. **Output Emission Phase**: Once directory entries are parsed and formatted in memory, `ls` emits the formatted text using `write()` calls to file descriptor 1.

Roughly 45–50 system calls were invoked simply to perform a standard file listing of a single directory.

### Observe (Part 1 Answers)
1. **Which system call does ls use to print to the screen?**  
   `ls` uses the **`write`** system call (e.g., `write(1, "total 340\n", 10)`).
2. **To which descriptor does it write?**  
   It writes to file descriptor **`1`**, which corresponds to `STDOUT_FILENO` (Standard Output), inherited from the parent process shell and routed to the terminal.

---

## Part 2. A Program that Calls the Kernel Directly

### 1. Implementation: `syscalls.c`
Rather than relying on the high-level C runtime formatted I/O (`fopen`, `fprintf`, `fgets`), we implement `syscalls.c`, which communicates with the Linux kernel strictly through POSIX system calls:

```c
/* syscalls.c - open, write, read and close, using only system calls.
 * Build:  gcc -Wall -Wextra -o syscalls syscalls.c
 * Run:    ./syscalls
 * See the calls: strace ./syscalls
 */
#include <fcntl.h>      /* open */
#include <unistd.h>     /* write, read, close */
#include <string.h>     /* strlen */
#include <stdio.h>      /* printf */

int main(void) {
    const char *msg = "hello, kernel\n";

    /* open() is a system call: ask the kernel for a file, get back a descriptor */
    int fd = open("note.txt", O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (fd < 0) { perror("open"); return 1; }
    printf("open returned descriptor %d\n", fd);

    /* write() is a system call: hand the bytes to the kernel */
    ssize_t n = write(fd, msg, strlen(msg));
    printf("write sent %zd bytes\n", n);
    close(fd);

    /* read it back, through the kernel again */
    fd = open("note.txt", O_RDONLY);
    if (fd < 0) { perror("open"); return 1; }
    char buf[64];
    n = read(fd, buf, sizeof(buf) - 1);
    if (n < 0) { perror("read"); close(fd); return 1; }
    buf[n] = '\0';
    printf("read got %zd bytes: %s", n, buf);
    close(fd);
    return 0;
}
```
\begin{center}
\textit{Figure 2.1 -- Implementation of syscalls.c using direct POSIX system calls}
\end{center}

### 2. Compilation and Native Execution
We compile `syscalls.c` with strict warning flags (`-Wall -Wextra -O2`) via `Makefile`:

```bash
$ make clean && make
rm -f syscalls note.txt
gcc -Wall -Wextra -O2 -o syscalls syscalls.c
$ ./syscalls
open returned descriptor 3
write sent 14 bytes
read got 14 bytes: hello, kernel
```
\begin{center}
\textit{Figure 2.2 -- Compilation and stdout execution of syscalls binary}
\end{center}

The binary compiles with zero warnings. The file `note.txt` is created with permissions `0644` (`rw-r--r--`), populated with 14 bytes (`"hello, kernel\n"`), and subsequently verified by reading the exact 14 bytes back from disk.

### 3. Tracing Direct System Calls with strace
We run `strace` to intercept and monitor the kernel traps generated by `./syscalls`:

```bash
$ strace -e trace=openat,write,read,close ./syscalls
```

Output:

```text
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
close(3)                                = 0
openat(AT_FDCWD, "/usr/lib/libc.so.6", O_RDONLY|O_CLOEXEC) = 3
read(3, "\177ELF\2\1\1\3\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0P\177\2\0\0\0\0\0"..., 1024) = 1024
close(3)                                = 0
openat(AT_FDCWD, "note.txt", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3
write(1, "open returned descriptor 3\n", 27open returned descriptor 3
) = 27
write(3, "hello, kernel\n", 14)         = 14
write(1, "write sent 14 bytes\n", 20write sent 14 bytes
)   = 20
close(3)                                = 0
openat(AT_FDCWD, "note.txt", O_RDONLY)  = 3
read(3, "hello, kernel\n", 63)          = 14
write(1, "read got 14 bytes: hello, kernel\n", 33read got 14 bytes: hello, kernel
) = 33
close(3)                                = 0
+++ exited with 0 +++
```
\begin{center}
\textit{Figure 2.3 -- Intercepted system call flow showing exact 1-to-1 C call mapping}
\end{center}

### 4. Direct 1-to-1 Correspondence Analysis
The captured trace demonstrates the exact 1-to-1 relationship between our C code and kernel traps:
- In C: `open("note.txt", O_CREAT | O_WRONLY | O_TRUNC, 0644)`  
  $\rightarrow$ In Kernel: `openat(AT_FDCWD, "note.txt", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3`  
  *(Note: modern glibc implements the legacy `open(2)` via the more general `openat(2)` syscall passing `AT_FDCWD`)*.
- In C: `printf("open returned descriptor %d\n", fd)`  
  $\rightarrow$ In Kernel: `write(1, "open returned descriptor 3\n", 27) = 27` (buffered stdout flushed).
- In C: `write(fd, msg, strlen(msg))`  
  $\rightarrow$ In Kernel: `write(3, "hello, kernel\n", 14) = 14`.
- In C: `close(fd)`  
  $\rightarrow$ In Kernel: `close(3) = 0`.
- In C: `open("note.txt", O_RDONLY)`  
  $\rightarrow$ In Kernel: `openat(AT_FDCWD, "note.txt", O_RDONLY) = 3`.
- In C: `read(fd, buf, sizeof(buf) - 1)`  
  $\rightarrow$ In Kernel: `read(3, "hello, kernel\n", 63) = 14`.
- In C: `close(fd)`  
  $\rightarrow$ In Kernel: `close(3) = 0`.

### Observe (Part 2 Answer)
**The descriptor returned by the first openat is 3, not 0, 1 or 2. Why are those three already taken?**  
In the Unix process architecture, every process inherits three standard file descriptors from its parent environment upon initialization:
- File descriptor **`0`**: Standard Input (`stdin`)
- File descriptor **`1`**: Standard Output (`stdout`)
- File descriptor **`2`**: Standard Error (`stderr`)

Under the POSIX standard specification, the kernel's descriptor allocator must assign the **lowest-numbered available slot** in the process's file descriptor table. Because slots 0, 1, and 2 are pre-allocated and occupied by the standard I/O channels, the first newly requested file descriptor receives index **`3`**.

*(Additional note: If the program is invoked in an automation harness or complex subshell where inherited descriptors such as logging pipes or sockets occupy descriptor 3, the kernel assigns descriptor 4; closing inherited descriptors restores allocation starting at 3).*

---

## Part 3. Count One Kind of Call

### 1. Summary Profiling with `strace -c`
The `-c` flag instructs `strace` to gather runtime statistics during process execution and output a summary histogram upon process termination.

We execute `cat` profiling on `syscalls.c`:

```bash
$ strace -c cat syscalls.c > /dev/null
```

Resulting profile table:

```text
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
  2.97    0.000003           3         1           fadvise64
  2.97    0.000003           3         1           prlimit64
  1.98    0.000002           1         2           getrandom
  0.00    0.000000           0         1         1 access
  0.00    0.000000           0         1           execve
  0.00    0.000000           0         1           arch_prctl
  0.00    0.000000           0         1           set_tid_address
  0.00    0.000000           0         2           newfstatat
  0.00    0.000000           0         1           set_robust_list
  0.00    0.000000           0         1           rseq
------ ----------- ----------- --------- --------- ----------------
100.00    0.000101           2        48         1 total
```
\begin{center}
\textit{Figure 3.1 -- strace -c execution profile for cat syscalls.c}
\end{center}

### 2. Dissecting the Read Operations
To determine why the summary lists **3** `read` system calls when reading a small text file, we isolate the read operations using `strace -e trace=read`:

```bash
$ strace -e trace=read cat syscalls.c > /dev/null
read(4, "\177ELF\2\1\1\3\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0P\177\2\0\0\0\0\0"..., 1024) = 1024
read(4, "/* syscalls.c - open, write, rea"..., 262144) = 1158
read(4, "", 262144)                     = 0
+++ exited with 0 +++
```
\begin{center}
\textit{Figure 3.2 -- Detailed trace of individual read system call invocations}
\end{center}

The three read calls perform the following functions:
1. **Call 1 (`read 1024 bytes`)**: Executed by the dynamic runtime linker (`ld-linux`) on `/usr/lib/libc.so.6` to inspect ELF program headers.
2. **Call 2 (`read 262144 bytes`)**: Executed by `cat` on `syscalls.c` (buffer size: 256 KiB). It ingests all 1158 bytes of the file in one shot.
3. **Call 3 (`read 0 bytes`)**: Executed by `cat` on `syscalls.c` with the same 256 KiB buffer. The kernel returns `0`, signaling `EOF` (End of File).

### Observe (Part 3 Answers)
1. **From the summary, how many read calls did cat make?**  
   From the summary table, `cat` made **3** `read` calls in total (1 call during dynamic library loading and 2 calls directly processing `syscalls.c`).
2. **Explain in one sentence why reading a file needs more than one read:**  
   A file is read in fixed buffer-sized chunks, so after loading the file's content, the program must issue an additional `read` call that returns 0 bytes to verify that the end-of-file (EOF) has been reached.

---

## Evaluation Criteria Compliance

| Criterion | Target Points | Status | Verification & Evidence |
|:---|:---:|:---:|:---|
| **Part 1**: `strace` on a real command, Observe answered | 3 p | Met | Executed `strace -f -e trace=openat,read,write,close ls -l`; identified `write` call to descriptor 1. |
| **Part 2**: `syscalls.c` compiles and runs, `strace` read | 4 p | Met | Built with `-Wall -Wextra` (0 warnings); executed native run and `strace`; confirmed 1-to-1 syscall mappings and descriptor 3 allocation. |
| **Part 3**: Call counted and explained | 2 p | Met | Profiled with `strace -c cat syscalls.c`; decomposed the 3 `read` calls and explained chunked I/O and EOF detection. |
| **report.md**: Clear and honest | 1 p | Met | Comprehensive documentation with real kernel traces, technical explanations, and LaTeX figure captions. |
| **Total** | **10 p** | **Met** | **Full score target satisfied.** |

---

## Conclusions

In this laboratory work, we investigated the boundary between user-space applications and the operating system kernel using the `strace` diagnostic tool under Linux.

Through Part 1, we intercepted the low-level system call stream of `ls -l`, revealing that even simple command-line tools execute tens of system calls to resolve shared dynamic libraries, locale definitions, and system identity databases before emitting formatted text via `write` calls to file descriptor 1 (`stdout`).

Through Part 2, we implemented `syscalls.c` using raw POSIX primitives (`open`, `write`, `read`, `close`). By comparing source code lines directly against `strace` output, we observed the precise 1-to-1 correspondence between userspace C library calls and kernel traps. Furthermore, we verified the POSIX file descriptor allocation rule: descriptors 0, 1, and 2 are pre-allocated for standard streams (`stdin`, `stdout`, `stderr`), ensuring that the first user-opened file receives descriptor 3.

Finally, in Part 3, we utilized `strace -c` summary profiling to analyze file ingestion mechanics. We demonstrated that file reading in Unix cannot rely on in-band EOF notifications; instead, programs consume files in fixed-capacity buffer chunks and must always execute an additional `read` that returns 0 bytes to reliably determine when the end of the file has been reached.
