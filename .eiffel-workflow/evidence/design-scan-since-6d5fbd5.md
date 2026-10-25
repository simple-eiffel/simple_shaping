# Design Scan (diff mode): simple_shaping --since 6d5fbd5 (main c63ebf1)
# Date: 2026-10-25. Read-only; nothing compiled, nothing edited.
# Subjects: src/pipeline/layout_cache.e, src/simple_shaping.e. Compared against all of src/.
# Question: is every contract on a per-call path O(1) or O(text)? Are the new postconditions true?

## Summary

| Area | Findings | High | Medium | Low |
|------|----------|------|--------|-----|
| Per-call contracts still superlinear | 6 | 4 | 2 | 0 |
| Truth of the new postconditions | 3 | 0 | 0 | 3 |
| Contracts the weakening dropped | 3 | 0 | 1 | 2 |
| **Total** | **12** | **4** | **3** | **5** |

The new clauses in layout_cache.e and simple_shaping.e are all O(1) except `touch`'s precondition (H1). The library still has the same disease elsewhere: the per-call paths below still build MML models or walk collections.

## HIGH

### H1. LAYOUT_CACHE.touch precondition and body are O(capacity) on EVERY cache hit
layout_cache.e `touch` (line 316-331 region): `require known: order.has (a_key)` walks `order` (512 keys by default, shaping_constants.e:213) and compares STRING_8 values (`compare_objects`, keys share a long digest prefix so each compare is near-full length); the body then does `order.start; order.prune (a_key)` (another O(n) value-compare scan) and `order.extend`. `item_verified` calls `touch` on every hit, `put` on every replace. So a hit costs two O(512) string scans, per cell, per frame; under assertions the precondition is the extra copy. This is the remaining cost in the hot path the 0.6.1 note describes. Proposal: replace `order` by a doubly linked recency chain (HASH_TABLE key -> node) or a generation counter per entry (touch = one `put` into a table; eviction scans for the minimum only on a MISS that is full, which is already a shaping-cost event). Until then, make the precondition `storage.has (a_key)` (O(1)) - `order_aligned` already ties the two.

### H2. SIMPLE_SHAPING.layout postcondition `at_least_one_line: not Result.lines_model.is_empty`
simple_shaping.e:179 (and `layout_default` via `layout`; `layout_styled` uses `lines.is_empty`, :228, correct). `lines_model` (shaped_layout.e:177-185) rebuilds an MML_SEQUENCE with `&` per line: O(lines^2) on every call INCLUDING hits. A 500-line paragraph pays about 125,000 sequence-append steps per hit. One-word fix: `not Result.lines.is_empty`. Same file also evaluates `cache_key` (O(text) UTF-8 conversion plus digest lookup) about nine times in `layout`'s postcondition (`is_cached` once, `old is_cached` four times, `cached_layout` once, plus `miss_counted`/`hit_counted` re-reads): O(text) but a 9x constant on the per-frame path; compute `old is_cached` once into a local via a single `old` clause or drop the `hit_*`/`miss_*` pairs to one implication each.

### H3. SHAPED_LAYOUT's invariant is O(layout) and runs on every non-attribute call
shaped_layout.e:200-206: `coverage_holds: covers_all_characters` (O(lines), via `lines_partition_text`, shaping_constants.e:322), `height_is_sum: total_height = sum_of_line_heights` (O(lines)), `same_n_closed: runs_at_layout_size (lines, pixel_size)` (O(lines x runs), shaping_constants.e:342-). Every call of `line_offset`, `respects_width`, `covers_all_characters`, `sum_of_line_heights`, `is_rtl`, `has_notes`, `lines_model` pays all three at entry and exit. The bridge's aligned draw calls `line_offset` once PER LINE per paint (simple_widgets via `SHAPING_CAIRO_BRIDGE.draw_layout_aligned`), so assertion-on paint is O(lines x (lines + runs)). Evidence: the file's own comment (glyph_run.e invariant note: "an invariant runs on every feature call... O(n^2)") says the rule that SHAPED_LAYOUT breaks. These three belong where they already are as well - `make`'s preconditions (:35-37) - and `layout`'s postconditions; keep only O(1) clauses in the invariant (`parameters_positive`, `direction_resolved`, `at_least_one_line`). The layout is immutable after `make`, so the invariant adds no information over the precondition.

### H4. EMOJI_SURFACE_CACHE.surface: eight O(n^2) MML comparisons plus an O(n) invariant, per emoji run per paint
emoji_surface_cache.e:117-124 builds `cached_model` (MML_MAP, `updated` per entry: O(n^2)) about nine times per call (`memo_only_grows`, `growth_bounded`, `domain_monotone`, `surfaces_write_once`, `miss_memoizes_nothing`, plus `old` copies). The bridge calls `surfaces.surface (a_run.asset_path)` for every image run on every paint (shaping_cairo_bridge.e:326). Invariant line 235 `across cached as s all s.is_valid end` adds O(n) per call. With 100 distinct emoji decoded, a frame with 20 emoji runs does thousands of MML steps per run. Same fix as LAYOUT_CACHE: O(1) queries (`has_surface`, `count`, `decode_count`) in the postconditions; the full model only on `wipe`/`dispose_all`; make the invariant O(1).

