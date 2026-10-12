#!/bin/bash
# Lab 3: The Command Line: Shell, Pipes and Text Filters
# Track A: The real OS, from the outside, Linux
# Author: Ilie Covali (gr. FAF-243)

# Q1. How many requests failed?
grep -c FAIL access.log

# Q2. How many different pages were requested, and which?
cut -d' ' -f5 access.log | sort -u

# Q3. How many requests did each page get?
cut -d' ' -f5 access.log | sort | uniq -c

# Q4. Which user or users have the most failed requests, and how many?
grep FAIL access.log | cut -d' ' -f3 | sort | uniq -c | sort -rn | head -2

# Q5. How many requests did user3 make, and how many of them failed?
grep 'user3' access.log | cut -d' ' -f4 | sort | uniq -c

# Q6. Print the last 3 failed requests, showing only time and user.
grep FAIL access.log | tail -3 | cut -d' ' -f2,3

# Q7. Which login shells appear in /etc/passwd, and how many accounts use each? (field 7, separator :)
cut -d: -f7 /etc/passwd | sort | uniq -c | sort -rn

# Q8. PREDICT, then explain: why do ls /etc | wc -l and ls -l /etc | wc -l differ by exactly one?
ls /etc | wc -l ; ls -l /etc | wc -l

# Bonus (+1): with grep -E , print only the lines where the minute ends in 0 (10:00, 10:10, ...) and the request failed. How many are there?
grep -E ' 10:[0-9]0 .* FAIL' access.log
