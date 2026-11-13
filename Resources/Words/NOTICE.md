# Autocorrect word lists

Made by `Tools/make-words.py`, read by `Sources/SageCorrect.swift`.

- `vi-syllables.tsv`, `vi-pairs.tsv`, `vi-triples.tsv`: Vietnamese syllables and the pairs and triples they're written in, counted in the Vietnamese sentence collections of the **Leipzig Corpora Collection** (Wikipedia, news, web; Universität Leipzig, https://wortschatz.uni-leipzig.de), with **FrequencyWords** `vi_50k` (Hermit Dave, CC BY-SA 4.0, https://github.com/hermitdave/FrequencyWords) at a tenth of its weight. Only counts are kept, no sentences.
- `en-words.tsv`: the words of **12dicts** `2of12full` (Alan Beale, public domain, from SCOWL's alt12dicts) and their inflections, counted by FrequencyWords `en_50k` (CC BY-SA 4.0).
- `en-complete.tsv` (word completion): FrequencyWords `en_50k` words of four letters or more, written with a capital where **12dicts** `5desk` writes them so (made by `Tools/make-complete.py`).
