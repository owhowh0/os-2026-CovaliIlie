CC = gcc
CFLAGS = -Wall -pthread
TARGETS = race mutex sem order parking atomic

all: $(TARGETS)

race: race.c
	$(CC) $(CFLAGS) -o $@ $<

mutex: mutex.c
	$(CC) $(CFLAGS) -o $@ $<

sem: sem.c
	$(CC) $(CFLAGS) -o $@ $<

order: order.c
	$(CC) $(CFLAGS) -o $@ $<

parking: parking.c
	$(CC) $(CFLAGS) -o $@ $<

atomic: atomic.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGETS)

.PHONY: all clean
