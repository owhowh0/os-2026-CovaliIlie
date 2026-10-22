# Lab 5 Notes: The File System with Your Own Hands
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. The tree and the file types
- `ls /`: standard Unix tree with UsrMerge (`bin -> usr/bin`, `sbin -> usr/bin`, `lib -> usr/lib`).
- `ls -ld /etc /etc/passwd /bin /dev/null /tmp`:
  - `/etc`: `d` (directory)
  - `/etc/passwd`: `-` (regular file)
  - `/bin`: `l` (symlink to `usr/bin`)
  - `/dev/null`: `c` (character device, major 1, minor 3)
  - `/tmp`: `d` (directory with sticky bit `t`)
- Character vs block device in `/dev`:
  - char: `/dev/null`, `/dev/console`
  - block: `/dev/nvme0n1p2`, `/dev/sda`
- Size comparison:
  - `/var/log`: 51M
  - `/usr`: 27G (~530x larger than `/var/log`)

## Part 2. Inodes and links
- File `notes.txt`: Inode 5310683, Links 1.
- `ln notes.txt hard.txt`: Both share inode 5310683, Links 2.
- `rm notes.txt`: Decrements link count to 1. `hard.txt` readable.
- `ln -s hard.txt soft.txt`: Inode 5310684, type `l`, size 8 (`"hard.txt"`).
- `rm hard.txt`: `cat soft.txt` fails with ENOENT (broken link). `soft.txt` still exists.
- Directory link counts:
  - ext4/tmpfs: 2 initially (`parent/d`, `d/.`), 4 with subdirs `x` and `y` (`d/x/..`, `d/y/..`).
  - Btrfs: reports static 1 due to B-tree optimizations.
- Size vs space:
  - `one.txt`: 2 bytes logical, 4.0K physical (minimum 1 disk block).
  - `big.img` (1GB sparse via `truncate`): 1.0G logical, 0 blocks allocated.

## Part 3. Permissions
- `chmod 600 s.txt`: `-rw-------`
- `chmod 000 s.txt`: `cat` fails with Permission Denied (owner DAC check matches and fails).
- `chmod u+r s.txt`: owner can read.
- `umask`: `0022` -> files `0666 & ~0022 = 0644`, dirs `0777 & ~0022 = 0755`.
- Directory `r` vs `x`:
  - `r--`: can `ls` directory entries, cannot `cat` inside.
  - `--x`: cannot `ls`, can traverse and `cat` files if filename known.
- Special bits:
  - `/usr/bin/passwd`: SUID `s` (runs as root to write `/etc/shadow`).
  - `/tmp`: Sticky `t` (prevents deleting other users' files in 777 dir).

## Part 4. Disks and /proc
- Root partition: `/dev/nvme0n1p2` on `/` (Btrfs subvolume `/@`, zstd:1).
- Usage: 147G used / 235G total (63%).
- Cores: 4 logical processors.
- RAM: 20,338,252 kB total (~19.4 GiB).
- `/proc/self/status`: name is `head` because `head` process opened the file.

## Stretch
- Magic numbers: gzip header starts with `1f 8b` (0x1F8B).
- SetUID search: found `pkexec`, `fusermount3`, `sudo`, `passwd`, `ksu`.
- Open file deletion: descriptor points to `bigfile (deleted)`, blocks held until fd closed.
