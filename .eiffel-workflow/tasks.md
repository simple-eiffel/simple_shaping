# Implementation Tasks: simple_shaping (Phase 4)

**Status 2026-09-02 (end of day): PHASE 4 COMPLETE - Tasks 1-13 landed** (Task 13's simple_cairo half
shipped as simple_cairo 1.3.0). Runner: 72 passed, 0 skipped, 0 failed, 0 skeletal; three bidi
conformance tests record classified DirectWrite divergences. Evidence: evidence/phase4-compile.txt,
phase4-contracts-{before,after}.txt, per-task files. Next: the simple_widgets adoption (in flight) and
simple_chat's SW_CHAT_VIEW; then /eiffel.verify and /eiffel.harden as formal passes.

Ordered by dependency (approach.md's five-step order, widened by the two data tasks the emoji
subsystem needs and the Phase-5 obligations already registered in `testing/`). Placeholder
inventory of 2026-09-02: **40 `-- Phase 4:` body markers across 10 src files**, plus **7 unmarked
degenerate items** (4 SHAPING_FONT realization attributes, 2 EMOJI_DATA_TABLES stubs, 1 catalog
version expectation) and **10 Phase-5 markers in `testing/`** — 57 in all; every one is claimed by
a task below.

Standing rules for every task: **the contracts are the specification** — bodies satisfy them, and
a contract change is REPORTED (to Larry, with the reason) and never slipped in. Clean compile
(`rm -rf EIFGENs/simple_shaping_tests`, then `ec.sh test`), zero warnings, whole suite green with
the skipped count only ever going DOWN, tests added per task, CRLF preserved on every `.e` file,
README/CHANGELOG/docs updated when behavior actually lands. `spikes/dwrite/` is EVIDENCE: it is
read and copied from, never edited. Seam contracts may only be KEPT or STRENGTHENED by an
effecting (ensures) and KEPT or WEAKENED (requires) — never the reverse.

---

## Task 1: Promote the dwrite spike shim into `Clib/`; effect DWRITE_API + GDI32_API

**Files:** `Clib/simple_shaping_dwrite.h` (NEW — grown from `spikes/dwrite/Clib/dwrite_spike.h`),
`src/native/dwrite_api.e` (20 markers), `src/native/gdi32_api.e` (8 markers),
`simple_shaping.ecf` (add `<external_include location="$(SIMPLE_EIFFEL)/simple_shaping/Clib"/>`
to BOTH targets, as the spike ECF does for its own Clib)

**Features:** `DWRITE_API`: open, close, analyze, script_run_count/position/length/script,
bidi_run_count/position/length/level, create_font_face_from_hdc, release_font_face, shape_run,
glyph_count/id/advance/x_offset/y_offset, cluster_of_unit. `GDI32_API`: create_font,
create_memory_dc, select_font, text_ascent, text_descent, realized_face_name, delete_handle,
delete_dc.

### Acceptance
- [ ] `open` discharges `open_on_success: Result = is_open` and `failure_reported: not Result
      implies last_hresult /= 0`; `close` discharges `closed: not is_open`. The Phase-1
      `Hresult_not_implemented` returns disappear — failures now report the REAL HRESULT.
- [ ] `analyze` discharges `runs_on_success: Result implies (script_run_count >= 1 and
      bidi_run_count >= 1)` and `failure_reported` — a shim that returns success without
      populating BOTH run tables is a contract violation at the trust boundary (ISSUE 11).
- [ ] `shape_run` discharges `glyphs_on_success: Result implies glyph_count >= 1` and
      `failure_reported`; em size is the caller's `a_em_size_pixels` (same-N), `a_analysis`
      is the run's DWRITE_SCRIPT_ANALYSIS bytes passed through verbatim.
- [ ] Every index accessor keeps its `in_range` precondition honest against the live tables;
      `bidi_run_level` keeps `non_negative`; `glyph_count`/`script_run_count`/`bidi_run_count`
      keep `non_negative`.
