#!/usr/bin/env python3
"""Builds Resources/Words (Sage's autocorrect tables) from open word data. Run by hand, never by the build.

  Tools/make-words.py <folder>   the folder holding:
    vie*-sentences.txt: Leipzig Corpora Collection, the 100K sentence sets vie_wikipedia_2016, vie_wikipedia_2021,
      vie_news_2019, vie_news_2020, vie_news_2022, vie_mixed_2014, vie-vn_web_2015 (downloads.wortschatz-leipzig.de)
    vi_50k.txt, en_50k.txt                                                    (hermitdave/FrequencyWords, 2018)
    2of12full.txt                                  (12dicts by Alan Beale, public domain; in SCOWL's alt12dicts)

Writes vi-syllables.tsv (syllable, count), vi-pairs.tsv and vi-triples.tsv (syllables, count) and en-words.tsv.
"""
import collections, glob, os, re, sys, unicodedata

src, out = sys.argv[1], os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "Words")
VI = "aăâbcdđeêghiklmnoôơpqrstuưvxy" + "àáảãạằắẳẵặầấẩẫậèéẻẽẹềếểễệìíỉĩịòóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ"
syllable = re.compile("^[" + VI + "]{1,7}$")
word = re.compile(r"[^\W\d_]+")

ones, pairs, triples = collections.Counter(), collections.Counter(), collections.Counter()
for name in sorted(glob.glob(os.path.join(src, "vie*-sentences.txt"))):
    for line in open(name, encoding="utf-8"):
        line = unicodedata.normalize("NFC", line.split("\t", 1)[-1]).lower()
        for run in re.split(r"[^\w\s]|\d", line):          # punctuation and digits break a run of syllables
            tokens = run.split()
            for i, t in enumerate(tokens):
                if not syllable.match(t): continue
                ones[t] += 1
                if i + 1 < len(tokens) and syllable.match(tokens[i + 1]):
                    pairs[t + " " + tokens[i + 1]] += 1
                    if i + 2 < len(tokens) and syllable.match(tokens[i + 2]): triples[t + " " + tokens[i + 1] + " " + tokens[i + 2]] += 1
# Conversation (subtitles) next to the written text, at a tenth of its weight.
for line in open(os.path.join(src, "vi_50k.txt"), encoding="utf-8"):
    w, n = line.split()
    w = unicodedata.normalize("NFC", w).lower()
    if syllable.match(w): ones[w] += max(1, int(n) // 10)

# Only real Vietnamese syllables: an onset, a rhyme the language uses (seen 500 times or more over all syllables),
# and a stop ending (c, ch, p, t) only with the sharp or heavy tone. Foreign words and names that happen to be
# spelt with Vietnamese letters (the, and, mary) drop out.
TONES = {"\u0300": "f", "\u0301": "s", "\u0309": "r", "\u0303": "x", "\u0323": "j"}
ONSETS = sorted("b c ch d đ g gh gi h k kh l m n ng ngh nh p ph qu r s t th tr v x".split(), key=len, reverse=True)
def split(w):
    d = unicodedata.normalize("NFD", w)
    tone = next((TONES[c] for c in d if c in TONES), "")
    bare = unicodedata.normalize("NFC", "".join(c for c in d if c not in TONES))
    onset = next((o for o in ONSETS if bare.startswith(o) and len(bare) > len(o)), "")
    if onset == "gi" and not re.match("[aăâeêoôơuưy]", bare[2:]): onset = "g"   # gì, gìn: g + i
    return onset, bare[len(onset):], tone
rhymes = collections.Counter()
for w, n in ones.items(): rhymes[split(w)[1]] += n
def real(w):
    onset, rhyme, tone = split(w)
    if rhymes[rhyme] < 500 or not re.fullmatch("[aăâeêioôơuưy]{1,3}(c|ch|m|n|ng|nh|p|t)?", rhyme): return False
    if re.search("(c|ch|p|t)$", rhyme) and tone not in ("s", "j"): return False
    return True
ones = collections.Counter({w: n for w, n in ones.items() if real(w)})
pairs = collections.Counter({p: n for p, n in pairs.items() if n >= 3 and all(t in ones for t in p.split())})
triples = collections.Counter({p: n for p, n in triples.items() if n >= 4 and all(t in ones for t in p.split())})

os.makedirs(out, exist_ok=True)
with open(os.path.join(out, "vi-syllables.tsv"), "w", encoding="utf-8") as f:
    for w, n in ones.most_common():
        if n >= 3: f.write(f"{w}\t{n}\n")
with open(os.path.join(out, "vi-pairs.tsv"), "w", encoding="utf-8") as f:
    for p, n in pairs.most_common():
        if n >= 3: f.write(f"{p}\t{n}\n")
with open(os.path.join(out, "vi-triples.tsv"), "w", encoding="utf-8") as f:
    for p, n in triples.most_common(): f.write(f"{p}\t{n}\n")
# English: the words of 12dicts' 2of12full (real words, no names), each as often as the subtitles say (1 if never).
counts = {}
for line in open(os.path.join(src, "en_50k.txt"), encoding="utf-8"):
    w, n = line.split()
    counts[w] = int(n)
with open(os.path.join(out, "en-words.tsv"), "w", encoding="utf-8") as f:
    base = set()
    for line in open(os.path.join(src, "2of12full.txt"), encoding="latin-1"):
        w = line.split()[-1] if line.strip() else ""
        if re.fullmatch(r"[a-z]+", w): base.add(w)
    # Its inflections too (jumps, studied, analyzing), when the subtitles have them: a known word with an ending off.
    def stems(w):
        for end, put in (("ies", "y"), ("ied", "y"), ("ier", "y"), ("iest", "y"), ("ily", "y"), ("es", ""), ("s", ""),
                         ("ed", ""), ("ed", "e"), ("d", ""), ("ing", ""), ("ing", "e"), ("ly", ""), ("er", ""), ("er", "e"),
                         ("est", ""), ("est", "e"), ("r", ""), ("st", "")):
            if w.endswith(end) and len(w) - len(end) >= 2:
                stem = w[:-len(end)] + put
                yield stem
                if len(stem) > 2 and stem[-1] == stem[-2]: yield stem[:-1]     # stopped, bigger
    words = set(base) | {w for w in counts if re.fullmatch(r"[a-z]+", w) and any(x in base for x in stems(w))}
    for w in sorted(words): f.write(f"{w}\t{counts.get(w, 1)}\n")
