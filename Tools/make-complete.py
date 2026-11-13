#!/usr/bin/env python3
"""Word completion's English list: Resources/Words/en-complete.tsv (word as written, tab, times).

Usage: Tools/make-complete.py <folder with en_50k.txt, 2of12full.txt and 5desk.txt>
    en_50k.txt                    (hermitdave/FrequencyWords 2018, CC BY-SA 4.0): the 50,000 commonest words of subtitles
    2of12full.txt, 5desk.txt      (12dicts by Alan Beale, public domain; SCOWL's alt12dicts)
A word of four letters or more seen 20 times; written with a capital when 5desk writes it so and 2of12full doesn't have
it lowercase (Mississippi, Hanoi), lowercase otherwise.
"""
import os, re, sys

src = sys.argv[1]
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "Words", "en-complete.tsv")
def words(name): return [l.split()[-1] for l in open(os.path.join(src, name), encoding="latin-1") if l.strip()]
lower = set(words("2of12full.txt"))
capital = {w.lower(): w for w in words("5desk.txt") if w[:1].isupper() and w.lower() not in lower}
with open(out, "w", encoding="utf-8") as f:
    for line in open(os.path.join(src, "en_50k.txt"), encoding="utf-8"):
        w, n = line.split()
        if int(n) >= 20 and len(w) >= 4 and re.fullmatch(r"[a-z]+", w):
            f.write(f"{capital.get(w, w)}\t{n}\n")
