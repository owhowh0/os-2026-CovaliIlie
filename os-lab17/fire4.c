/* fire4.c - four threads of one process share the same memory.
 * All add to the same counter, a million times each, WITHOUT a lock.
 * Build: gcc -Wall -Wextra -pthread -o fire4 fire4.c
 * Run:   ./fire4
 */
#include <stdio.h>
#include <pthread.h>

#define N 1000000
#define NUM_THREADS 4
long counter = 0;              /* one variable, shared by all threads */

void *work(void *arg) {
    long id = (long)arg;
    printf("thread %ld sees counter = %ld\n", id, counter);
    for (int i = 0; i < N; i++)
        counter++;             /* NOT atomic: read, add, write */
    return NULL;
}

int main(void) {
    pthread_t th[NUM_THREADS];
    for (long i = 0; i < NUM_THREADS; i++) {
        pthread_create(&th[i], NULL, work, (void *)(i + 1));
    }
    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(th[i], NULL);
    }
    printf("expected: %d\n", NUM_THREADS * N);
    printf("counter:  %ld   (lost updates: the race)\n", counter);
    return 0;
}
