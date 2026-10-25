# Cache-miss path: which contracts make layout_default superlinear

Read-only static analysis (no compile, no edits). C = characters, L = lines, R = runs,
G = glyphs. Test text: C = 9N, L = R = N, one script item (one paragraph), G ~ C.

Measured: contracts on, N=10 43 ms, N=100 27,000 ms (x640); contracts off 1.5 / 2.7 ms.

## Root cause: BIDI_RESULT.level rebuilds an MML model on every call

MML_SEQUENCE.& (simple_mml/src/mml_sequence.e:298-325) copies the whole sequence, so
building a model of k elements costs ~k^2/2 element copies. levels_model
(src/pipeline/bidi_result.e:79-90) is a `&` loop: ~C^2/2 copies per build.

### 1. bidi_result.e:62  `model_agrees: Result = levels_model [a_index]`  (postcondition of `level`)
- Cost per evaluation: O(C^2) (~C^2/2 = 405,000 element copies at C = 900, plus allocation/GC).
- Calls to `level` per paragraph, about 3C:
  - C in BIDI_RESULT.make post `levels_copied` (bidi_result.e:37-38, one `level (i)` per char);
  - ~C in DIRECTWRITE_SCRIPT_ITEMIZER.itemize body (directwrite_script_itemizer.e:130:
    `l_ids [i] /= l_id or else a_bidi.level (...)` - ids are equal across the paragraph, so
    the `or else` always evaluates `level`); NULL_SCRIPT_ITEMIZER does the same
    (null_script_itemizer.e:31);
  - C in itemize post `one_level_per_item` (script_itemizer.e:82 -> `levels_constant_within`,
    script_itemizer.e:103-115, one `a_bidi.level (i)` per char).
- Total ~3C x C^2/2 = 1.5 C^3. C=90: 1.1e6 copies (~40 ms at ~35 ns each; measured 43 ms).
  C=900: 1.1e9 copies (~27-40 s; measured 27,000 ms). THIS ONE CLAUSE ACCOUNTS FOR THE N^3.
- Fix (same meaning): `level` already reads `levels [a_index]`; the clause compares the array
  with a model built FROM THE SAME ARRAY, i.e. it only checks that the model builder works.
  Replace with `agrees_with_storage: Result = levels [a_index]` (O(1)), and test `levels_model`
  once in a unit test (count and per-element agreement), not in the postcondition of an O(1)
  accessor. Meaning lost: none that matters (tautology over one data structure).

### 2. bidi_result.e:37  `levels_copied: across 1 |..| count as i all level (i) = a_levels [...]`  (make post)
- Once per paragraph, C iterations, each calling `level` (offender 1) => C x C^2/2 = C^3/2 by
  itself, even if the other two call sites were fixed.
- Fix: compare arrays directly in the creation postcondition:
  `levels.count = a_levels.count and then across 1 |..| count as i all levels [i] = a_levels [a_levels.lower + i - 1] end`
  (O(C), same meaning).

### 3. script_itemizer.e:82 + :103  `one_level_per_item: across Result as it all levels_constant_within (a_bidi, it) end`
- O(C) by itself (each char once). It is the third caller of offender 1 (counted above) and
  becomes harmless once `level` is O(1). No change needed after fix 1.

## Secondary: one model build per clause, quadratic per item (C^2 term)

### 4. glyph_shaper.e:45-50  GLYPH_SHAPER.shape postconditions
`clusters_model.count`, `is_non_decreasing (clusters_model)`, `advances_model.count`,
`glyphs_model.count`, `advances_model.for_all`: 6 model builds (shaped_item.e:117-195), each
~G^2/2, G ~ C. shape runs TWICE per paragraph (fallback probe, list_font_fallback.e:130
`probe.shape (...).is_complete`, and the real shape in simple_shaping.e append_piece_runs).
12 builds x C^2/2 = 6 C^2 = 4.9e6 copies at C=900 (~0.15-0.2 s of the 27 s); the second-largest
term (O(C^2)).
Fix (meaning kept; models are definitional copies of the arrays):
- `cluster_per_character: Result.clusters.count = a_item.count` (SHAPED_ITEM invariant already
  states it);
- `clusters_monotone_*`: add SHAPED_ITEM.clusters_non_decreasing / clusters_non_increasing as
  plain array loops (O(n), no model) and call those;
- `advances_match: Result.advances.count = Result.glyphs.count` (already an invariant; drop);
- `advances_non_negative`: array loop `all_advances_non_negative` (O(G)).

### 5. bidi_resolver.e:42-47  BIDI_RESOLVER.resolve postconditions
`levels_model.count`, `levels_model.for_all`, `levels_model.is_empty`: 3 builds x C^2/2 per
paragraph = 1.5 C^2 (1.2e6 copies at C=900, ~40 ms). Fix: `Result.count = a_text.count` (O(1),
bidi_result.e:48), a new BIDI_RESULT.all_levels_bounded array loop (O(C)), and
`a_text.is_empty implies Result.count = 0`.

