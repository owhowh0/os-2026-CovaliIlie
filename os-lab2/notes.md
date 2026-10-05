# Lab 2 Notes: Meet the OS You Will Build (xv6)

## Part 2. Use xv6 as the Unix it is
### Observe
1. **List three programs xv6 ships with:**
   - `ls`: Lists files and directories along with their type, inode number, and size.
   - `cat`: Reads and displays contents of files or standard input.
   - `echo`: Prints arguments passed to it to standard output.
   *(Other included utilities: `sh`, `grep`, `wc`, `rm`, `mkdir`, `kill`)*.

2. **You just used a pipe ( | ) inside xv6. Which two OS features must exist for a pipe to work? (Hint: think processes and communication.)**
   - **Process Creation and Multiprocessing/Scheduling (`fork()`):** The OS must be capable of creating and scheduling multiple independent execution contexts simultaneously (the writer/producer process and the reader/consumer process).
   - **Inter-Process Communication (IPC) via shared kernel buffers and file descriptors (`pipe()`):** The OS must provide a kernel-managed synchronized buffer connecting the standard output (`fd 1`) of one process to the standard input (`fd 0`) of another process, managing blocking read/write flow control.

3. **In one sentence: how does the xv6 shell compare to the Linux shell from Lab 1?**
   - The xv6 shell implements the core Unix abstractions—command execution, I/O redirection, pipes, and background jobs—in under 150 lines of C, but intentionally omits advanced features found in modern Linux shells like tab-completion, command history, environment variables, and job control.

---

## Part 3. Read the source
### Observe
1. **Which system calls does `user/cat.c` use, and what does each one ask the kernel to do?**
   - `open(argv[i], O_RDONLY)`: Requests the kernel to locate and open the file at the given path in read-only mode and allocate an entry in the process's file descriptor table, returning the file descriptor.
   - `read(fd, buf, sizeof(buf))`: Requests the kernel to read up to 512 bytes from the file descriptor `fd` into the process buffer `buf`.
   - `write(1, buf, n)`: Requests the kernel to write `n` bytes from the user buffer `buf` to file descriptor 1 (standard output).
   - `close(fd)`: Requests the kernel to close the open file descriptor `fd` and release its descriptor table slot and file reference.
   - `exit(status)`: Requests the kernel to terminate the calling process, free its virtual memory and allocated resources, and pass its exit status to the parent process.

2. **In which kernel file, and on which line, is `sys_read` implemented?**
   - Implemented in `kernel/sysfile.c`, starting on **line 69** (`uint64 sys_read(void)`).

3. **In one sentence: what is the difference between the code in `kernel/` and the code in `user/`?**
   - Code in `kernel/` executes in privileged CPU mode (RISC-V Supervisor mode) with direct control over physical memory, hardware devices, and page tables, while code in `user/` runs in unprivileged User mode with isolated address spaces and must invoke system calls (`ecall`) to request any privileged service or hardware operation from the kernel.
