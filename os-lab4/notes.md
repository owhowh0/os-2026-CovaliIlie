# Lab 4 Notes: The xv6 Shell from the Outside
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. Fix sleep for the current xv6
### user/user.h grep:
```
25:int pause(int);
26:int sleep(int);
```
`user/sleep.c` updated to call `pause(atoi(argv[1]));`.
Tested in QEMU:
- `$ sleep 5` -> pauses 5 ticks, exits 0.
- `$ sleep` -> prints `usage: sleep <ticks>`, exits 1.

---

## Part 2. bash versus the xv6 shell
### Comparison Table

| Command | Tests | bash | xv6 | Why |
|:---|:---|:---|:---|:---|
| `echo hello > f ; cat < f` | redirection | `hello` | `hello` | Both support stdout overwrite (`>`) and stdin read (`<`). |
| `ls \| grep READ` | pipe | `README` | `README 2 2 2441` | Both implement `\|` via pipe IPC and child process wiring. |
| `(echo a; echo b) \| wc` | grouping, list | `2 2 4` | `2 2 4` | Both parse subshell parentheses and chain multiple outputs. |
| `echo one ; echo two` | sequence | `one` \n `two` | `one` \n `two` | Both support `;` sequential execution. |
| `echo bg &` | background | `bg` | `bg` | Both fork asynchronous child processes via `&`. |
| `ls *` | globbing | `f README` | `ls: cannot open *` | Bash expands `*` via globbing; xv6 shell has no wildcard engine and passes `*` literally. |
| `echo $HOME` | variables | `/home/ilie` | `$HOME` | Bash expands `$VAR`; xv6 has no environment variables. |
| `echo "a b"` | quotes | `a b` | `"a b"` | Bash strips quotes; xv6 preserves quotes literally. |
| `mkdir d ; cd d ; ls ..` | PATH | `d f README` | `exec ls failed` | Bash uses `$PATH`; xv6 has no `$PATH` and searches only current dir (`/d/ls` missing). Alternative: `/ls ..`. |
| `arrow up, Tab, Ctrl+R` | history, completion | Works via readline | Escape chars / no response | Bash integrates GNU readline; xv6 has bare-bones console driver. |

### Observe
1. **Features in both:** Redirection (`<`, `>`), pipes (`\|`), sequencing (`;`), background (`&`), grouping (`(...)`), arguments, built-in `cd`.
   **Features only in bash:** Globbing (`*`), variables (`$`), quote stripping (`""`, `''`), `$PATH`, readline line-editing/history/completion.
2. **Why `ls ..` fails after `cd d`:** xv6 lacks `$PATH`. It calls `exec("ls", ...)` which resolves to `./d/ls`. Fix: `/ls ..` or `../ls ..`.
3. **Most missed vs easiest feature:**
   - Most missed: Readline command editing / Tab completion / history, and `$PATH`.
   - Easiest to add: `$PATH` fallback in `sh.c` (prefix `"/ "` if relative `exec()` fails).

---

## Part 3. Who expands *? A program that prints its argv
### Command: `args *.c "x y"`
- **xv6 (`argc = 4`):**
  ```
  argv[0] = [args]
  argv[1] = [*.c]
  argv[2] = ["x]
  argv[3] = [y"]
  ```
- **Bash (`argc = 5`):**
  ```
  argv[0] = [./args]
  argv[1] = [args.c]
  argv[2] = [args_linux.c]
  argv[3] = [sleep.c]
  argv[4] = [x y]
  ```
### Observe
1. **Argument counts:** xv6 received 4 arguments; Bash received 5 arguments.
2. **Who expands `*` and removes quotes:** The **shell** (Bash). The kernel and program do not alter the strings.
3. **Extra spaces in `args one   two   three`:** Discarded during tokenization as whitespace separators.

---

## Part 4. Read the shell
### Findings in `user/sh.c`:
- **5 command types:** `EXEC` (1), `REDIR` (2), `PIPE` (3), `LIST` (4), `BACK` (5).
- **`cd` handling:** In `main()` lines 166–170 before `fork1()`. Must be executed by the parent shell process so `chdir()` affects the shell itself.
- **Search for `*` and `$`: No matching code.** Zero logic for wildcards or variables; passes tokens verbatim.