### 6. Other *_model uses on the miss path
Only items 1, 4, 5. `piece_policy` ensure (simple_shaping.e ~1075) uses `families_model |=| ...`
(O(families) ~ 5, styled path only) and `primary_line_height` builds `families_model` once per
layout (O(5^2)): harmless.

## Checked and NOT superlinear (already fixed or O(1) per call)
- SHAPED_LAYOUT invariant (shaped_layout.e ~line 168): O(1) (moved to make post in 0.6.2).
- SHAPED_LINE invariant `width_is_run_sum` (shaped_line.e ~103): O(runs on that line) = 1 here;
  evaluated on every qualified call (`l.width`, `l.height` in SHAPED_LAYOUT.make across): O(R)
  total. Caveat: a No_wrap paragraph (one line of R runs) pays O(R) per `width` call; the same
  fix as the layout invariant applies (make post `width_computed` already holds it; the
  invariant clause is redundant for an immutable object).
- GLYPH_RUN / SHAPED_RUN / IMAGE_RUN / TEXT_SEGMENT / SCRIPT_ITEM / SHAPED_ITEM invariants: O(1).
- SIMPLE_SHAPING / LAYOUT_CACHE / SHAPING_STATISTICS / FONT_REGISTRY / FONT_LIST / SHAPING_FONT
  invariants: O(1). layout / layout_default postconditions (simple_shaping.e:176-222):
  is_cached, cached_layout are hash lookups; covers_all_characters and respects_width are O(L)
  once.
- Once-per-paragraph O(R)/O(L) clauses, about 10 evaluations total (linear): lines_partition_text
  (shaping_constants.e:322; engine post line 200, wrapped_lines post line 1519, SHAPED_LAYOUT.make
  pre line 36 and post coverage_holds), runs_at_layout_size (shaping_constants.e:342; make pre
  line 37, post line 59), sum_of_line_heights, segments_partition and
  no_resolvable_single_left_plain (emoji_segmenter.e ~150-170).
- line_layout_engine.e: fits_within, unit_end, extend_with_unit, finished_line contracts are
  O(1) per call (`old a_line.count` is O(1)); is_one_unit in finished_line pre is O(runs on
  line) = 1 here.
- BIDI_RESOLVER.reorder post `is_permutation` (bidi_resolver.e:61): O(n^2) in the line run
  count n (occurrences_in per i). n = 1 per line here; quadratic for a No_wrap line or a long
  RTL line. Fix when it matters: one O(n) helper `is_permutation_of_1_to_n` with a seen-array.

## Possible multiplier outside this library (cannot confirm statically)
EiffelBase ARRAYED_LIST.extend (via BAG.extend) carries `one_more_occurrence: occurrences (v) =
old occurrences (v) + 1` (two O(n) scans). If EiffelBase is compiled with postconditions under
-keep, every `extend` in MML_SEQUENCE.extended_at (mml_sequence.e:315-325) is O(n) and a model
build is O(k^3) instead of O(k^2), making items 1-5 worse; and a_runs.extend / l_current.extend
in build_lines cost O(R) each (O(R^2) per paragraph = 1e4 steps at N=100, negligible). Fixing
items 1-2 removes the dominant part regardless.

## Expected effect (arithmetic, not measured)
Items 1+2 are ~99% of the model copies (3 C^3 / 2 vs ~7.5 C^2 for items 4-5). After fixes 1-2
the remaining model work is ~6e6 copies at C=900 (~0.2 s); fixing 4-5 as well makes the
contracts-on path O(C).

## Cannot be kept cheaply
Nothing. Every listed clause is a tautology over one structure (item 1; the count clauses of 4)
or restates per element / by array loop with identical meaning (items 2, 4, 5).

## Top 5 (ranked)
1. src/pipeline/bidi_result.e:62 `model_agrees: Result = levels_model [a_index]` - O(C^2) model rebuilt on each of ~3C `level` calls (C^3); use `Result = levels [a_index]`.
2. src/pipeline/bidi_result.e:37 `levels_copied: across ... level (i) ...` - C calls into #1; compare `levels [i]` with `a_levels [...]` directly (O(C)).
3. src/pipeline/glyph_shaper.e:45-50 - six `*_model` builds per `shape` (called twice per paragraph), C^2 each; use array-loop helpers on SHAPED_ITEM plus `.count` on the arrays.
4. src/pipeline/bidi_resolver.e:42-47 - three `levels_model` builds per `resolve`; use `Result.count` and an array-loop `all_levels_bounded`.
5. src/pipeline/script_itemizer.e:82/:103 `levels_constant_within` - O(C) itself but multiplies #1's cost per `level` call; harmless after #1 (keep).
