CC = gcc
CFLAGS = -Wall -Wextra -pthread

PROGS = fire fire4

all: $(PROGS)

fire: fire.c
	$(CC) $(CFLAGS) -o $@ $<

fire4: fire4.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(PROGS)

.PHONY: all clean
