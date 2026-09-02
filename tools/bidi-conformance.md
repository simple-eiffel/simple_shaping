# Unicode bidi conformance data — the pin

Phase 4 Task 3 (`DIRECTWRITE_BIDI_RESOLVER`). Phase 5 (`/eiffel.verify`) runs the
FULL files named here through `BIDI_CONFORMANCE_HARNESS`; Phase 4 runs the
committed sample.

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
