# Unicode bidi conformance data — the pin

Phase 4 Task 3 (`DIRECTWRITE_BIDI_RESOLVER`) runs the committed sample through
`BIDI_CONFORMANCE_HARNESS` on every build. **Phase 4 Task 12 runs the FULL files
named here** - see "Full run - 2026-09-02" at the bottom for the totals, the
three divergence classes and the stride the routine suite uses.

## Pinned version

| | |
|---|---|
| Unicode version | **16.0.0** (`BidiCharacterTest-16.0.0.txt`, dated 2024-02-02) |
| Fetcher | `tools/fetch_bidi_tests.py` (verifies the sha256 before use) |
| Destination | `testing/fixtures/` — **git-ignored**, never committed |

| File | URL | Bytes | sha256 |
|---|---|---|---|
| `BidiCharacterTest.txt` | https://www.unicode.org/Public/16.0.0/ucd/BidiCharacterTest.txt | 6,880,649 | `d04a51a90052dcd71c4e91ee5b3a9d973ee35c12406b5a99875ac8163c8f2804` |
| `BidiTest.txt` | https://www.unicode.org/Public/16.0.0/ucd/BidiTest.txt | 7,959,988 | `93e5eb9d88ca89dcf895f5576486a3363762ad2aa8f2db2fa56fe60cb82b9520` |

```
python tools/fetch_bidi_tests.py            # download + verify
python tools/fetch_bidi_tests.py --sample   # + regenerate the committed sample
```

Why 16.0.0 rather than `latest`: a moving target cannot be a conformance oracle.
16.0.0 is the last version older than this machine's Windows build, so a
divergence is a real divergence and not a data file describing characters the OS
has never heard of.

## The committed sample

`testing/test_data/BidiCharacterTest.sample.txt` — **396 cases**, extracted by
`tools/fetch_bidi_tests.py --sample`.

Format, verbatim from the source file:

```
codepoints ; paragraph-direction ; paragraph-level ; levels ; visual-order
```

* `paragraph-direction`: `0` = LTR, `1` = RTL, `2` = auto (first strong)
* `levels`: one per input character; `x` = removed by rule X9
* `visual-order`: 0-based input indices of the KEPT positions, left to right

### Sampling rule — five ADDITIVE blocks, nothing filtered out

`BidiCharacterTest.txt` holds 91,707 data lines, and they are overwhelmingly
machine-generated paired-bracket cases: only **129** of the 91,707 contain a
digit at all, and only **28** use the auto paragraph direction. A plain stride
through the file would have produced a sample that was almost nothing but
brackets. So the sample is the union of five blocks, and **every rule below only
adds cases — none removes any**:

