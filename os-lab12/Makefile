CC = gcc
CFLAGS = -Wall -pthread
TARGETS = prodcons condvar readers deadlock

all: $(TARGETS)

prodcons: prodcons.c
	$(CC) $(CFLAGS) -o $@ $<

condvar: condvar.c
	$(CC) $(CFLAGS) -o $@ $<

readers: readers.c
	$(CC) $(CFLAGS) -o $@ $<

deadlock: deadlock.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGETS)

.PHONY: all clean
