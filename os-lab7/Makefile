CC = gcc
CFLAGS = -Wall -Wextra -O2

PROGS = run zombie redirect pipeline

all: $(PROGS)

run: run.c
	$(CC) $(CFLAGS) -o $@ $<

zombie: zombie.c
	$(CC) $(CFLAGS) -o $@ $<

redirect: redirect.c
	$(CC) $(CFLAGS) -o $@ $<

pipeline: pipeline.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(PROGS) out.txt

.PHONY: all clean
