# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added - Phase 4 Task 9: SEAM 4 is real - the R11 per-call font-fallback walk
- **`LIST_FONT_FALLBACK.font_for` walks for real.** Step 1 probes `a_requested`
  BY SHAPING the item through the `GLYPH_SHAPER` seam - `SHAPED_ITEM.is_complete`
  is the verdict, exactly as G2/D-S05 specify. Step 2, only on a gap, walks
  `a_policy.families_for (script class)` in order, realizes each candidate
  through `registry` at the request's OWN (weight, italic, pixel_size) - which
  is how `same_pixel_size` and `same_style` are discharged - and takes the first
  that shapes complete. Step 3 is exhaustion: `a_requested` again with
  `is_complete_coverage = False` (DR-010 - tofu boxes plus a
  `Note_fallback_exhausted` upstream, never a silent drop, never Void).
- **The policy is the PER-CALL one (R11) and nothing else.** This class holds no
  `FONT_LIST` at all; the walked list arrives as an argument, so
  `layout (text, w, n, my_fonts)` now walks the list the consumer actually
  passed.
- **`SHAPING_CONSTANTS.script_class_of` (ADDED, Larry's gate decision 5)** plus
  its per-code-point half `script_class_of_code_point`. The FONT_LIST bucket is
  computed from the item's CODE POINTS - Hebrew U+0590-05FF and the Hebrew
  presentation forms U+FB1D-FB4F, Greek U+0370-03FF and polytonic U+1F00-1FFF,
  the Latin letter blocks, the punctuation and symbol blocks, everything else
  `other` - and NEVER from `SCRIPT_ITEM.script_code`, which is opaque and
  numbers differently on every backend. Where an item mixes classes the most
  specific one present wins (the constants are ordered so that this is the
  minimum).
- **An absent family counts as NOT COVERED, and costs no probe.** Absence is
  settled by `FONT_REGISTRY.family_exists` (R1's `GetTextFaceW` comparison)
  BEFORE anything is realized, because GDI substitutes a stand-in for an unknown
  family without saying so - and the substitute would often shape complete,
  which would "rescue" the item with a face nobody has.
- **Verdict cache: write-once per (script class, family), never per policy.**
  It therefore stays valid across per-call policies for the whole facade
  lifetime and is never invalidated. New query `LIST_FONT_FALLBACK.verdict_count`
  makes the growth statable; `font_for` gains (`ensure then`, additive)
  `verdicts_only_grow`, `verdict_recorded`, `probes_bounded_by_verdicts` and
  `rescue_comes_from_this_registry`.
- **`probes_performed` counts the coverage shapes actually RUN** (R7 amended) -
  a cached verdict skips the shape, so the same call made twice costs 2 probes
  then 0. This class never touches `SHAPING_STATISTICS`; the count rides home on
  the `FALLBACK_CHOICE` for the calling engine to add in.
- **Measured on this machine (Windows 11, EiffelStudio 25.02):** the four
  Hebrew letters of shalom requested under **Consolas** report `missing_glyph_count = 4`
  (Consolas has no U+0590-05FF block at all) and are rescued by **Segoe UI**,
  the next family in the policy, at a cost of exactly 2 probes; a policy of
  `[Consolas, Verdana, No Such Family QZX 9]` exhausts in 2 probes and 3
  verdicts (the absent family costs none) and hands back the requested Consolas
  with `is_complete_coverage = False`; and the same walk repeated costs 2 probes,
  then 0, then 0 again under a DIFFERENT `FONT_LIST` object.
- **`test_fallback_rescue` (AC-4) is REAL** - it was the skeletal Phase-5 marker
  and now runs through `run_backend_test` with an honest SKIP when the backend
  or either named face is missing. Joined by
  `test_fallback_exhaustion_keeps_the_requested_font`,
  `test_fallback_verdict_cache_is_policy_independent` and the machine-free
  `test_script_class_of_buckets_by_code_point`. Suite: **54 passed, 6 skeletal
  skipped, 1 backend-dependent skip, 0 failed** (was 50 / 7 / 1 / 0).


### Added - Phase 4 Task 5: SEAM 3 is real - glyph shaping over DirectWrite
- **`DIRECTWRITE_GLYPH_SHAPER.shape` shapes for real.** `GetGlyphs` (analyzer
  slot 7) + `GetGlyphPlacements` (slot 8) run over the item's font's
  `IDWriteFontFace` at `a_font.pixel_size` (same-N, D-S03 - no re-measuring on
  the paint side), with `isRightToLeft` taken from the item's level parity and
  the item's `DWRITE_SCRIPT_ANALYSIS` bytes passed back verbatim, exactly as
  Task 4's itemizer recorded them. Measured on this machine: shalom under
  Segoe UI at 16 px gives 4 glyphs (ids 2945/2932/2925/2933) with advances
  12.55/8.81/4.29/11.10 px - the spike's numbers - and `abc` gives ids
  68/69/70 with advances 8.14/9.41/7.39.
- **The cluster map is in CODE-POINT space.** DirectWrite's map is indexed by
  UTF-16 UNIT; each character's entry is read at its FIRST unit through
  `DIRECTWRITE_UTF16_MAPPING` (Task 4's helper, now inherited here too), which
  collapses a surrogate pair's low half away. U+1F916 is therefore ONE cluster
  entry over TWO units, not two entries.
- **RTL items come back in VISUAL order, and this is the interesting part.**
  DirectWrite delivers glyphs in LOGICAL order for both directions and a
  cluster map that is non-DECREASING for both - the Task-1 round trip shaped
  shalom with `isRightToLeft = TRUE` and measured the map `0 1 2 3`. Passed
  through unchanged that map violates the seam's `clusters_monotone_rtl` for
  any RTL item of 2+ characters. So an RTL item's glyph, advance and offset
  arrays are MIRRORED into visual order and the cluster map is mirrored with
  them: shalom now answers `4 3 2 1` over the reversed glyph array, which is
  the only arrangement where both the frozen clause holds AND `clusters` still
  names the first glyph of the character's own cluster. LTR items pass through
  untouched. A map that is not non-decreasing is not guessed at - it degrades
  through R3.
- **Coverage gaps are COUNTED, never thrown (G2).** `missing_glyph_count` is
  the number of characters whose whole cluster came back glyph id 0, and
  `is_complete` is `missing_glyph_count = 0`. The robot under Segoe UI shapes
  SUCCESSFULLY to one `.notdef` and reports `missing_glyph_count = 1` for its
  one code point - that is the probe verdict seam 4 consumes, not an error.
- **R3 tofu-but-valid on any unrecoverable failure** - no `IDWriteFontFace`, a
  backend that will not open, `shape_run` False after the shim's three
  grow-and-retry attempts, or an empty/unreadable glyph table. One box per
  character (glyph id 0), advance `pixel_size / 2`, zero offsets, and a
  trivial one-to-one cluster map REVERSED for RTL items (R3 as amended by
  ISSUE 12 - an identity map could never satisfy `clusters_monotone_rtl`).
  Never an empty item for a non-empty range, never a dropped range, never a
  raise; a `rescue` retries once and falls to the synthesis.
- **`DIRECTWRITE_GLYPH_SHAPER.last_shape_was_synthesized`** (new query) is the
  observable that separates the two all-zero cases: a REAL shape of an
  uncovered run is all zeros too, so the glyph ids alone cannot tell a
  coverage verdict from a backend error. Task 11 reads this flag before
  emitting `Note_backend_error_recovered`.
- **Buffer discipline (A-C02) stays where it can see the error.** First
  allocation `1.5n + 16` glyphs with grow-and-retry up to 3 attempts is inside
  the C shim's `ssd_shape_run` (Task 1) - the only place that sees
  `ERROR_INSUFFICIENT_BUFFER` from `GetGlyphs`. `shape_run` answering False
  means those attempts are spent, so the Eiffel answer to False is R3, not a
  second retry loop. No glyph-count upper bound is promised.

### Changed - Phase 4 Task 5
- `DIRECTWRITE_GLYPH_SHAPER.shape` WEAKENS the seam's precondition with
  `require else range_only`, dropping `font_ready` from its effective
  precondition (a lawful contract weakening in an heir, the same device
  `NULL_GLYPH_SHAPER` already uses; the seam's own clause is untouched). A
  seam that promises never to raise cannot answer an unrealized font with an
  assertion violation - R3 is the documented answer, and it needs only
  `pixel_size`, which the `SHAPING_FONT` invariant keeps positive whether the
  machine realized the font or refused it.

### Added - Phase 4 Task 4: SEAM 2 is real - script itemization over DirectWrite
- **`DIRECTWRITE_SCRIPT_ITEMIZER.itemize` is the script x bidi INTERSECTION.**
  `AnalyzeScript` (analyzer slot 3) runs over the span; the level half is NOT
  re-asked of DirectWrite but read out of the `BIDI_RESULT` seam 1 already
  resolved - that result is the oracle `one_level_per_item` is checked against,
  so no other level table would do. A new item begins wherever the opaque script
  id changes OR the level changes; splitting on the run INDEX instead would be
  wrong, because DirectWrite may deliver two adjacent runs carrying the same id
  and a boundary with neither change violates `boundaries_are_script_or_bidi`.
  The intersection is not decoration: the D-015 line
  (shalom + U+1F916 + Christos + abc) yields **3 script runs but 4 items** -
  `AnalyzeScript` folds the spaces and the robot's surrogate pair into the
  Hebrew run, and item 2 exists only because the bidi level changes.
- **Positions and counts are CODE POINTS.** The UTF-16 boundary is owned here,
  exactly as Task 3 owns it in the bidi resolver, and it is now FACTORED into a
  new `{NONE}` helper class `DIRECTWRITE_UTF16_MAPPING` (`unit_count`,
  `first_units`, `utf16_span`) that the itemizer inherits. Measured on the
  D-015 probe, 18 code points over 19 units:
  `(1,4) level 1`, `(5,3) level 0`, `(8,8) level 0`, `(16,3) level 0` - the
  code-point reading of the spike's unit table `[0,4) [4,8) [8,16) [16,19)`.
  A surrogate pair is ONE code point inside ONE item, and nothing after it
  shifts.
- **`SCRIPT_ITEM.analysis` carries the run's `DWRITE_SCRIPT_ANALYSIS` bytes
  verbatim** (`copy_script_run_analysis`, 8 bytes per run on this machine),
  from the run covering the item's first code point, ready for Task 5's
  `shape_run`. Script ids stay engine-internal opaque ints - measured 36 / 30 /
  49 for Hebrew / Greek / Latin, asserted only as pairwise distinct and stable,
  never as those values, never mapped to `Script_class_*`.
- **`soft_breaks` effects over `AnalyzeLineBreakpoints`** (slot 6), one flag per
  CODE POINT, `CAN_BREAK` and `MUST_BREAK` counting as opportunities. The whole
  text is analyzed rather than the item alone, because a UAX #14 opportunity is
  decided from the characters on both sides of a position and an item is
  routinely a mid-sentence slice; the shim leaves the script and bidi run tables
  alone, so this never disturbs an itemization in progress.
- **Emoji freedom stays a CALLER DUTY (ISSUE 1)**: a pictograph reaching this
  seam PLAIN - which is FR-007 rung 3, not a caller bug - itemizes like any
  other character and nothing here inspects, rejects or asserts about it.
- **NFR-011 degradation, never a raise**: when `DWRITE_API.open` or `analyze`
  fails, `itemize` falls back to the LEVEL-SPLIT answer (items split at bidi
  level changes alone, one opaque script id 0, empty analysis bytes) - the
  Phase-1 body, a lawful intersection, and the same shape
  `NULL_SCRIPT_ITEMIZER` produces; `soft_breaks` falls back to
  "a break after an ASCII space". Both also carry a rescue that takes that
  fallback once and only once.
- **Tests** (four, all through the honest-SKIP backend runner):
  `test_directwrite_itemizer_d015_intersection` (the four items in code points,
  ids pairwise distinct and stable across two calls, a full analysis record per
  item, the pictograph itemized rather than rejected),
  `test_directwrite_itemizer_common_script_does_not_fragment` ("123 456" stays
  ONE item), `test_directwrite_itemizer_soft_breaks_hebrew_and_spaces` (flags
  `00000100001000` - a break after each space, none before the first character
  or inside a word), and
  `test_directwrite_itemizer_surrogate_pair_inside_one_item` (8 code points, not
  9 units; the level change forces an item to start AT the pair; plus the
  `a_start` /= 1 sub-span path). Suite: **45 passed, 7 skipped, 0 failed.**


### Added - Phase 4 Task 2: fonts realize, release, and are probed for existence
- **`SHAPING_FONT` realizes** (`realize`, `dispose`, both `{FONT_REGISTRY}`-only,
  because native lifetime is the registry's - DR-012). The D-S03 chain runs for
  real: LOGFONTW with `lfHeight = -pixel_size` (same-N), `CreateFontIndirectW`,
  a private memory DC, `SelectObject`, TEXTMETRIC ascent/descent, `GetTextFaceW`,
  then `GdiInterop.CreateFontFaceFromHdc` for the shaper's `IDWriteFontFace`.
  `dispose` unwinds it in the ONE lawful order - face `Release`, restore the DC's
  original font, `DeleteObject (HFONT)`, `DeleteDC` - and returns the font to its
  unrealized state, so the same registry can realize the identity again.
  New queries: `is_realization_attempted`, `has_backend_face`, `is_family_realized`,
  `realized_family`, `font_handle`, `device_context`, `backend_face`.
- **`is_ready` means the GDI half**, exactly: an HFONT selected into a memory DC
  with a POSITIVE `tmAscent`. The `IDWriteFontFace` is best effort and reported
  separately by `has_backend_face`, so a machine that cannot load `dwrite.dll`
  still measures and paints and an item without a face degrades through R3's
  tofu synthesis rather than an assertion (NFR-011). A font that fails the GDI
  half keeps NOTHING - every handle is released inside `realize`.
- **`FONT_REGISTRY` realizes on first use and disposes on demand.** It owns the
  one `GDI32_API` and the one `DWRITE_API` its fonts realize through; `dispose_all`
  releases every font's handles BEFORE dropping the identities (dropping first
  would strand them for the life of the process). It deliberately does not close
  the DirectWrite factory: the shim's COM objects are process-wide statics, and
  closing them would `FreeLibrary` `dwrite.dll` underneath another registry's live
  faces.
- **R1 existence probe: `FONT_REGISTRY.family_exists`.** GDI silently substitutes
  for a family it does not have, so the requested name proves nothing - the probe
  realizes the family transiently and compares `GetTextFaceW`'s answer, releasing
  every handle before it returns. Verdicts are memoized per family (case-folded).
  Measured here: GDI hands back **"Arial" for "SBL Hebrew"**, and the probe's
  verdict over the default policy's ten families matches
  `InstalledFontCollection` exactly.
- **R5: `SIMPLE_SHAPING.cache_key` digests the POST-PROBE effective list**, via the
  new public query `effective_digest`, **memoized per configured-policy digest**
  (gate decision 3). `cache_key` is evaluated inside `layout`'s postconditions, so
  the memo is what keeps assertion evaluation cheap, deterministic and probe-free
  after the first call. The R8 entry-side check uses the same effective digest -
  a key claiming effective identity while verification demanded configured
  identity would demote every hit R5 exists to create. Consequence: **two policies
  that differ only in a family this machine does not have now share one cache
  entry.** `missing_family_count` reports how many distinct families were dropped;
  exactly one `Note_family_missing` is built per family per facade lifetime
  (attaching it to a layout's notes is Task 11's line).
- **Tests**: `test_font_realization_round_trip` (realize -> `count` back to 0 ->
  every handle back to `default_pointer` -> re-realize works),
  `test_family_existence_probe` (SBL Hebrew verified absent through
  `realized_face_name` first, then the probe's verdict; honest SKIP if the machine
  owns it), `test_effective_digest_drops_absent_families` (effective differs from
  configured exactly when a family drops, memo stability, one note per family,
  and one shared cache entry). Machine-dependent tests skip honestly through a
  `begin_machine_test` protocol, never as passes. Suite: **26 passed, 9 skipped,
  0 failed.**

### Changed - Phase 4 Task 2
- **`FONT_REGISTRY.font` gained one postcondition clause**, `realized_on_first_use:
  Result.is_realization_attempted` (a REPORTED contract change under Phase 3 gate
  decision 2; see `.eiffel-workflow/evidence/phase4-task2.txt`). It deliberately
  does not promise `Result.is_ready`: realization is a native operation a machine
  may refuse, and promising its success would turn a GDI failure into a
  postcondition violation escaping `layout`.

### Added - Phase 4 Task 1: the native surfaces are real (nothing above them is, yet)
- **`Clib/simple_shaping_dwrite.h`** - the production DirectWrite + GDI C shim,
  grown from `spikes/dwrite/Clib/dwrite_spike.h` (which stays byte-identical as
  evidence). Plain C, hand-declared COM vtables, `dwrite.dll` via
  `LoadLibraryW`, `gdi32.lib` via `#pragma comment` - **zero new DLLs**
  (NFR-004). Every buffer is heap-allocated and grows on demand; the spike's
  fixed caps would have truncated a real chat line.
- **`DWRITE_API` bodies are effective**: `open`/`close`/`analyze`, the script
  and bidi run accessors, `create_font_face_from_hdc`/`release_font_face`,
  `shape_run` (em size = the caller's `a_em_size_pixels`, same-N; the run's
  `DWRITE_SCRIPT_ANALYSIS` bytes passed through verbatim; 1.5n+16 first
  allocation with grow-and-retry), the glyph accessors and `cluster_of_unit`.
  The Phase-1 `Hresult_not_implemented` returns are gone: `last_hresult` now
  carries the HRESULT DirectWrite actually returned. Every HRESULT is checked
  in C and every failure resets the affected table, so a failure crosses the
  boundary as `False` + `last_hresult` - never an exception, never a
  partly-filled table (NFR-011), and `runs_on_success`/`glyphs_on_success`
  cannot be violated from the native side (ISSUE 11).
- **`DWRITE_API` grew a line-breaking surface** (additive; no existing contract
  touched): `analyze_line_breakpoints` over `AnalyzeLineBreakpoints` with a
  REAL `SetLineBreakpoints` sink - the spike's was a stub - plus
  `breakpoint_count`, `break_condition_before`/`_after`, `is_break_whitespace`,
  `is_break_soft_hyphen`. `SCRIPT_ITEMIZER.soft_breaks` consumes these.
  Also `script_analysis_size` + `copy_script_run_analysis`, so `SCRIPT_ITEM`
  can carry a run's analysis bytes verbatim back into `shape_run`.
- **`GDI32_API` bodies are effective**: `create_font` (LOGFONTW,
  `lfHeight = -pixel_size`, `CreateFontIndirectW`), `create_memory_dc`,
  `select_font`, `text_ascent`/`text_descent`, `realized_face_name`
  (`GetTextFaceW` decoded to `STRING_32` - the R1 existence comparator),
  `delete_handle`, `delete_dc`. Plain Win32 externals over `<windows.h>`;
  they deliberately do NOT include the shim header, whose state is `static`.
- **ECF**: `<external_include location="$ECF_CONFIG_PATH/Clib"/>` on BOTH
  targets (ECF-relative, so it resolves in a worktree and for a consumer that
  vendors the library).
- **Test**: `test_dwrite_native_round_trip` drives the whole chain against the
  D-015 probe string and reproduces the spike's measured facts - 3 script runs
  / 2 bidi runs, Hebrew resolved level 1, 19 breakpoints, Segoe UI realized at
  em 16, shalom shaping to 4 glyphs with positive advances and an identity
  cluster map, and `.notdef` = glyph id 0 on the uncovered emoji run. On a
  machine where `open` fails it reports an honest SKIP in its own counter,
  never a pass and never inflating the Phase-5 skeletal count. Suite: **23
  passed, 9 skipped, 0 failed**.
### Added - Phase 4, Tasks 6 and 7 (emoji data: assets acquired and tables generated)
- **The Noto Emoji artwork ships.** `assets/noto-emoji/png/128/` - 3,768 PNG
  files, 21,196,457 bytes - extracted from ONE tagged release,
  googlefonts/noto-emoji `v2.051` ("Unicode 17.0 update mk1"), archive sha256
  `04f3d1e5605edebebac00a7a0becb390a4a3ead015066905b27935b30c18e745`. The
  padding rule Phase 2 caught (ISSUE 5) is now verified against the real files:
  `emoji_u00a9.png` and `emoji_u0023_20e3.png` exist, `emoji_ua9.png` and
  `emoji_u23_20e3.png` do not.
- **`LICENSE-ASSETS.md`** at the repository root - the artwork's license and
  attribution, written to ship beside the exe (NFR-009/AC-9). Upstream's own
  root `LICENSE` and `README` disagree at this tag (OFL 1.1 vs Apache-2.0), so
  it carries BOTH texts and says why.
- **`tools/emoji-acquisition.md`** - the R4 record: tag, URL, archive sha256,
  file/byte counts, the Unicode emoji version the release states and where that
  claim comes from, plus the three pinned Unicode data files with their versions
  and sha256s. `tools/emoji-test.txt`, `tools/emoji-zwj-sequences.txt` and
  `tools/emoji-data.txt` (all Emoji 17.0) are committed byte-exact.
- **`tools/generate_emoji_tables.py`** - the D-S08 generator. `--check` exits 1
  when `src/emoji/generated/emoji_data_tables.e` is stale against its inputs.
- **`EMOJI_DATA_TABLES` is generated and real.** `unicode_version` is `"17.0"`
  (was `"UNPINNED-0.0.0"`), so `EMOJI_ASSET_CATALOG`'s
  `tables_and_assets_pinned_together` invariant now pins something.
  `is_extended_pictographic` is a binary search over 156 merged ranges compiled
  into the class - no UCD file is read at run time (D-S08).
- **Additive RGI lookups on `EMOJI_DATA_TABLES`** (Phase 3 gate decision 4, the
  generator emits them; no existing contract touched): `is_rgi_sequence`,
  `longest_rgi_prefix_length`, `without_vs16`, `codepoints_of`, and the
  constants `Rgi_sequence_count` (3,944), `Max_rgi_sequence_length` (9) and
  `Max_rgi_prefix_length` (10). Keys are canonical - VS16 is dropped before
  lookup, exactly as `EMOJI_ASSET_CATALOG.asset_key` drops it - so every lawful
  spelling of a sequence answers the same. These are what Task 8's longest match
  will call.
- **Four real tests** (`test_emoji_tables_pinned_version`,
  `test_emoji_tables_extended_pictographic`, `test_emoji_tables_rgi_sequences`,
  `test_asset_catalog_over_real_assets`), the last one running the catalog over
  the ACTUAL asset directory with a real file probe. Suite: **26 passed, 9
  skipped, 0 failed** (was 22/9/0; the skipped count did not move).

### Known - recorded, not decided here
- Flag PAIRS have no PNG in `v2.051` (upstream keeps waved flags as SVG under
  `third_party/`), so a flag sequence lands on rung 2 of the FR-007 ladder: two
  regional-indicator letter tiles.

### Added - Phase 4, Task 8 (emoji segmentation is real: the FR-007 ladder)
- **`EMOJI_SEGMENTER.segment` performs full RGI longest-match segmentation.**
  One left-to-right pass; at each position the candidate is
  `EMOJI_DATA_TABLES.longest_rgi_prefix_length`, so VS16 pairs, ZWJ families,
  skin-tone modifiers, flag pairs and keycaps all come out of one generated
  lookup (Q4 = MVP). Emoji segments carry the RESOLVED level of their first
  character, and PLAIN spans are built as the gaps between them, which makes
  `partition` true by construction.
- **The FR-007 ladder lives in ONE place** (A-C06), in that class:
  (1) the whole sequence has an asset -> ONE emoji segment with the joined key;
  (2) else every COMPONENT images on its own -> one segment per component;
  (3) else the span stays PLAIN on the glyph path and EXACTLY ONE
  `Note_emoji_degraded` covering it is appended to the caller's accumulator
  (ISSUE 6). Every emoji segment emitted is therefore RESOLVED (DR-006), which
  is what makes `IMAGE_RUN.resolved` dischargeable.
- **Rung 3 still lifts what it can.** A sequence whose full asset is missing and
  whose components only PARTLY resolve keeps its imaged characters as images and
  leaves only the rest plain - otherwise `no_resolvable_single_left_plain` would
  be violated by the degradation itself.
- **Glue never reaches the shaper.** VS16, ZWJ and the TAG characters
  (U+E0020..U+E007F) ride with the base they join, so a degraded family never
  hands DirectWrite a joiner to render as a tofu box. Worked example: the
  England flag has no asset in `v2.051`, so it becomes ONE black-flag image over
  all seven characters.
- **Production wiring**: `SIMPLE_SHAPING` now builds its catalog with
  `EMOJI_ASSET_CATALOG.make` and a REAL file-existence probe (new
  `EMOJI_FILE_PROBE`, a `RAW_FILE.exists` closure) instead of
  `make_without_assets`. The probe is an object because an agent closed on
  `Current` is not creatable inside a creation procedure under void safety.
- **`SIMPLE_SHAPING.default_asset_directory`** (new, additive) - AC-9's
  runnable-folder rule made computable: `assets\noto-emoji\png\128` resolved
  against the directory of the RUNNING EXECUTABLE, never the working directory.
  `set_asset_directory` remains the consumer override; the rule is documented in
  the facade's new `assets` note.
- **`EMOJI_ASSET_CATALOG.Asset_unicode_version`** (new constant, `"17.0"`): the
  DR-013 expectation now comes from the ASSET acquisition record instead of
  being read back off the tables, so `tables_and_assets_pinned_together` can
  actually fire when tables and artwork drift apart (RISK-005).
- **Nine real tests** - the ZWJ family (`test_emoji_zwj_single_image_run` was
  skeletal and is real now), the D-015 line, the ISSUE-5 padded singles and the
  keycap, rung 2 over the US and England flags, VS16 and skin-tone spellings,
  rung 3's single note, rung 3's partial lift, level inheritance, and the AC-9
  default directory. Suite: **36 passed, 8 skipped, 0 failed** (was 27/9/0 - the
  skeletal count went DOWN by one).


### Added - Phase 4 Task 3: seam 1 (bidi) is real end to end

- **`DIRECTWRITE_BIDI_RESOLVER.resolve` runs `AnalyzeBidi` for real.** The
  UTF-16 boundary lives here and nowhere else: the text is walked once to map
  each CODE POINT to the index of its FIRST UTF-16 unit, the run levels are
  spread over units, and one level is read back per code point - so a surrogate
  pair lands as ONE code point carrying its run's level. Measured on the D-015
  line: **18 code points, 19 UTF-16 units**, levels `111100000000000000` under
  a forced-LTR paragraph.
- **`Direction_auto` is real first-strong detection (UAX #9 P2/P3).**
  DirectWrite has no facility for it - `DWRITE_READING_DIRECTION` has only LTR
  and RTL, and `AnalyzeBidi` takes the paragraph level as an INPUT - so the scan
  is ours: P2's isolate-skipping walk (U+2066/2067/2068 ... U+2069, recognized
  by value), with each candidate's strong class asked of DirectWrite itself by
  analyzing that one code point in isolation and reading the level signature
  back (LTR paragraph: R/AL -> 1; RTL paragraph: L -> 2; an RLM-prefixed third
  probe separates strong L from a European number, which rule W7 otherwise makes
  look identical). No strong character -> paragraph level 0, which is P3.
- **`DIRECTWRITE_BIDI_RESOLVER.reorder` implements UAX #9 L2 for MIXED levels** -
  from the highest level down to the lowest odd level, reverse every maximal run
  at that level or higher. The Phase-1 body handled only all-even and all-odd.
  Zero native calls: a line's visual order is arithmetic.
- **`DWRITE_API` grew a settable paragraph reading direction** (additive; no
  existing contract touched): `set_paragraph_reading_direction` /
  `paragraph_reading_direction` / `Reading_direction_ltr` /
  `Reading_direction_rtl`, over `ssd_set_reading_direction` in the shim. The
  spike's analysis source answered LEFT_TO_RIGHT unconditionally, so a
  forced-RTL paragraph could not be expressed at all.
- **Degradation, never an exception (NFR-011):** when DirectWrite cannot be
  opened or `analyze` fails, `resolve` returns the all-paragraph-level result -
  a lawful `BIDI_RESULT` that discharges every seam ensure, and the same shape
  `NULL_BIDI_RESOLVER` produces. `resolve` and `reorder` each carry a rescue
  that falls back once and only once.
- **`BIDI_CONFORMANCE_HARNESS.run_character_case` has its real body.** It checks
  a case in two halves: `resolve`'s paragraph level and per-character levels
  (skipping the positions BidiCharacterTest marks `x`, removed by rule X9), then
  `reorder` against the visual order - fed the ORACLE's own levels for the kept
  positions, so an L2 defect can never hide behind a backend divergence.
- **Unicode conformance data pinned:** `tools/bidi-conformance.md` (Unicode
  **16.0.0**, URLs + sha256 for `BidiCharacterTest.txt` and `BidiTest.txt`),
  `tools/fetch_bidi_tests.py` to fetch and verify them into the git-ignored
  `testing/fixtures/`, and the committed 396-case sample at
  `testing/test_data/BidiCharacterTest.sample.txt`, drawn by five ADDITIVE
  blocks (UAX #9 worked examples, a stride through each paragraph-direction
  stratum, all 28 auto cases, a stride through the cases with digits). Nothing
  is filtered out for being hard.
- **Tests:** `test_directwrite_utf16_code_point_mapping` (the mandatory
  surrogate-pair boundary test), `test_directwrite_l2_reorder_mixed_levels`
  (hand-computed L2 permutations, no native calls), and
  `test_bidi_conformance_samples` - AC-5, no longer skeletal. `TEST_APP` gained
  a generic `run_backend_test` so a backend-dependent test reports an honest
  SKIP with its own reason instead of a pass. Suite: **25 passed, 8 skipped
  (skeletal), 0 failed**, plus 1 backend SKIP.

### Known divergence - DirectWrite's `AnalyzeBidi` vs UAX #9 (recorded, not worked around)

Of the 396 sampled Unicode cases, **358 agree and 38 do not**; none is
unclassified, and our L2 agrees on all 396. The 38 fall in two named classes,
listed case by case in `tools/bidi-conformance.md` and printed in full by the
test run:

- **30 paired-bracket cases (rule N0 / BD16).** DirectWrite sets a bracket pair
  to the strong direction enclosed by it without N0's preceding-context check.
- **8 explicit directional formatting cases** (U+202A-U+202E, U+2066-U+2069),
  mostly the "overrides tightly flanking isolates" set from the Unicode 8.0
  clarifications, plus a case where the backward search of rule W2 stops at the
  characters rule X9 removed.

Neither class touches the D-015 acceptance line or ordinary chat text.
`test_bidi_conformance_samples` therefore reports a **SKIP with that reason**
rather than a pass, and still asserts hard that the sample ran, that no mismatch
is unclassified, that L2 agrees on every case, and that the agreeing count stays
above a regression floor. This is the evidence that makes the D-S06 promotion
gate for a future `EIFFEL_BIDI_RESOLVER` worth opening.

Phase 2 repair pass: the adversarial contract review's 22 findings applied as
contract-level edits (5 HIGH / 6 MEDIUM / 8 LOW / 3 INFO). Seam signatures
freeze here, going into Phase 3. Test suite: 22 passed, 9 skipped (skeletal
Phase-5 markers), 0 failed.

### Changed - BREAKING (signatures freeze after this)
- **Seam 4 carries the per-call policy (R11).**
  `FONT_FALLBACK.font_for (a_text, a_item, a_requested, a_policy: FONT_LIST)`,
  with `require policy_usable: not a_policy.is_empty` and
  `ensure probes_counted`. `LIST_FONT_FALLBACK` walks `a_policy` and no longer
  holds a creation-time list at all - `make (a_probe, a_registry)`.
  `SIMPLE_SHAPING.layout` passes its own `a_fonts`. Previously the walk used
  the list captured when the facade was created, so a layout advertised "under
  policy a_fonts" was fiction beyond the primary face and `set_default_fonts`
  never rewired fallback. **Gate: Larry's Phase 3 approval (pending).**
- **`EMOJI_SEGMENTER.segment` takes a notes accumulator:**
  `segment (a_text, a_bidi, a_notes: ARRAYED_LIST [SHAPING_NOTE])`. Notes only
  grow, and every appended note is `Note_emoji_degraded` - FR-007 rung 3's
  observability was structurally unimplementable without a channel out.
- **`FALLBACK_CHOICE` carries `probes_performed: INTEGER`** (invariant >= 0;
  `make (a_font, a_complete, a_probes)`). The facade adds it into
  `statistics.fallback_probes` through the new
  `SHAPING_STATISTICS.record_fallback_probes`; seam doubles return 0. R7's
  "counted by the calling engine" was otherwise uncountable.
- **`FONT_LIST.digest` and `SIMPLE_SHAPING.cache_key` are injective.** Every
  serialized component is length-prefixed (`count ':' bytes`). Family names may
  contain `;`, `|` and `:`, so bare separators equated `["A;B"]` with
  `["A","B"]` - breaking value equality and letting two policies share one
  cache key.
- **`FONT_LIST.copy` is redefined DEEP** (fresh lists, fresh hash table of
  fresh inner lists; immutable elements shared). Self-copy is guarded as a
  no-op, as EiffelBase's ARRAYED_LIST.copy does. `is_equal` was redefined
  without it, so a `twin` aliased the internals and twin-then-mutate silently
  corrupted the original policy - the simple_chat D5 lesson.
- **`LAYOUT_CACHE` binds R8**: `put` / `item_verified` / `has_verified` carry
  the fonts digest, entries store it (`digests_model`, domain pinned to
  `cache_model`'s by invariant), and a policy mismatch demotes the hit.
- **Noto asset keys pad to four hex digits** (`emoji_u00a9`,
  `emoji_u0023_20e3`). `lower_hex` stripped leading zeros, so copyright,
  registered and every keycap would have probed a nonexistent path and
  degraded to permanent silent tofu the day assets shipped.
- **The test runner counts skips separately.** Each `[skeletal]` Phase-5 marker
  prints an explicit `SKIP` line, and the totals read
  `N passed, M skipped, F failed`. A skipped test can never count as passed.

### Removed
- `SCRIPT_ITEMIZER.itemize`'s `plain_span_only` precondition (and
  `is_emoji_free` with the class's private `EMOJI_DATA_TABLES` once). FR-007
  rung 3 lawfully sends unresolvable pictographs into the glyph path, so the
  precondition made the documented degradation an assertion violation -
  NFR-011's never-raises law broken by a contract. Emoji-freedom is now a
  caller duty stated in the class note; `segment` carries the honest mirror
  ensure for the single-codepoint case.
- `SIMPLE_SHAPING.measured_width`'s vacuous `whitespace_measures` clause; R2's
  measurement half is now bound to the named Phase-5 test
  `test_whitespace_measures_positive_under_realized_font`.

### Added
- `SHAPING_CONSTANTS.runs_at_layout_size` - closes D-S03 same-N as a
  `SHAPED_LAYOUT` invariant and `make` precondition, so a Phase-4 body cannot
  shape at one size and stamp the layout with another.
- `SHAPING_CONSTANTS.is_all_odd` / `is_reversal`, and two free bidi-oracle
  strengthenings: `reorder`'s `rtl_reversal` and `resolve`'s `empty_auto_ltr`.
- Success-and-failure postconditions on `DWRITE_API.analyze` / `shape_run` /
  `open` (`runs_on_success`, `glyphs_on_success`, `failure_reported`), so a
  lying shim is a contract violation at the trust boundary, not a surprise.
- `EMOJI_SEGMENTER.segment` ensures `emoji_levels_inherited` (RTL image
  placement depends on it) and `no_resolvable_single_left_plain`.
- Defensive deep copy in `SIMPLE_SHAPING.set_default_fonts`; `capacity_kept`
  frame on `set_asset_directory`.
- Tests: `test_font_list_twin_is_independent`,
  `test_font_list_digest_is_injective`, Noto padding expectations in
  `test_asset_catalog_key_scheme`, an R8 policy-mismatch demotion assertion.

## [0.1.0] - 2026-09-01 (pre-release: Phase 1 contracts)

Contract skeletons only. Nothing here shapes text yet: `layout` returns a
degenerate one-line, zero-run layout that satisfies every stated contract
(total function, coverage, caching) while the pipeline bodies await Phase 4.
Pure value classes and pure-logic engines already carry real bodies.

### Added
- The four seams as deferred classes with normative contracts (the
  cross-backend equivalence oracle): `BIDI_RESOLVER`, `SCRIPT_ITEMIZER`,
  `GLYPH_SHAPER`, `FONT_FALLBACK`.
- DirectWrite-first MVP effecting slots (G1 final, backed by the
  spikes/dwrite feasibility spike): `DIRECTWRITE_BIDI_RESOLVER`,
  `DIRECTWRITE_SCRIPT_ITEMIZER`, `DIRECTWRITE_GLYPH_SHAPER` - contract-level
  skeletons whose notes bind the proven plain-C COM-shim pattern
  (AnalyzeScript / AnalyzeBidi / GetGlyphs / GetGlyphPlacements).
  Uniscribe classes are named-only alternate slots; they do not exist yet.
- `LIST_FONT_FALLBACK` (G2): the library's own fallback in every configuration.
- Result model: `SHAPED_LAYOUT` -> `SHAPED_LINE` -> `SHAPED_RUN` closed over
  exactly `GLYPH_RUN` | `IMAGE_RUN`; `SHAPING_NOTE` degradation records.
- Emoji subsystem: `EMOJI_SEGMENTER` (runs after bidi, BEFORE itemization -
  spike-confirmed necessity), `EMOJI_ASSET_CATALOG` (Noto `emoji_u1f916`
  naming; disk-free resolution via an injectable existence probe),
  `EMOJI_DATA_TABLES` (generator-owned; UNPINNED until Phase 3 acquisition).
- `SHAPING_FONT` (same-N holder) + `FONT_REGISTRY` (per-processor ownership).
- `LAYOUT_CACHE`: real LRU with full-key verification on hit (R8).
- `FONT_LIST` (real builder + value-based digest), `SHAPING_STATISTICS`
  (R7 counter definitions), `FALLBACK_CHOICE`, pipeline value classes.
- NULL_* doubles for all four seams with real pure-logic bodies (headless).
- `SIMPLE_SHAPING` facade wired DirectWrite-first; degenerate total-function
  `layout` with the full contract already enforced.
- MML model queries on every collection-bearing class (simple_mml).
- Testing: TEST_APP + LIB_TESTS (real tests where logic is real, skeletal
  Phase-5 assault stubs), SCOOP consumer test, BIDI_CONFORMANCE_HARNESS skeleton.

### Deferred (deliberate, recorded)
- `SHAPING_CAIRO_BRIDGE` + `EMOJI_SURFACE_CACHE`: await the gated simple_cairo
  D-S07 glyph API (no cairo dependency in Phase 1).
- `USP10_API` + `UNISCRIBE_*`: the named alternate backend slot (G1 final).
- Native bodies (dwrite/gdi32 externals), real shaping, wrap, probing: Phase 4.
- Noto png/128 assets + pinned Unicode tables: Phase 3 acquisition (R4).