- [ ] SINGLE-TRANSLATION-UNIT RULE: every `external "C inline use %"simple_shaping_dwrite.h%""`
      lives in `DWRITE_API` (the shim's state and COM objects are statics). GDI32_API's externals
      are plain Win32 calls and may bind directly. `gdi32.lib` links via `#pragma comment` in the
      header — zero new DLLs (NFR-004).
- [ ] Shim growth beyond the spike: `AnalyzeLineBreakpoints` (analyzer slot 6) sink + accessors
      for Task 4's `soft_breaks`; the spike's `spk_sink_breaks` is a stub today.
- [ ] NEVER-RAISES (NFR-011): every HRESULT is checked in C; failures cross the boundary as
      `False` + `last_hresult`, never as an exception, and never as a partly-filled table.
- [ ] Tests: a native round-trip test that opens, analyzes the D-015 probe string and reproduces
      the spike's measured facts (3 script runs / 2 bidi runs; Hebrew resolved level 1; Segoe UI
      at em 16 shapes shalom to 4 glyphs with positive advances, .notdef = id 0) — reported as an
      honest SKIP, never a pass, on a machine where `open` fails.
- [ ] `spikes/dwrite/` byte-identical afterwards; `EIFGENs` excluded; clean compile, zero warnings.

**Dependencies:** none. This is the unblocking task.

---

## Task 2: SHAPING_FONT realization, FONT_REGISTRY disposal, R1 probe, R5 effective digest