| Block | Rule | New cases |
|---|---|---|
| A | the first 45 data lines (the worked examples transcribed from UAX #9 itself) | 45 |
| B | paragraph direction 0 (LTR): 150 at a fixed stride through all 45,849 | 149 |
| C | paragraph direction 1 (RTL): 150 at a fixed stride through all 45,830 | 149 |
| D | paragraph direction 2 (auto): **all 28** | 10 |
| E | cases containing an EN (U+0030–U+0039) or AN (U+0660–U+0669): 45 at a stride through all 129 | 43 |

Duplicates between blocks are dropped (first occurrence wins) and file order is
preserved inside each block. Composition: 32 cases with EN digits, 25 with AN
digits, 38 with explicit embedding/override codes, 6 with isolates, 46 with
X9-removed positions.

**No case is excluded for being hard.** Bracket pairs, isolates, explicit
embedding codes and X9-removed positions all reach the harness, and what the
backend gets wrong is reported, never sampled away.

## Result on this machine (2026-09-02, Windows 11 Pro 10.0.26200)

```
396 sampled cases, 358 agreed, 38 disagreed
  [paired-bracket 30, explicit-formatting 8, unclassified 0]
L2 mismatches 0
```

`LIB_TESTS.test_bidi_conformance_samples` therefore reports an honest **SKIP**
with that reason — never a PASS — and prints all 38 mismatching cases with the
levels DirectWrite actually produced. It still asserts hard that the sample ran,
that **no** mismatch is unclassified, that our L2 agrees on all 396, and that the
agreeing count stays above a regression floor.

### Divergence class 1 — paired brackets (rule N0 / BD16), 30 cases

UAX #9 rule N0 (Unicode 6.3+) resolves a bracket pair by looking at the strong
type *inside* the pair AND at the established context *before* it.
`IDWriteTextAnalyzer::AnalyzeBidi` sets the pair to the enclosed strong
direction without that context check.

```
0028 2680 05D0 2681 0029 05D1 ; LTR paragraph
  Unicode : 0 0 1 0 0 1     the pair holds an R but the context is L -> N0 c.2 -> brackets take e = L
  DWrite  : 1 1 1 1 1 1     the brackets take the enclosed R
```

Every one of the 30 has this shape, and the effect cascades into the neutrals
that neighbor the brackets.

### Divergence class 2 — explicit directional formatting, 8 cases

Explicit embeddings/overrides (U+202A–U+202E) and isolates (U+2066–U+2069),
mostly the "overrides tightly flanking isolates" set added for the Unicode 8.0
clarifications.

```
202D 05D0 202B 05D1 202C 2068 05D2 2069 202B 05D3 202C 05D4 202C ; auto
  Unicode : x 2 x 3 x 2 3 2 x 3 x 2 x     the FSI sits at the outer level, its content one deeper
  DWrite  : 1 2 2 3 3 3 2 2 2 3 3 2 2     the initiator takes the inner level and the content the outer one

0627 202A 202C 0020 0031 002D 0032 ; LTR
  Unicode : 1 x x 1 2 1 2   W2 sees the AL across the removed LRE/PDF: the ENs become AN, so the ES stays neutral
  DWrite  : 1 1 1 1 2 2 2   the backward search stops at the removed characters, so W4 makes the ES a number
```

### What this means for simple_shaping

Neither class touches the D-015 acceptance line or ordinary chat text: both need
either a bracket pair wrapped around opposite-direction text, or explicit
embedding/override/isolate control characters, which chat messages do not carry.
The divergence is recorded rather than worked around, and it is exactly the
evidence that makes the D-S06 promotion gate for a future
`EIFFEL_BIDI_RESOLVER` worth opening: a from-scratch UAX #9 implementation would
close both classes.

`reorder` (rule L2) is ours, not DirectWrite's, and it agrees with Unicode on
all 396 sampled cases plus the hand-computed cases in
`LIB_TESTS.test_directwrite_l2_reorder_mixed_levels`.

---

# Full run — 2026-09-02 (Phase 4 Task 12)

The `EIFFEL_BIDI_RESOLVER` promotion gate (D-S06 / NFR-008), run in full for the
first time: **both** pinned Unicode 16.0.0 files, every case, against
`DIRECTWRITE_BIDI_RESOLVER` on Windows 11 Pro 10.0.26200.

```
python tools/fetch_bidi_tests.py                      # fetch + verify the sha256
SIMPLE_SHAPING_BIDI_STRIDE=1 ./EIFGENs/simple_shaping_tests/F_code/simple_shaping.exe
```

## Totals

| File | Cases run | Agreed | Disagreed | paired-bracket | explicit-formatting | segment-separator | **unclassified** | L2 mismatches | Unparsed lines |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `BidiCharacterTest.txt` | 91,707 | 86,376 | 5,331 | 5,292 | 39 | 0 | **0** | 0 | 0 |
| `BidiTest.txt` | 770,241 | 526,062 | 244,179 | 0 | 243,962 | 217 | **0** | 0 | 0 |
| **both** | **861,948** | **612,438** | **249,510** | 5,292 | 244,001 | 217 | **0** | **0** | **0** |

`BidiTest.txt` holds 490,846 data lines; each line's paragraph-direction bitset
expands to one, two or three cases, which is where 770,241 comes from.

**Every one of the 861,948 cases is accounted for.** Not one mismatch is
unclassified, and rule L2 — `reorder`, which is OURS and not DirectWrite's —
reproduces Unicode's visual order on every case of both files when it is fed the
oracle's own levels for the X9-kept positions.

### What that means for chat text

`BidiTest.txt` is exhaustive over sequences of bidi classes, so it is dominated
by inputs no chat line contains:

| Composition of the 770,241 cases | Cases | Diverged |
|---|---:|---:|
| contains an explicit formatting code (LRE/RLE/LRO/RLO/PDF/LRI/RLI/FSI/PDI) | 670,203 | 243,962 |
| no explicit code, but contains a segment separator (S) | 26,448 | 217 |
| neither | 73,590 | **0** |

DirectWrite agrees with UAX #9 on **100 % of the 73,590 cases that carry neither
an explicit directional formatting character nor a segment separator** — which is
the whole of ordinary text, the D-015 acceptance line included.

## Divergence class 3 — rule L1 around a SEGMENT SEPARATOR (NEW, found by this run)

Classes 1 and 2 are the ones Task 3 measured on the sample (paired brackets /
rule N0-BD16, and explicit directional formatting); their descriptions above
stand unchanged. The full run found a **third**, and it is named and counted
here rather than folded into "unclassified" and forgotten.

UAX #9 rule L1 resets a segment separator itself, and any **whitespace or
isolate formatting characters preceding** it, to the paragraph level — and
nothing else. `IDWriteTextAnalyzer::AnalyzeBidi` also resets the *non*-whitespace
neutrals that flank one:

```
R S ET AL          ; LTR paragraph
  Unicode : 1 0 1 1    W6 makes the ET an ON; N1 sees R-acting text on both
                       sides (AN/EN act as R), so the ON takes level 1
  DWrite  : 1 0 0 1    the ON AFTER the separator is reset along with it

R ES S AL          ; LTR paragraph
  Unicode : 1 1 0 1    only the separator itself resets
  DWrite  : 1 0 0 1    the ON BEFORE the separator resets too

AN S ET AL         ; LTR paragraph
  Unicode : 2 0 1 1
  DWrite  : 2 0 0 1
```

All 217 have that shape. Reaching it needs a TAB (U+0009), U+000B or U+001F
immediately beside a neutral — which no chat message and no shaped line in this
library carries. `BidiCharacterTest.txt` produced **zero** cases of this class in
its 91,707: it barely uses TAB, and the Task-3 sample used none at all, which is
why only the class file could find it.

## The paired-bracket predicate had to widen

Task 3's `has_bracket` asks about the six ASCII brackets — all its curated sample
contains — and its own note said a bracket outside them "would land in the
UNCLASSIFIED bucket and fail the suite, which is the intent". The full
`BidiCharacterTest.txt` duly produced one:

```
05D0 0020 2329 05D1 002E 0031 3009 ; LTR paragraph
  Unicode : 1 1 1 1 1 2 1        U+2329 pairs with U+3009
  DWrite  : 1 1 1 1 1 2 0
```

So Task 12's `LIB_TESTS.has_paired_bracket` carries the **whole** set: all 128
code points of Unicode 16.0.0 `BidiBrackets.txt`
(<https://www.unicode.org/Public/16.0.0/ucd/BidiBrackets.txt>, read once to
author the constant - the tests need no third data file at run time) with
`Bidi_Paired_Bracket_Type` `o` or `c`, as the 30 ranges they compress to
(`LIB_TESTS.bracket_ranges`, read off the data file rather than recalled). Task
3's narrower predicate is left untouched — its test still runs against its own
sample.

## BidiTest.txt: a different file format, and what it needed

`BidiTest.txt` does not spell code points. A data line is a list of **bidi class
names** plus a hex bitset of paragraph directions (`1` auto / `2` LTR / `4` RTL),
and the expectations come from the `@Levels:` and `@Reorder:` lines standing
above it. Three things were built for it:

1. **`BIDI_CONFORMANCE_HARNESS.run_case`** — judges the per-character levels and
   the L2 visual order and claims **no paragraph level**, because the file states
   none. Deriving one (P2/P3) inside the test would have meant checking the
   backend against the test's own arithmetic instead of against Unicode.
2. **The `@Levels:` / `@Reorder:` state machine**, plus a whitespace tokenizer:
   the file separates tokens with spaces *or tabs*, and `STRING.split` takes one
   separator character.
3. **One representative code point per bidi class** (`LIB_TESTS.class_code_point`):

   | | | | | | |
   |---|---|---|---|---|---|
   | L `U+0041` A | R `U+05D0` alef | AL `U+0627` arabic alef | EN `U+0030` 0 | ES `U+002B` + | ET `U+0024` $ |
   | AN `U+0660` arabic-indic 0 | CS `U+002C` , | NSM `U+0300` grave | BN `U+00AD` soft hyphen | B `U+2029` PS | S `U+0009` TAB |
   | WS `U+0020` space | ON `U+0021` ! | LRE `U+202A` | RLE `U+202B` | PDF `U+202C` | LRO `U+202D` |
   | RLO `U+202E` | LRI `U+2066` | RLI `U+2067` | FSI `U+2068` | PDI `U+2069` | |

   **ON is `!` and deliberately not a bracket.** The file's own header states that
   its expectations assume no bidi paired brackets are present; picking `(` would
   have made rule N0 apply to cases whose answers were computed without it, and
   turned every ON case into a false divergence. An unknown class name is counted
   as an UNPARSED line and fails the test — it is never skipped silently (the
   full run: 0 unparsed lines in either file).

## Routine suite vs. the full run

MEASURED on this machine (Windows 11 Pro 10.0.26200): the whole suite takes
**13 s** at the routine stride and **80 s** with `SIMPLE_SHAPING_BIDI_STRIDE=1`
(2026-09-02 13:41:56 -> 13:43:16, 861,948 cases). A clean compile already costs
about a minute, so adding 67 s to every verification cycle was judged the wrong
trade: the two conformance tests run a **documented stride** by default and the
full run is one environment variable away. The stride is a regression tripwire;
the FULL run - recorded above, and re-run whenever the backend, the Windows
build or the Unicode pin changes - is the gate.

| | BidiCharacterTest.txt | BidiTest.txt |
|---|---|---|
| routine stride | every 18th data line — 5,094 cases | every 150th data line — 5,130 cases |
| `SIMPLE_SHAPING_BIDI_STRIDE=1` | all 91,707 | all 770,241 |
| `SIMPLE_SHAPING_BIDI_STRIDE=<n>` | every n-th data line | every n-th data line |

The stride is taken in **file order with no content filter** — nothing is
excluded for being hard. Routine-stride result on this machine:

```
BidiCharacterTest.txt  5,094 cases, 4,783 agreed, 311 disagreed
                       [paired-bracket 310, explicit-formatting 1,
                        segment-separator 0, unclassified 0]; L2 mismatches 0
BidiTest.txt           5,130 cases, 3,489 agreed, 1,641 disagreed
                       [paired-bracket 0, explicit-formatting 1,640,
                        segment-separator 1, unclassified 0]; L2 mismatches 0
```

## It cannot silently pass

Both tests report an honest **SKIP** with the counts while any divergence
remains — agreement on every case is the only PASS. On top of that they assert
**hard**, and a violation fails the suite outright:

* the file really ran (≥ 5,000 / ≥ 4,500 cases);
* **zero unparsed data lines** — a line the parser cannot read is a failure, not
  a silent skip;
* UAX #9 **L2 agrees on every case run**;
* **zero UNCLASSIFIED mismatches** — a mismatch outside the three named classes
  is a NEW divergence class, and that is exactly the news this gate exists to
  deliver.

## The verdict for D-S06

A from-scratch `EIFFEL_BIDI_RESOLVER` would close all three classes; DirectWrite
closes none of them, and none of the three touches ordinary text. The promotion
gate now has its number: **612,438 of 861,948 cases agree, 249,510 diverge in
three named and measured ways, and nothing at all is unexplained.**