## MEDIUM

### M1. FONT_REGISTRY.font: six `fonts_model` comparisons per request (font_registry.e:104-108) plus invariant `across fonts as f all f.registry = Current` (:327)
Called per run on every cache miss and by `line_height`/`primary_line_height` (simple_shaping.e:313, 878), which hosts call per row (SW_SHAPING.line_height). Model build O(n^2) in the number of (family, weight, italic, size) entries, which grows with every distinct size and style. Same treatment: `has_font (key)` and `count` O(1) queries; `idempotent` only needs `count`. Rated MEDIUM because misses dominate and `line_height` per row is the only repeat path (still real: it pays this on every call).

### M2. EMOJI_ASSET_CATALOG.has_asset / asset_path: `resolved_model` clauses (emoji_asset_catalog.e:161-166, 180) and invariant `across resolved as p all p.starts_with (directory)` (:258)
Per emoji cluster on every cache miss, growing with the number of distinct emoji ever resolved (up to the full Noto set, about 3,700). Quadratic model builds per cluster. Same fix.

## LOW / observations

### Truth of the new postconditions (all checked by reading the bodies, not by running them)
- L1. `put` (layout_cache.e:200-221) `lru_victim_gone: (not old has (a_key) and old count >= capacity) implies (attached (old oldest_key) as al_victim implies not has (al_victim))` is TRUE: the not-present branch evicts `order.first` (the oldest) before inserting; the new key cannot equal the victim (it was absent). When the key IS present the antecedent is false, so the replace branch is not covered (correct, nothing is evicted). `count_exact` is true in both branches (invariant `bounded` keeps old count <= capacity). `old oldest_key` is a reference to the first key string, which `evict_oldest` removes from the list but does not mutate: safe.
- L2. `item_verified` `no_touch_on_miss: Result = Void implies (newest_key ~ old newest_key and oldest_key ~ old oldest_key)` is TRUE (a miss never reaches `touch`; a stale same-key entry is also left in place, not evicted). It is weaker than the old whole-sequence check: it would not notice a miss that reordered the MIDDLE of `order`. `count_unchanged` true: no removal on mismatch.
- L3. `SIMPLE_SHAPING.layout`: `miss_grows_when_room` true (put adds one when there is room); `hit_cache_frame` weakened to `cache_count = old cache_count` is true. `cached_layout` calls `cache.stored` with a freshly built key; `result_stored: cached_layout (...) = Result` is true for the plain path but note `layout_styled` with spans stores under a different key (Styles_tag) and its postcondition does not claim a store: consistent.

### What the weakening no longer catches (cheap clauses to add back, all O(1))
- L4. A hit must return the STORED object: `layout` could add `(old is_cached (...)) implies Result = old cached_layout (...)` (one `stored` lookup); today a hit that rebuilt an equal layout would pass.
- L5. `put` no longer says other entries are untouched. Cheap: `(not old has (a_key) and old count < capacity) implies oldest_key ~ old oldest_key` (a plain insert never changes who is next to go), and `(old has (a_key)) implies count = old count` (already in `count_exact`). Also a precondition on `put` that the layout belongs to the key (`a_layout.pixel_size > 0`) is available but the R8 text/size/width check is done at READ time, so storing a mismatched layout is merely wasted: low value.
- M3 (MEDIUM). `touch`'s `map_untouched` was weakened to `count = old count and stored (a_key) = old stored (a_key)`; it no longer states `order` still lists every key once. The invariant keeps `order_aligned: storage.count = order.count` (O(1)), which catches the duplicate-append bug `touch`'s comment describes (a duplicate makes the counts differ). Keep it; do NOT replace it with a model.

## Other per-call contract notes (O(text), acceptable, listed so they are not re-found)
- BIDI_RESOLVER.resolve ensures `levels_model.for_all` (bidi_resolver.e:43) and `reorder` ensures `is_permutation` as `across 1 |..| n all occurrences_in (Result, i) = 1` (:61): O(n^2) in the text length on every MISS (a 10,000-character paragraph is 10^8 steps with assertions). Only the miss path; consider `is_permutation` as a sorted-copy check.
- SCRIPT_ITEMIZER.itemize ensures (script_itemizer.e:77-83) walk the result: O(items), fine.
- SHAPING_STATISTICS `counters_model |=| (old counters_model).replaced_at (...)` (shaping_statistics.e:83-141): constant-size (5-element) sequence, O(1) in effect. `layout`'s `statistics.counters_model` clauses are also constant.
- FONT_LIST.families_for postcondition `script_families_model` (font_list.e:131) is O(entries) and runs per fallback lookup on a miss; small lists, fine.

## Recommended order
1. H2 (one-word fix, biggest win per line) and H1 `touch` precondition (`storage.has`).
2. H4 and M1/M2 as one "cache contracts" item: O(1) queries in `surface`, `font`, `has_asset`; models only on wipe/rebind.
3. H3: move SHAPED_LAYOUT's O(layout) invariant clauses to `make`'s preconditions (already there) and keep O(1) in the invariant.
4. H1 body: replace the LRU list with a counter or linked chain.
5. L4/L5 cheap clauses.