**Files:** `src/fonts/shaping_font.e` (4 degenerate attributes + the missing realization
features), `src/fonts/font_registry.e` (dispose_all + realization on first use),
`src/simple_shaping.e` (`cache_key`'s R5 marker + the effective-policy helper),
`src/config/font_list.e` (notes only — no contract change)

**Features:** SHAPING_FONT `realize` / `dispose` / `is_ready` / `ascent` / `descent`
(+ the R1 comparator query); FONT_REGISTRY `font`, `dispose_all`; SIMPLE_SHAPING `cache_key`
and a `{NONE}` effective-policy builder.

### Acceptance
- [ ] Realization runs the D-S03 chain: build LOGFONTW (`lfHeight = -pixel_size`),
      `GDI32_API.create_font`, `create_memory_dc`, `select_font`, `text_ascent`/`text_descent`,
      then `DWRITE_API.create_font_face_from_hdc` for the shaper's face.
- [ ] `SHAPING_FONT`'s invariants hold at every moment: `line_metrics: is_ready implies (ascent >
      0.0 and descent >= 0.0)`, `unrealized_has_no_metrics: not is_ready implies (ascent = 0.0 and
      descent = 0.0)`, `face_needs_realization`, `identity_positive`, `weight_range`. `line_height`
      keeps its `realized` precondition and `metric` ensure.
- [ ] `FONT_REGISTRY.font` keeps ALL of `identity`, `owned`, `registered`, `cached_result`,
      `model_exact`, `growth_bounded`, `idempotent` — one holder per identity, same object every
      call (D-S03 demands it so faces and per-font caches never split).
- [ ] `dispose_all` releases in order — IDWriteFontFace Release, restore the DC's original font,
      DeleteObject(HFONT), DeleteDC — before dropping identities; discharges `emptied` and
      `count_zero`; the registry invariant `fonts_are_owned` survives.
- [ ] R1: the existence probe compares `GDI32_API.realized_face_name` against the requested
      family (GDI silently maps unknown families); an absent family is dropped from the EFFECTIVE
      list with exactly one `Note_family_missing` per family per facade lifetime.
- [ ] R5: the facade's `cache_key` digests the POST-PROBE effective list. Because `cache_key` is
      evaluated inside `layout`/`layout_default` postconditions (`result_stored`,
      `cache_exact_when_room`), the effective digest MUST be memoized per configured-policy digest
      so assertion evaluation is cheap, deterministic, and probe-free after the first call — see
      Open question 3.
- [ ] Tests: realization/dispose round trip with handle-leak evidence (`count` back to 0); the R1
      probe against a family known absent on the build machine (e.g. "SBL Hebrew") and one known
      present ("Segoe UI"); the effective digest differs from the configured digest exactly when a
      family was dropped; same-identity calls return the same object.

**Dependencies:** Task 1.

---

## Task 3: DIRECTWRITE_BIDI_RESOLVER — AnalyzeBidi + UTF-16 mapping + real L2 reorder

**Files:** `src/directwrite/directwrite_bidi_resolver.e` (2 markers)

**Features:** `resolve`, `reorder`

### Acceptance
- [ ] `resolve` discharges every seam ensure: `never_void`, `one_level_per_character`
      (CODE-POINT count, not UTF-16 units), `levels_bounded` (<= Max_bidi_level),
      `paragraph_level_binary`, `forced_ltr`, `forced_rtl`, `empty_text_default`,
      `empty_auto_ltr` (UAX #9 P3: no strong character → paragraph level 0).
- [ ] UTF-16 BOUNDARY: this class owns the code-point ↔ UTF-16 mapping. The spike measured 18
      code points = 19 units for the D-015 string; a surrogate pair must land as ONE code point
      carrying its run's level. A dedicated mapping test is mandatory (it is the single most
      likely silent-wrong-answer site in the backend).
- [ ] `Direction_auto` = first-strong detection through the source callback's
      `GetParagraphReadingDirection`.
- [ ] `reorder` implements UAX #9 L2 for MIXED levels (reverse maximal runs from the highest level
      down to the lowest odd level) — the Phase-1 body only handled all-even and all-odd — and
      discharges `same_count`, `one_based`, `is_permutation`, `indices_in_range`, `ltr_identity`,
      and the ISSUE-13 oracle `rtl_reversal: is_all_odd (a_levels) implies is_reversal (Result)`.
- [ ] Tests: the mixed-level reorder cases (Hebrew + digits + Latin) with hand-computed
      permutations; the surrogate-pair mapping test; `test_bidi_conformance_samples` (AC-5) turned
      real through `BIDI_CONFORMANCE_HARNESS`.

**Dependencies:** Task 1.

---

## Task 4: DIRECTWRITE_SCRIPT_ITEMIZER — script × bidi intersection + AnalyzeLineBreakpoints

**Files:** `src/directwrite/directwrite_script_itemizer.e` (2 markers)

**Features:** `itemize`, `soft_breaks`

### Acceptance
- [ ] `itemize` is the INTERSECTION of AnalyzeScript and AnalyzeBidi run boundaries — the spike
      proved the necessity: AnalyzeScript alone merged Common-script characters into neighbors
      (3 script runs), and only the intersection with the 2 bidi runs produced the 4 items the
      seam must emit.
- [ ] Discharges `never_void`, `empty_iff_empty`, `first_at_start`, `contiguous`, `total_cover`,
      `items_nonempty`; positions are code-point space (UTF-16 mapping owned here, as in Task 3);
      each item carries ONE script id and ONE level.
- [ ] `SCRIPT_ITEM.analysis` carries the run's DWRITE_SCRIPT_ANALYSIS bytes VERBATIM to Task 5's
      shaper. Script ids stay engine-internal opaque ints (spike: Hebrew 36, Greek 30, Latin 49) —
      never compared across backends, never persisted, never mapped to our `Script_class_*`.
- [ ] Emoji-freedom is a CALLER DUTY, not a precondition (ISSUE 1): pictographs reaching this seam
      as .notdef IS FR-007 rung 3 and must not assert.
- [ ] `soft_breaks` effects over AnalyzeLineBreakpoints and discharges `one_per_character` and
      `no_break_before_first`.
- [ ] Tests: the D-015 string produces the spike's 4 items with the measured (pos, len, script,
      level); a Common-script-only string does not fragment; `soft_breaks` over Hebrew + spaces.

**Dependencies:** Tasks 1, 3 (the intersection consumes a real BIDI_RESULT; the shim's breakpoint
accessors arrive in Task 1).

---

## Task 5: DIRECTWRITE_GLYPH_SHAPER — GetGlyphs/GetGlyphPlacements + R3 tofu synthesis

**Files:** `src/directwrite/directwrite_glyph_shaper.e` (1 marker)

**Features:** `shape`

### Acceptance
- [ ] Real shaping at `a_font.pixel_size` (same-N, D-S03) over the font's IDWriteFontFace, with
      `isRightToLeft` = the item's level parity and the item's analysis bytes.
- [ ] Buffer discipline: first allocation `1.5n + 16` (A-C02 GUIDANCE ONLY — the seam promises NO
      glyph-count bound), grow-and-retry up to 3 attempts, then the R3 synthesis.
- [ ] Discharges `never_void`, `cluster_per_character`, `clusters_monotone_ltr`,
      `clusters_monotone_rtl`, `advances_match`, `advances_non_negative`, `complete_meaning`,
      `font_recorded`.
- [ ] `missing_glyph_count` = characters whose cluster's glyphs are ALL id 0 (the G2 probe
      verdict that Task 9 consumes) — and `is_complete` therefore means what
      `complete_meaning` says.
- [ ] R3 tofu-but-valid on any unrecoverable HRESULT: glyph id 0 per character, advance
      `pixel_size / 2`, **a trivial one-to-one cluster map REVERSED for RTL items** (R3 as amended
      by ISSUE 12 — an identity map violates `clusters_monotone_rtl` for any RTL item of 2+
      characters), never an empty item, never a raise, never a dropped range. The
      `Note_backend_error_recovered` is emitted by the caller (Task 11).
- [ ] Tests: shalom under Segoe UI reproduces the spike's ids/advances; an RTL item of 3+
      characters proves the monotone-RTL clause; a forced-failure path proves the tofu synthesis
      satisfies every clause.

**Dependencies:** Tasks 1, 2 (a realized font with a face), 4 (real items).

---

## Task 6 (data): Acquire the Noto Emoji assets; pin them per R4

**Files:** `assets/noto-emoji/png/128/*.png` (NEW), `LICENSE-ASSETS.md` (NEW),
`tools/emoji-acquisition.md` (NEW — the R4 record), `simple_shaping.ecf`/`.gitignore` as needed

### Acceptance
- [ ] The full Noto Emoji `png/128` set from ONE tagged release (Apache-2.0 — no attribution-UI
      requirement); `LICENSE-ASSETS.md` ships beside the exe in the runnable folder (NFR-009/AC-9).
- [ ] R4 record in `tools/`: release TAG + source URL + archive **sha256** + the Unicode emoji
      version the release states + the `emoji-test.txt` / `emoji-zwj-sequences.txt` versions
      downloaded to match. That version string is what Task 7 emits as the DR-013 constant.
- [ ] The ISSUE-5 padding rule is verified against the REAL filenames on disk:
      `emoji_u1f916.png`, `emoji_u00a9.png`, `emoji_u00ae.png`, `emoji_u0023_20e3.png` all exist;
      the unpadded spellings do not.
- [ ] Assets and tables move in ONE commit (DR-013/RISK-005) — never assets alone.

**Dependencies:** none (parallel with Tasks 1-5). Blocks Tasks 7 and 8.

---

## Task 7 (data): Generate EMOJI_DATA_TABLES (D-S08)

**Files:** `tools/generate_emoji_tables` (NEW script + its pinned inputs),
`src/emoji/generated/emoji_data_tables.e` (REGENERATED — `unicode_version` and
`is_extended_pictographic` are the two stubs today)

**Features:** `unicode_version`, `is_extended_pictographic`, plus the RGI-sequence lookups the
segmenter's longest match needs (additive to this generator-owned class — Open question 4)

### Acceptance
- [ ] `unicode_version` = the acquisition record's Unicode emoji version; `EMOJI_ASSET_CATALOG`'s
      invariant `tables_and_assets_pinned_together` then holds against the real assets.
- [ ] Tables are COMPILED IN — no runtime parsing of UCD files (D-S08); refreshing later is
      "re-run the generator + swap assets", one commit.
- [ ] Every structural predicate (`is_vs16`, `is_zwj`, `is_regional_indicator`,
      `is_emoji_modifier`, `is_combining_enclosing_keycap`) keeps its `definition` ensure
      unchanged; `is_emoji_starter` keeps its `definition` over the new real
      `is_extended_pictographic`.
- [ ] Generated file is CRLF, compiles with zero warnings, and carries the generator's provenance
      in its class note.
- [ ] Tests: spot-check membership (U+1F916 pictographic; U+0041 not; U+1F1E6 regional); the
      version constant matches Task 6's record exactly.

**Dependencies:** Task 6.

---

## Task 8: EMOJI_ASSET_CATALOG over real files; EMOJI_SEGMENTER's RGI ladder

**Files:** `src/emoji/emoji_asset_catalog.e` (production probe + the Phase-3 version expectation),
`src/emoji/emoji_segmenter.e` (1 marker), `src/simple_shaping.e` (create the catalog with a REAL
file probe instead of `make_without_assets`)

**Features:** catalog `make` with the production existence probe; segmenter `segment`,
`has_resolvable_single`

### Acceptance
- [ ] Full RGI longest-match segmentation (Q4 = MVP): VS16 pairs, ZWJ families, skin-tone
      modifiers, flag pairs, keycaps — table-driven off Task 7.
- [ ] The FR-007 ladder in ONE place: (1) full-sequence asset; (2) per-codepoint assets;
      (3) span stays PLAIN into the glyph path + `Note_emoji_degraded`. Every EMOJI segment
      emitted is therefore RESOLVED (DR-006), which is what makes `IMAGE_RUN.resolved`
      dischargeable.
- [ ] `segment` discharges `never_void`, `partition`, `emoji_resolved`, `empty_text`,
      `emoji_levels_inherited` (RTL image placement depends on it), `no_resolvable_single_left_plain`,
      `notes_only_grow`, and `appended_notes_are_degradations` (every appended note carries
      `Note_emoji_degraded`) — the ISSUE-6 accumulator is the ONLY channel rung 3 has.
- [ ] Catalog: `asset_key` keeps `noto_prefix`, `no_vs16_component`, `deterministic`;
      `has_asset` keeps the whole write-once memo frame (`resolution_cached`, `memo_only_grows`,
      `growth_bounded`, `domain_monotone`, `verdicts_write_once`, `negative_no_memo`);
      `asset_path` keeps `under_directory`, `is_png`, `memo_unchanged`, `key_derived`;
      `lower_hex` keeps `noto_minimum_padding`.
- [ ] Tests: `test_emoji_zwj_single_image_run` turned real (a ZWJ family = ONE segment with the
      joined key); U+00A9 and the keycaps resolve through the padded names; a sequence with no
      asset degrades PLAIN and appends exactly ONE note; the D-015 robot resolves to
      `emoji_u1f916` with a path under the configured directory.

**Dependencies:** Tasks 6, 7.

---

## Task 9: LIST_FONT_FALLBACK — the R11 per-call policy walk

**Files:** `src/fallback/list_font_fallback.e` (1 marker), `src/shaping_constants.e` (additive
pure helper `script_class_of` — Open question 6)

**Features:** `font_for`

### Acceptance
- [ ] The walk uses the PER-CALL `a_policy` (R11) and nothing captured at creation — this class
      holds no FONT_LIST at all. Procedure: probe `a_requested` by shaping; on gaps walk
      `a_policy.families_for (script_class)` in order, realizing candidates through `registry` at
      the SAME (weight, italic, pixel_size); exhaustion returns `a_requested` with
      `is_complete_coverage = False`.
- [ ] Discharges `never_void`, `same_pixel_size`, `same_style`, `no_silent_drop`, and
      `probes_counted: Result.probes_performed >= 0` — with `probes_performed` equal to the number
      of coverage SHAPES actually run (R7 amended). This class NEVER touches SHAPING_STATISTICS.
- [ ] Script-class bucketing is by CODEPOINT RANGE over the item's characters (Hebrew
      U+0590-05FF, Greek U+0370-03FF/U+1F00-1FFF, Latin, symbol, other) — NEVER by the engine's
      opaque `SCRIPT_ITEM.script_code`.
- [ ] Verdict cache: write-once per (script class, family), never keyed by policy identity, so it
      stays valid across per-call policies and never invalidates within a facade lifetime.
- [ ] Tests: `test_fallback_rescue` (AC-4) turned real — an uncovered codepoint renders from the
      first covering family, the choice reports the fallback face, exhaustion returns the
      requested font with `is_complete_coverage = False`; `probes_performed` counts exactly the
      probes run (0 from `NULL_FONT_FALLBACK`, already asserted).

**Dependencies:** Tasks 1, 2, 5.

---

## Task 10: LINE_LAYOUT_ENGINE — the real cluster-safe wrap

**Files:** `src/pipeline/line_layout_engine.e` (1 marker)

**Features:** `build_lines` (`fits_within` is already real and contracted)

### Acceptance
- [ ] Greedy accumulate; break ONLY at soft-break positions that are also cluster boundaries and
      NEVER inside an emoji segment (DR-007). See Open question 1 — the engine has no soft-break
      parameter, so the breaks must arrive as run granularity from the facade.
- [ ] R2 hanging whitespace: the breaking space belongs to the preceding line but its advance is
      excluded from the fit test — `fits_within` IS that rule and must be the ONLY fit comparison.
- [ ] A single unbreakable cluster/image wider than the width overflows its own line and is
      flagged `is_overflowing`, satisfying SHAPED_LINE's `overflow_shape: is_overflowing implies
      runs_model.count = 1`. Never split.
- [ ] Per finished line, `a_reorderer.reorder` over the line's run levels puts runs in VISUAL
      order (DR-002); line ascent/height = max over runs' fonts (glyph) and boxes (image), keeping
      `metrics_sane: height > 0.0 and ascent > 0.0 and ascent <= height`.
- [ ] Image-run boxes are sized AT LINE HEIGHT (FR-007) — square box, `advance_width = width`
      (IMAGE_RUN's `box_is_advance`).
- [ ] `No_wrap = 0` → exactly one unbounded line. Empty text → ONE line of count 0 (FR-N01/AC-6).
- [ ] Discharges `never_void`, `at_least_one_line`, `partition: lines_partition_text`.
- [ ] Tests: `test_wrap_cluster_safety` (AC-2) turned real — pointed Hebrew never splits
      base+niqqud, no emoji sequence splits, every character lands in exactly one line, overflow
      flagged only for a single unbreakable run.

**Dependencies:** Tasks 3 (reorder), 5 (real runs); the Open-question-1 ruling.

---

## Task 11: The facade pipeline — SIMPLE_SHAPING.layout, line_height, statistics

**Files:** `src/simple_shaping.e` (3 markers: `layout`, `line_height`, `cache_key` — `cache_key`'s
R5 half lands in Task 2)

**Features:** `layout`, `line_height` (and thereby `layout_default`, `measured_width`, `is_cached`)

### Acceptance
- [ ] The A-C03/DR-005 pipeline exactly: bidi over the FULL text → `segmenter.segment (a_text,
      bidi, l_notes)` → itemize PLAIN spans only → per item `font_fallback.font_for (a_text, item,
      requested, a_fonts)` (the PER-CALL policy, R11) then `glyph_shaper.shape` → cluster-safe
      greedy wrap → per-line visual reorder → SHAPED_LINEs → SHAPED_LAYOUT + notes → `cache.put
      (key, layout, a_fonts.digest)`.
- [ ] `base_direction` comes from bidi's resolution and satisfies SHAPED_LAYOUT.make's
      `direction_resolved`; `lines_cover_source` and **`runs_at_this_size: runs_at_layout_size
      (a_lines, a_pixel_size)`** hold — the ISSUE-8 same-N closure, which forces the REQUESTED
      font itself to have been realized at the layout's size (GLYPH_RUN's own `same_n_rule` proves
      nothing).
- [ ] Every `layout` ensure holds on both paths: `total_function`, `source_kept`,
      `parameters_kept`, `at_least_one_line`, `coverage`, `width_respected`, `cached_now`,
      `result_stored`, `cache_bounded_growth`, `cache_exact_when_room`, `hit_cache_frame`,
      `hit_shapes_nothing`, `hit_counted`, `miss_counted`; plus `layout_default`'s R6 restatement
      and `counted_once`.
- [ ] R7 counting, disjoint and exact: `record_shape_call` per RUN-PRODUCING shape;
      `record_fallback_probes (choice.probes_performed)` per seam-4 answer; `record_note` per note
      emitted; ZERO of both on a verified cache hit (AC-3's assertion).
- [ ] Degradations become data, never exceptions (NFR-011): `Note_fallback_exhausted` when
      `not choice.is_complete_coverage`, `Note_backend_error_recovered` when Task 5 synthesized
      tofu, `Note_emoji_degraded` from the segmenter's accumulator, `Note_family_missing` from
      R1, `Note_asset_missing` where the catalog expected a file.
- [ ] `line_height` = ascent + descent of the FIRST REALIZED general-list family at
      `a_pixel_size` (Q8), keeping `positive`, `cache_untouched`, `statistics_untouched`.
- [ ] `measured_width` (already a real delegation) then satisfies AC-10 — first line of a
      `No_wrap` layout, whitespace measured as shaped (R2).
- [ ] Tests: `test_headless_full_pipeline` (AC-7) and `test_measured_width_sums_advances` (AC-10)
      turned real; the AC-3 repaint test (200 identical calls, `shape_calls` unchanged);
      statistics disjointness proved with a probing fallback.

**Dependencies:** Tasks 2, 3, 4, 5, 8, 9, 10.

---

## Task 12: Phase-5 obligations carried forward (drive the skipped count to 0)

**Files:** `testing/lib_tests.e` (9 skeletal tests), `testing/bidi_conformance_harness.e`
(`run_character_case`), `testing/test_app.e` (registration), a fault-injecting shaper double
(NEW testing class), `testing/fixtures/` for BidiTest.txt + BidiCharacterTest.txt

### Acceptance
- [ ] `run_character_case` gets its real body (build the STRING_32, `resolve`, compare paragraph
      level and per-character levels skipping -1 positions, `reorder`, compare visual order) and
      keeps `counted`, `failure_recorded_unless_pass`, `pass_records_no_failure`. The Phase-1 stub
      records a FAILURE for every case on purpose — a fake pass would poison the gate.
- [ ] FULL run: BidiTest.txt (513,494 cases) + BidiCharacterTest.txt against
      DIRECTWRITE_BIDI_RESOLVER. This is the EIFFEL_BIDI_RESOLVER promotion gate (D-S06/NFR-008);
      divergence is REPORTED, never silently tolerated.
- [ ] `test_never_raises_fault_injection` (AC-8): a shaper double that fails hard on every call
      still yields a paintable layout whose degradations are enumerated in `notes` (R3).
- [ ] The same-N test: a layout built at size N has EVERY glyph run at N
      (`runs_at_layout_size`), including fallback runs.
- [ ] `test_d015_chat_line` (AC-1) headless: ‎`שלום 🤖 Χριστός`‎ → Hebrew visually RTL, U+1F916 as
      exactly ONE IMAGE_RUN with `asset_key = "emoji_u1f916"` and a path under the asset
      directory, Greek/Latin as GLYPH_RUNs, `covers_all_characters`. The PAINT half is Task 13.
- [ ] `test_whitespace_measures_positive_under_realized_font` (R2's measurement half, moved here
      from a vacuous postcondition by ISSUE 9): whitespace-only text under a REALIZED font
      measures > 0, and `measured_width ("a b") > measured_width ("ab")`.
- [ ] `test_bidi_conformance_samples`, `test_wrap_cluster_safety`, `test_fallback_rescue`,
      `test_emoji_zwj_single_image_run`, `test_headless_full_pipeline`,
      `test_measured_width_sums_advances` land with their owning tasks (3, 10, 9, 8, 11, 11);
      this task closes the remainder and drives `run_skeletal_test` registrations to zero. The
      runner's verdict line must end at "0 skeletal".

**Dependencies:** per test — Tasks 1-11.

---

## Task 13 (EXTERNAL, GATED): D-S07 simple_cairo glyph API + the paint bridge

**Files:** `D:/prod/simple_cairo` (SEPARATE REPO — Larry's gate, additive only):
`cairo_glyph_t` array marshalling, `CAIRO_CONTEXT.show_glyphs`, `glyph_extents`, `set_font_face`,
`CAIRO_FONT_FACE` wrapping `cairo_win32_font_face_create_for_logfontw_hfont` and
`cairo_win32_font_face_create_for_hfont` (headers already in its Clib). Then, in simple_shaping:
`src/bridge/shaping_cairo_bridge.e` and `src/bridge/emoji_surface_cache.e` (designed in
spec/04, NOT written in Phase 1), plus `SHAPING_FONT.cairo_face` / `has_cairo_face`.

### Acceptance
- [ ] simple_cairo's change is ADDITIVE and gated by Larry — this is not simple_shaping's code and
      no cairo internals leak above simple_cairo (layering: simple_widgets → simple_shaping →
      simple_cairo → cairo.dll).
- [ ] `SHAPING_CAIRO_BRIDGE.draw_layout` / `draw_line`: glyph runs → `set_font_face
      (run.font.cairo_face)` + `set_font_size (run.font.pixel_size)` (same-N, DR-009) +
      `show_glyphs`; image runs → `EMOJI_SURFACE_CACHE.surface (run.asset_path)` (existing
      `CAIRO_SURFACE.make_from_png` — zero WIC, A-C08) + `set_source_surface` + `paint`.
      Consumers never touch glyph arrays; cairo never re-measures.
- [ ] `SHAPING_FONT.has_cairo_face` becomes reachable and keeps `face_needs_realization`.
- [ ] AC-1's paint half and the AC-9 runnable-folder check.
- [ ] **If the gate slips (RISK-008): temporary externals inside simple_shaping's own `Clib/`
      (Task 1's header), migrated to simple_cairo later.** That fallback is named here so the
      slip cannot silently block painting — but it is a LAST resort, not a default.

**Dependencies:** Task 11 (a real layout to paint); Larry's D-S07 gate.

---

## External dependency tasks (tracked, not simple_shaping code)

- **simple_cairo D-S07 additive glyph API** — separate repo, LARRY'S GATE (Task 13's first half).
  Fallback: temporary in-library externals, RISK-008.
- **simple_widgets adoption** — `SW_PAINTER.draw_shaped_layout`, then SW_CHAT_THREAD's greedy wrap
  (sw_chat_thread.e) replaced by SHAPED_LINE layout. A SECOND gated repo change, coordinated at
  Phase 7; simple_chat's SW_CHAT_VIEW is the consumer behind it.
- **Noto Emoji tagged release download** (Apache-2.0) — Task 6's input; pinned by tag + URL +
  sha256.
- **Unicode data files** — `emoji-test.txt` (RGI) + `emoji-zwj-sequences.txt` for Task 7;
  `BidiTest.txt` + `BidiCharacterTest.txt` fixtures for Task 12. Versions pinned in `tools/`
  alongside the asset record (DR-013 lockstep).
- **OS-provided, nothing to ship:** `dwrite.dll` (LoadLibraryW at runtime, no import library) and
  `gdi32` (`#pragma comment`). Zero new DLLs is a hard requirement (NFR-004/AC-9).

---

## Open questions for Larry (Phase 3 found these; NOT decided here)

1. **LINE_LAYOUT_ENGINE has no soft-break channel.** `build_lines (a_text, a_width_pixels,
   a_pixel_size, a_runs, a_reorderer)` cannot see `SCRIPT_ITEMIZER.soft_breaks`, yet DR-007 says
   break only at soft-break positions that are cluster boundaries. Either (a) the FACADE pre-splits
   runs at break opportunities so the engine only decides which runs go on which line — no contract
   change, but run granularity gets finer (many small GLYPH_RUNs per line); or (b) `build_lines`
   gains an `a_breaks: ARRAY [BOOLEAN]` parameter — a CONTRACT CHANGE needing your gate.
   Recommendation: (a).
2. **Font realization has no contracted trigger or failure channel.** `SHAPING_FONT` has no
   `realize`/`dispose`; `FONT_REGISTRY.font`'s ensure never says `Result.is_ready`; yet
   `GLYPH_SHAPER.shape` and `FONT_FALLBACK.font_for` both REQUIRE `a_font.is_ready`, and R1's
   existence probe needs a realized-face-name comparator that no class exposes. Task 2 plans to ADD
   features (additive, no existing contract touched). Do you also want `FONT_REGISTRY.font`
   strengthened with `realized: Result.is_ready` — which IS a contract change?
3. **R5 makes `cache_key` probe-dependent, and `cache_key` runs inside postconditions.**
   `layout`/`layout_default` evaluate `cache_key (...)` in `result_stored` and
   `cache_exact_when_room`. Digesting the POST-PROBE effective list means assertion evaluation
   could trigger GDI probes. Task 2 plans a memo keyed by the configured digest (a benign
   write-once memo, like the catalog's declared CQS exception). Confirm the memo — or drop R5 back
   to the configured-list digest.
4. **EMOJI_DATA_TABLES exposes no RGI-sequence lookup.** Only `is_extended_pictographic` /
   `is_emoji_starter` exist; the segmenter's longest match needs generated sequence queries. The
   class is generator-owned, so adding them is regeneration rather than a contract edit — confirm
   no gate is needed.
5. **`script_class_of` does not exist.** LIST_FONT_FALLBACK's note calls for it; SHAPING_CONSTANTS
   has none. Task 9 plans to add it as a pure helper beside the other contract helpers (additive).
   Confirm.
6. **Documentation drift, code is right.** `intent-v2.md` Part A (G1 bullet, AC-5's
   `UNISCRIBE_BIDI_RESOLVER`) and `spec/07`'s body (`make`'s `uniscribe_wired` ensure, the Uniscribe
   dependency rows, "no Clib in MVP", the `src/uniscribe/` file structure) predate the 2026-09-01
   G1 FINAL ruling and Task 1's Clib. The source, `approach.md` and the Phase-2 amendment section
   are correct. Fix the originals in a doc pass, or keep Phase 2's convention (originals untouched,
   deltas appended as amendments)?
7. **`SHAPING_STATISTICS.record_fallback_probe` (singular) is now dead surface** — R7's amended
   mechanism uses `record_fallback_probes (a_count)` exclusively. Keep it (harmless, tested) or
   remove it (a contract change)?

## Gate decisions (Larry, 2026-09-02) — the seven open questions

Approved with the orchestrator's recommendations, verbatim:

1. **Soft-break channel for `LINE_LAYOUT_ENGINE.build_lines`:** the facade pre-splits runs at soft-break positions before calling `build_lines`. No contract change.
2. **Font realization trigger / failure channel:** additive `realize` and `is_ready` on SHAPING_FONT; `FONT_REGISTRY.font` may gain a strengthened postcondition — a REPORTED contract change, recorded in the Phase 4 evidence, never slipped.
3. **R5 and `cache_key`:** memoize the effective digest once per realized policy; `layout`'s postconditions read the memo. R5 stands.
4. **RGI-sequence lookup in EMOJI_DATA_TABLES:** the generator emits the queries; additive.
5. **`script_class_of`:** additive pure helper in SHAPING_CONSTANTS.
6. **Doc drift (Uniscribe wording in intent Part A / spec 07 body):** keep the amendment-only convention; originals untouched, amendments appended.
7. **`SHAPING_STATISTICS.record_fallback_probe` (singular, dead):** keep, marked obsolete in its note; removal deferred to the Phase 7 ship cleanup as a reported change.
