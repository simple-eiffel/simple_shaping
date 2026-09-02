# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
