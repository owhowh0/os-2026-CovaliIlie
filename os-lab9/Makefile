CC = gcc
CFLAGS = -Wall -Wextra -O2

PROGS = syscalls

all: $(PROGS)

syscalls: syscalls.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(PROGS) note.txt

.PHONY: all clean
