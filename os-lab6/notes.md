# Lab 6 Notes: Inside the xv6 File System
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. Read what xv6 shows you
- Types from `kernel/stat.h`:
  - `T_DIR` = 1 (directory)
  - `T_FILE` = 2 (regular file)
  - `T_DEVICE` = 3 (character device)
- Root inode number: 1 (`ROOTINO` in `kernel/fs.h`). `.` and `..` both point to 1 because root has no parent above it.
- Directory entry size: `sizeof(struct dirent)` = `sizeof(ushort)` (2) + `DIRSIZ` (14) = 16 bytes.
- Size 32 for empty directory `a` = 2 entries: `.` (inode 28) and `..` (inode 1), each 16 bytes.

## Part 2. Write mystat
- Implemented `user/mystat.c` (`typename()`, `stat()`, formatted print).
- Added `$U/_mystat\` to `Makefile` `UPROGS`.
- Outputs:
  - `mystat README . console`:
    - `README: file, inode 2, links 1, size 2441 bytes`
    - `.: directory, inode 1, links 2, size 1024 bytes`
    - `console: device, inode 27, links 1, size 0 bytes`
  - After `ln README r2`:
    - `README: file, inode 2, links 2, size 2441 bytes`
    - `r2: file, inode 2, links 2, size 2441 bytes`
  - After `rm README`:
    - `r2: file, inode 2, links 1, size 2441 bytes`
    - Content intact (`cat r2 | wc` -> 48 336 2441).
- Kernel unlinking logic:
  - `kernel/sysfile.c` line 244: `ip->nlink--;`
  - Blocks freed in `iput()` (`kernel/fs.c`: `last = (ip->ref == 1 && ip->valid && ip->nlink == 0)`) via `itrunc(ip)`.
- xv6 `struct dinode` fields: `type`, `major`, `minor`, `nlink`, `size`, `addrs[NDIRECT + 1]`.

## Part 3. Measure the limits
- Constants in `kernel/fs.h`:
  - `BSIZE` = 1024
  - `NDIRECT` = 12
  - `NINDIRECT` = 1024 / 4 = 256
  - `DIRSIZ` = 14
- `mkdir averyveryverylongname` -> `ls` prints `averyveryveryl` (truncated to 14 chars due to `DIRSIZ 14`).
- Max file size calculation:
  - Blocks: 12 direct + 256 indirect = 268 blocks.
  - Bytes: 268 * 1024 = 274,432 bytes (268 KiB).
- Disk layout from `nmeta` line (`nmeta 47 ... blocks 1953 total 2000`):
  - Total: 2000 blocks
  - Log: 31 blocks (30 log blocks + 1 log header)
  - Inodes: 13 blocks (200 inodes / 16 per block)
  - Bitmap: 1 block
  - Data blocks: 1953 blocks

## Part 4. Write find & Stretch
- Implemented `user/find.c` with directory recursion, skips `.` and `..`, matches `strcmp`, closes directory descriptors.
- Stretch flag `-n`: prints path followed by inode number.
- QEMU run:
  - `find . r2`:
    - `./a/b/r2`
    - `./a/r2`
    - `./r2`
  - `find a b`:
    - `a/b`
  - `find . r2 -n`:
    - `./a/b/r2 30`
    - `./a/r2 31`
    - `./r2 3`
- Comparing with `cat` (inode 3): `./r2` has inode 3, so `./r2` is the hard link sharing inode 3 with `cat`.
