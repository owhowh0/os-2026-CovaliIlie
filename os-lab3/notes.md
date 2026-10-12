# Lab 3 Notes: The Command Line (Shell, Pipes and Text Filters)
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. Move Fast, Find Help
### Observe
1. **Which of cd, ls, echo are built-ins, and why MUST cd be one?**
   - `cd` and `echo` are shell built-ins; `ls` is an external binary (`/usr/bin/ls`).
   - `cd` must be a built-in because external commands run in separate child processes (`fork()`). An external program would change the working directory of the child process and immediately exit, leaving the parent shell unchanged. Only a built-in running in the shell's process context can modify the parent shell's working directory (`sys_chdir`).
2. **How many directories are in your PATH, and in which one is ls?**
   - 16 directories in `$PATH` (`echo $PATH | tr ':' '\n' | wc -l`).
   - `ls` is located in `/usr/bin/ls`.
3. **What exit code does a command that is not found return?**
   - Exit code `127` (standard POSIX command not found code).
4. **Which option of ls sorts by modification time?**
   - `-t` (or `--sort=time`): sorts entries by time, newest first.

---

## Part 2. What the Shell Does to Your Line
### Predictions vs. Real Output

| Command | My Prediction | Real Output | Explanation |
|:---|:---|:---|:---|
| `echo *.c` | `a.c b.c` | `a.c b.c` | Glob expands to `.c` files. |
| `echo file?.txt` | `file1.txt file2.txt` | `file1.txt file2.txt` | `?` matches 1 character (`1` and `2`). |
| `echo [a-b]*` | `a.c alfa beta.txt b.c` | `a.c alfa beta.txt b.c` | `[a-b]` matches files starting with 'a' or 'b'. |
| `echo *.xyz` | `*.xyz` | `*.xyz` | Unmatched glob left literal (nullglob off). |
| `ls alfa beta.txt` | fail: no such file | `ls: cannot access 'alfa': No such file...`<br>`ls: cannot access 'beta.txt': No such file...` | Space unquoted caused word splitting. |
| `ls "alfa beta.txt"` | `'alfa beta.txt'` | `'alfa beta.txt'` | Quotes preserve space as single argument. |
| `echo '$HOME' "$HOME" \$HOME` | `$HOME /home/ilie $HOME` | `$HOME /home/ilie $HOME` | Single quotes inhibit expansion; double quotes expand; `\` escapes `$`. |
| `echo {1..5} ; echo $((7 * 6))` | `1 2 3 4 5`<br>`42` | `1 2 3 4 5`<br>`42` | Brace expansion and arithmetic evaluation. |
| `echo "today is $(date +%A), I am $(whoami)"` | `today is Monday, I am ilie` | `today is Monday, I am ilie` | Command substitutions evaluated inside double quotes. |
| `touch log{1..3}.txt && ls log*` | `log1.txt log2.txt log3.txt` | `log1.txt log2.txt log3.txt` | Braces generate three filenames, created, then globbed. |

### Observe
1. **Who expanded `*.c`?** The shell (Bash) expanded `*.c` via pathname expansion before executing `echo`.
2. **Why did `ls alfa beta.txt` fail? Two fixes:**
   - Failed due to word splitting on IFS whitespace into two separate arguments.
   - Fix 1: `ls "alfa beta.txt"`
   - Fix 2: `ls alfa\ beta.txt`
3. **Difference between single and double quotes:**
   - Single quotes treat every character literally (no parameter expansion or command substitution).
   - Double quotes suppress globbing and word splitting, but preserve variable expansion, command substitution, and arithmetic evaluation.
4. **Why `ls` shows `'alfa beta.txt'` in quotes:** GNU `ls` applies `--quoting-style=shell-escape` by default when outputting to a terminal to disambiguate filenames containing spaces.

---

## Part 3. Redirection, Chaining and Jobs
### Observe
1. **Which file got the error, and which got the listing?**
   - `err.txt` received the error message (`2> err.txt`).
   - `out.txt` received the directory listing (`> out.txt`).
2. **Difference between `> all.txt 2>&1` and `2>&1 > all.txt`:**
   - Evaluated strictly left-to-right.
   - `> all.txt 2>&1`: fd 1 is redirected to `all.txt`, then fd 2 is duplicated from fd 1 (both point to `all.txt`).
   - `2>&1 > all.txt`: fd 2 is duplicated from fd 1 (still pointing to terminal), then fd 1 is redirected to `all.txt`. Stderr prints to terminal; only stdout goes into `all.txt`.
3. **Why `wc -l < access.log` prints only number vs `wc -l access.log`:**
   - `< file` attaches file to stdin (fd 0); `wc` receives no filename argument and reads stdin anonymously.
   - `wc -l file` receives the filename as an argument, opens it, and prints the name alongside the count.
4. **Operators `;`, `&&`, `||`:**
   - `;`: Executes sequentially and unconditionally.
   - `&&`: Executes next command only if previous command succeeded (exit code 0).
   - `||`: Executes next command only if previous command failed (non-zero exit code).

---

## Part 4. One-Liners (Summary)
- **Q1:** `grep -c FAIL access.log` -> `100`
- **Q2:** `cut -d' ' -f5 access.log | sort -u` -> `/page0`, `/page1`, `/page2`, `/page3` (4 pages)
- **Q3:** `cut -d' ' -f5 access.log | sort | uniq -c` -> 125 each (sum = 500)
- **Q4:** `grep FAIL access.log | cut -d' ' -f3 | sort | uniq -c | sort -rn | head -2` -> `user3` (15) and `user5` (15) (sum = 100)
- **Q5:** `grep 'user3' access.log | cut -d' ' -f4 | sort | uniq -c` -> 15 FAIL, 57 OK (total = 72)
- **Q6:** `grep FAIL access.log | tail -3 | cut -d' ' -f2,3` -> `10:10 user0`, `10:15 user5`, `10:20 user3`
- **Q7:** `cut -d: -f7 /etc/passwd | sort | uniq -c | sort -rn` -> 38 `/usr/bin/nologin`, 1 `/usr/bin/zsh`, 1 `/usr/bin/git-shell`, 1 `/usr/bin/bash`
- **Q8:** `ls /etc | wc -l ; ls -l /etc | wc -l` -> 258 vs 259 (difference of 1 due to `total` header line)
- **Bonus:** `grep -E ' 10:[0-9]0 .* FAIL' access.log` -> 50 matching lines

---

## Part 5. Script and Automation
### Observe
1. **Shebang `#!/bin/bash` & execution without `+x`:**
   - Directs the kernel's `execve` loader to use `/bin/bash` as interpreter.
   - Without `+x`, kernel returns `EACCES` (*Permission denied*).
2. **Why `./report.sh` and not `report.sh`:**
   - Current directory `.` is excluded from `$PATH` for security (preventing binary hijacking in shared folders). Path must be explicitly qualified.
3. **Why `>&2` and `exit 1`:**
   - `>&2` routes diagnostics to stderr so standard output stream remains clean for data consumers.
   - `exit 1` returns a non-zero exit code to signal error condition to callers.
