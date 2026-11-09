# Lab 12 Notes: Producer, Consumer and the Other Tools
Author: Ilie Covali (gr. FAF-243)
Instructor: Reițman Patricia

## Part 1. Producer and consumer
- Program: `prodcons.c`
- Synchronization mechanism:
  - `empty`: counting semaphore tracking free slots (initialized to `SIZE = 4`).
  - `full`: counting semaphore tracking filled slots (initialized to `0`).
  - `lock`: `pthread_mutex_t` protecting buffer index updates (`in`, `out`) and shared array `buf`.
- Answers to Observe questions:
  1. **The producer is fast, yet "in buffer" never goes above 4. Which call stops it?**
     `sem_wait(&empty);` stops the producer. When all 4 slots are occupied, the semaphore counter `empty` reaches `0`, causing `sem_wait(&empty)` to block the producer until the consumer frees a slot and calls `sem_post(&empty)`.
  2. **Who waits at the start: the consumer or the producer? Which call makes it wait?**
     The consumer waits at the start. It is blocked by `sem_wait(&full);` because `full` is initialized to `0` (the buffer contains no items initially).
  3. **In producer(), swap the first two lines: lock the mutex BEFORE sem_wait(&empty). Run it. What happens when the buffer is full, and why?**
     When the buffer fills to 4 items (`empty == 0`), the producer acquires `lock` via `pthread_mutex_lock(&lock)` and then blocks inside `sem_wait(&empty)`. The consumer attempts to dequeue an item, but blocks immediately on `pthread_mutex_lock(&lock)`. The producer cannot proceed because it needs the consumer to free a slot; the consumer cannot proceed because the producer holds the mutex. The program deadlocks indefinitely (exit code 124 under `timeout`).

## Part 2. The condition variable
- Program: `condvar.c`
- Answers to Observe questions:
  1. **In order.c (Lab 11) the semaphore itself remembered that the message was ready. Here, which variable remembers it?**
     The integer flag variable `ready` (set to `1` by `writer()` under `lock`) remembers the state. The condition variable `changed` does not store state; it is merely a wait/notification channel.
  2. **Replace "while (!ready)" with "if (!ready)", compile, run. Does it still work here?**
     Yes, it works in this minimal scenario because there are only two threads (one dedicated producer, one dedicated consumer), no competing consumers, and no spurious wakeups occur during this single run.
  3. **Then why do we write while? Give one reason why a thread can wake up and still find ready == 0:**
     POSIX condition variables adhere to Mesa monitor semantics:
     - **Spurious wakeups:** The OS kernel may wake a sleeping thread without any call to `pthread_cond_signal` (due to internal kernel signal handling or SMP scheduling events).
     - **Stolen state / Multiple consumers:** If multiple reader threads exist, another thread may wake up, re-acquire the mutex, consume the state, and set `ready = 0` before the current thread gains the lock.
     Re-evaluating the predicate inside a `while` loop guarantees correctness across all wakeups.

## Part 3. Readers and writers
- Program: `readers.c`
- Synchronization mechanism:
  - `room`: binary semaphore (`1`) ensuring exclusive access for writers or the reader group.
  - `rlock`: binary semaphore (`1`) protecting the shared reader count `readers`.
- Answers to Observe questions:
  1. **Three readers are inside at the same time, but a writer is always alone. Which two lines of reader() make that possible?**
     - Line 1: `if (++readers == 1) sem_wait(&room);` (the first reader entering locks the room against writers).
     - Line 2: `if (--readers == 0) sem_post(&room);` (the last reader exiting releases the room to allow waiting writers).
  2. **Why does the counter readers need its own lock (rlock)? What could go wrong without it?**
     The variable `readers` is shared among multiple concurrent reader threads. Modifying it (`++readers`, `--readers`) involves a non-atomic load-modify-store sequence. Without `rlock`, two readers entering simultaneously can experience a race condition where one increment is lost, causing both to believe `readers == 1` (locking `room` twice) or preventing `readers` from ever reaching `0` when exiting, permanently locking out writers.
  3. **Imagine readers that keep arriving without a pause. What happens to writer 2? (This problem has a name: starvation.)**
     Writer 2 suffers from **writer starvation** (resource exhaustion). Because existing readers hold `room` and subsequent readers join without releasing `room` (since `readers` never drops to 0), the writer blocks on `sem_wait(&room)` indefinitely.

## Part 4. Build a deadlock, then remove it
- Program: `deadlock.c`
- Answers to Observe questions:
  1. **In the stuck run, which thread holds which mutex, and which one is each thread waiting for? Draw the circle:**
     - Thread `one` holds mutex `A`, waits to acquire mutex `B`.
     - Thread `two` holds mutex `B`, waits to acquire mutex `A`.
     Wait-for graph circle:
     `Thread one` --[holds]--> `Mutex A` <--[waits on]-- `Thread two`
          |                                                  ^
          +------------------[waits on]--> `Mutex B` --[holds]--+
  2. **Remove both sleep(1) lines from the ORIGINAL version and run it ten times. Does it still always hang? Why is that worse, not better?**
     No, without `sleep(1)` it deadlocks intermittently (e.g. 7 out of 10 runs). This is significantly worse because intermittent, timing-dependent concurrency bugs evade automated unit testing, pass code reviews, and manifest non-deterministically under unpredictable production loads where debugging is difficult.
  3. **In one sentence: why can taking the locks in the same order never deadlock?**
     Enforcing a strict global lock acquisition hierarchy prevents circular wait dependencies, making cycles in the resource allocation graph mathematically impossible.
