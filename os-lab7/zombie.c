#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>

/* creates a zombie child process by delaying parent waitpid */
int main(void)
{
    printf("parent: my PID is %d\n", getpid());
    fflush(stdout);

    pid_t pid = fork(); /* step 1: copy myself */
    if (pid < 0) {
        perror("fork");
        return 1;
    }

    if (pid == 0) { /* only the child runs this */
        printf("child: my PID is %d, my parent is %d\n", getpid(), getppid());
        fflush(stdout);
        execlp("ls", "ls", "-l", (char *)NULL); /* step 2: become ls */
        perror("exec");
        exit(127);
    }

    int status;
    sleep(20);                /* child finishes immediately while parent sleeps -> zombie */
    waitpid(pid, &status, 0); /* step 3: wait for the child and reap zombie */
    printf("parent: child %d ended with status %d\n", pid, WEXITSTATUS(status));
    return 0;
}
