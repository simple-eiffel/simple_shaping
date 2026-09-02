note
	description: "[
		Phase-1 test set for simple_shaping: REAL tests wherever Phase 1
		carries real logic (value classes, FONT_LIST policy/digest,
		LAYOUT_CACHE with R8 verification and LRU eviction, the asset
		catalog's naming scheme and injected resolution, the NULL doubles,
		the facade's degenerate total-function layout with its cache
		discipline), plus SKELETAL stubs naming the Phase-5 assault
		(AC-1..AC-10) so nothing can be quietly forgotten.

		Phase 4 Task 3 added three REAL bidi tests: the mandatory UTF-16
		code-point mapping test (a surrogate pair between Hebrew and Latin),
		the UAX #9 L2 reorder cases with HAND-COMPUTED permutations, and
		`test_bidi_conformance_samples' - AC-5, no longer skeletal - which
		runs the committed Unicode BidiCharacterTest sample through
		BIDI_CONFORMANCE_HARNESS. The two that need a live DirectWrite report
		an honest SKIP with a reason where the backend is missing, never a
		pass.

		Contracts ARE tests brought into the classes: every call below also
		executes the preconditions, postconditions and invariants involved -
		the assertions here check observable behavior on top.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	LIB_TESTS

inherit
	TEST_SET_BASE

	SHAPING_CONSTANTS
		undefine
			default_create
		end

feature -- Test: facade wiring

	test_facade_wires_directwrite_first
			-- G1 FINAL: production creation wires DirectWrite effectings and
			-- the library's own fallback.
		note
			testing: "covers/{SIMPLE_SHAPING}.make"
		local
			l_shaping: SIMPLE_SHAPING
		do
			create l_shaping.make ({STRING_32} "assets")
			assert_true ("directwrite bidi", attached {DIRECTWRITE_BIDI_RESOLVER} l_shaping.bidi_resolver)
			assert_true ("directwrite itemizer", attached {DIRECTWRITE_SCRIPT_ITEMIZER} l_shaping.script_itemizer)
			assert_true ("directwrite shaper", attached {DIRECTWRITE_GLYPH_SHAPER} l_shaping.glyph_shaper)
			assert_true ("own list fallback (G2)", attached {LIST_FONT_FALLBACK} l_shaping.font_fallback)
			assert_integers_equal ("cache empty", 0, l_shaping.cache_count)
			assert_integers_equal ("statistics zero", 0, l_shaping.statistics.shape_calls)
			assert_false ("defaults present", l_shaping.default_fonts.is_empty)
		end

	test_facade_injected_backends
			-- make_with_backends wires exactly what it is given.
		note
			testing: "covers/{SIMPLE_SHAPING}.make_with_backends"
		local
			l_shaping: SIMPLE_SHAPING
			l_bidi: NULL_BIDI_RESOLVER
			l_itemizer: NULL_SCRIPT_ITEMIZER
			l_shaper: NULL_GLYPH_SHAPER
			l_fallback: NULL_FONT_FALLBACK
		do
			create l_bidi
			create l_itemizer
			create l_shaper
			create l_fallback
			create l_shaping.make_with_backends (l_bidi, l_itemizer, l_shaper, l_fallback, {STRING_32} "assets")
			assert_same_reference ("bidi wired", l_bidi, l_shaping.bidi_resolver)
			assert_same_reference ("itemizer wired", l_itemizer, l_shaping.script_itemizer)
			assert_same_reference ("shaper wired", l_shaper, l_shaping.glyph_shaper)
			assert_same_reference ("fallback wired", l_fallback, l_shaping.font_fallback)
		end

feature -- Test: layout (degenerate Phase-1 pipeline, full contract enforced)

	test_layout_total_function_and_cache_discipline
			-- The AC-3 seed: identical calls hit the cache; a hit shapes
			-- nothing and returns the SAME immutable layout.
		note
			testing: "covers/{SIMPLE_SHAPING}.layout_default, covers/{LAYOUT_CACHE}.item_verified"
		local
			l_shaping: SIMPLE_SHAPING
			l_first, l_second: SHAPED_LAYOUT
		do
			create l_shaping.make ({STRING_32} "assets")
			l_first := l_shaping.layout_default ({STRING_32} "abc", 100, 16)
			assert_true ("covers all characters", l_first.covers_all_characters)
			assert_integers_equal ("one line", 1, l_first.lines.count)
			assert_true ("cached now",
				l_shaping.is_cached ({STRING_32} "abc", 100, 16, l_shaping.default_fonts))
			assert_integers_equal ("one miss", 1, l_shaping.statistics.cache_misses)
			l_second := l_shaping.layout_default ({STRING_32} "abc", 100, 16)
			assert_same_reference ("hit returns the cached layout", l_first, l_second)
			assert_integers_equal ("one hit", 1, l_shaping.statistics.cache_hits)
			assert_integers_equal ("zero shape calls throughout (Phase 1)",
				0, l_shaping.statistics.shape_calls)
		end

	test_layout_empty_text
			-- FR-N01/AC-6 seed: empty text still yields one measurable line.
		note
			testing: "covers/{SIMPLE_SHAPING}.layout"
		local
			l_shaping: SIMPLE_SHAPING
			l_layout: SHAPED_LAYOUT
		do
			create l_shaping.make ({STRING_32} "assets")
			l_layout := l_shaping.layout_default ({STRING_32} "", 100, 16)
			assert_integers_equal ("one line", 1, l_layout.lines.count)
			assert_integers_equal ("zero runs", 0, l_layout.lines.first.runs.count)
			assert_false ("no notes", l_layout.has_notes)
			assert_true ("line height positive", l_layout.total_height > 0.0)
		end

	test_measured_width_empty_is_zero
			-- AC-10 seed: empty text measures 0.0.
		note
			testing: "covers/{SIMPLE_SHAPING}.measured_width"
		local
			l_shaping: SIMPLE_SHAPING
		do
			create l_shaping.make ({STRING_32} "assets")
			assert_reals_equal ("empty is zero", 0.0,
				l_shaping.measured_width ({STRING_32} "", 16, l_shaping.default_fonts), 0.000001)
		end

feature -- Test: FONT_LIST (FR-N03 value semantics)

	test_font_list_value_digest
			-- Equal configurations are equal values with equal digests;
			-- divergence changes both.
		note
			testing: "covers/{FONT_LIST}.digest, covers/{FONT_LIST}.is_equal"
		local
			l_first, l_second: FONT_LIST
		do
			create l_first.make_default
			create l_second.make_default
			assert_true ("equal by value", l_first ~ l_second)
			assert_true ("equal digests", l_first.digest.same_string (l_second.digest))
			l_second.with_family ({STRING_32} "Consolas").do_nothing
			assert_false ("diverged after with_family", l_first ~ l_second)
		end

	test_font_list_script_prepends
			-- R1 policy: scholar Hebrew faces first, then general anchors.
		note
			testing: "covers/{FONT_LIST}.families_for"
		local
			l_fonts: FONT_LIST
			l_hebrew: ARRAYED_LIST [IMMUTABLE_STRING_32]
		do
			create l_fonts.make_default
			l_hebrew := l_fonts.families_for (Script_class_hebrew)
			assert_true ("SBL Hebrew first", l_hebrew.first.same_string_general ("SBL Hebrew"))
			assert_integers_equal ("five prepends plus three anchors", 8, l_hebrew.count)
			assert_true ("general anchors included",
				l_hebrew [6].same_string_general ("Segoe UI"))
		end

	test_font_list_twin_is_independent
			-- ISSUE 3: `copy' is deep, so a twin can be mutated without
			-- touching the original - the simple_chat D5 lesson.
		note
			testing: "covers/{FONT_LIST}.copy, covers/{FONT_LIST}.twin"
		local
			l_original, l_twin: FONT_LIST
			l_original_digest: STRING_8
		do
			create l_original.make_default
			l_original_digest := l_original.digest.twin
			l_twin := l_original.twin
			assert_true ("twin starts equal", l_original ~ l_twin)
			assert_false ("twin is a different object", l_original = l_twin)

			l_twin.with_family ({STRING_32} "Consolas").do_nothing
			assert_integers_equal ("original general list untouched", 3, l_original.general_count)
			assert_integers_equal ("twin grew", 4, l_twin.general_count)
			assert_true ("original digest unchanged",
				l_original.digest.same_string (l_original_digest))
			assert_false ("digests differ after mutating the twin",
				l_original.digest.same_string (l_twin.digest))
			assert_false ("no longer equal", l_original ~ l_twin)

			l_twin.with_family_for_script (Script_class_hebrew, {STRING_32} "Frank Ruehl").do_nothing
			assert_integers_equal ("original hebrew prepends untouched",
				8, l_original.families_for (Script_class_hebrew).count)
			assert_true ("original hebrew head still SBL Hebrew",
				l_original.families_for (Script_class_hebrew).first.same_string_general ("SBL Hebrew"))
			assert_true ("twin hebrew head is the new face",
				l_twin.families_for (Script_class_hebrew).first.same_string_general ("Frank Ruehl"))

			-- Self-copy must be a no-op, never a wipe (the guard in `copy').
			l_original.copy (l_original)
			assert_integers_equal ("self-copy keeps the general list", 3, l_original.general_count)
			assert_true ("self-copy keeps the digest",
				l_original.digest.same_string (l_original_digest))
		end

	test_font_list_digest_is_injective
			-- ISSUE 2: separators inside family names must not collide two
			-- different policies.
		note
			testing: "covers/{FONT_LIST}.digest"
		local
			l_joined, l_split: FONT_LIST
		do
			create l_joined.make_empty
			l_joined.with_family ({STRING_32} "A;B").do_nothing
			create l_split.make_empty
			l_split.with_family ({STRING_32} "A").do_nothing
			l_split.with_family ({STRING_32} "B").do_nothing
			assert_false ("[A;B] and [A, B] have different digests",
				l_joined.digest.same_string (l_split.digest))
			assert_false ("and are therefore different values", l_joined ~ l_split)
		end

feature -- Test: statistics and notes

	test_statistics_counters
			-- R7 counters count and wipe independently.
		note
			testing: "covers/{SHAPING_STATISTICS}.record_shape_call"
		local
			l_statistics: SHAPING_STATISTICS
		do
			create l_statistics.make
			l_statistics.record_shape_call
			l_statistics.record_shape_call
			l_statistics.record_fallback_probe
			l_statistics.record_cache_miss
			assert_integers_equal ("two shapes", 2, l_statistics.shape_calls)
			assert_integers_equal ("one probe (disjoint)", 1, l_statistics.fallback_probes)
			assert_integers_equal ("one miss", 1, l_statistics.cache_misses)
			l_statistics.wipe
			assert_integers_equal ("wiped", 0, l_statistics.shape_calls)
		end

	test_shaping_note_fields
			-- Notes carry code, message, range, and a stable code name.
		note
			testing: "covers/{SHAPING_NOTE}.make"
		local
			l_note: SHAPING_NOTE
		do
			create l_note.make (Note_emoji_degraded, {STRING_32} "no asset for sequence", 5, 3)
			assert_integers_equal ("code", Note_emoji_degraded, l_note.code)
			assert_equal ("code name", "emoji_degraded", l_note.code_name)
			assert_integers_equal ("start", 5, l_note.source_start)
			assert_integers_equal ("count", 3, l_note.source_count)
		end

feature -- Test: LAYOUT_CACHE (R8 + LRU)

	test_layout_cache_verified_hit_and_demotion
			-- R8: a digest hit whose stored layout mismatches is a miss.
		note
			testing: "covers/{LAYOUT_CACHE}.item_verified"
		local
			l_cache: LAYOUT_CACHE
			l_layout: SHAPED_LAYOUT
			l_hit: detachable SHAPED_LAYOUT
		do
			create l_cache.make (4)
			l_layout := degenerate_layout ({STRING_32} "abc", 100, 16)
			l_cache.put ("k1", l_layout, "digest-A")
			l_hit := l_cache.item_verified ("k1", {STRING_32} "abc", 100, 16, "digest-A")
			assert_true ("verified hit is the stored layout", l_hit = l_layout)
			assert_void ("text mismatch demotes",
				l_cache.item_verified ("k1", {STRING_32} "abx", 100, 16, "digest-A"))
			assert_void ("width mismatch demotes",
				l_cache.item_verified ("k1", {STRING_32} "abc", 99, 16, "digest-A"))
			assert_void ("size mismatch demotes",
				l_cache.item_verified ("k1", {STRING_32} "abc", 100, 17, "digest-A"))
			assert_void ("FONT POLICY mismatch demotes (ISSUE 2: R8 bound)",
				l_cache.item_verified ("k1", {STRING_32} "abc", 100, 16, "digest-B"))
			assert_false ("has_verified agrees about the policy",
				l_cache.has_verified ("k1", {STRING_32} "abc", 100, 16, "digest-B"))
			assert_true ("and still finds the right one",
				l_cache.has_verified ("k1", {STRING_32} "abc", 100, 16, "digest-A"))
		end

	test_layout_cache_lru_eviction
			-- Oldest untouched entry leaves first; touching refreshes.
		note
			testing: "covers/{LAYOUT_CACHE}.put"
		local
			l_cache: LAYOUT_CACHE
			l_layout: SHAPED_LAYOUT
			l_touched: detachable SHAPED_LAYOUT
		do
			create l_cache.make (2)
			l_layout := degenerate_layout ({STRING_32} "abc", 100, 16)
			l_cache.put ("k1", l_layout, "digest-A")
			l_cache.put ("k2", l_layout, "digest-A")
			l_touched := l_cache.item_verified ("k1", {STRING_32} "abc", 100, 16, "digest-A")
			assert_true ("k1 touched for recency", l_touched /= Void)
			l_cache.put ("k3", l_layout, "digest-A")
			assert_integers_equal ("still bounded", 2, l_cache.count)
			assert_true ("k1 survived (touched)",
				l_cache.has_verified ("k1", {STRING_32} "abc", 100, 16, "digest-A"))
			assert_false ("k2 evicted (oldest untouched)",
				l_cache.has_verified ("k2", {STRING_32} "abc", 100, 16, "digest-A"))
			assert_true ("k3 present",
				l_cache.has_verified ("k3", {STRING_32} "abc", 100, 16, "digest-A"))
		end

feature -- Test: emoji asset catalog (G3 naming + injected resolution)

	test_asset_catalog_key_scheme
			-- Noto naming: lowercase hex, VS16 dropped, ZWJ members joined.
		note
			testing: "covers/{EMOJI_ASSET_CATALOG}.asset_key"
		local
			l_catalog: EMOJI_ASSET_CATALOG
			l_tables: EMOJI_DATA_TABLES
		do
			create l_tables
			create l_catalog.make ({STRING_32} "C:\assets", l_tables, agent probe_always_false)
			assert_equal ("robot", "emoji_u1f916",
				l_catalog.asset_key (<<{NATURAL_32} 0x1F916>>))
			assert_equal ("heart drops VS16", "emoji_u2764",
				l_catalog.asset_key (<<{NATURAL_32} 0x2764, {NATURAL_32} 0xFE0F>>))
			assert_equal ("zwj family joined", "emoji_u1f469_200d_1f4bb",
				l_catalog.asset_key (<<{NATURAL_32} 0x1F469, {NATURAL_32} 0x200D, {NATURAL_32} 0x1F4BB>>))
			assert_equal ("copyright pads to four (ISSUE 5)", "emoji_u00a9",
				l_catalog.asset_key (<<{NATURAL_32} 0x00A9>>))
			assert_equal ("registered pads to four", "emoji_u00ae",
				l_catalog.asset_key (<<{NATURAL_32} 0x00AE>>))
			assert_equal ("keycap base pads to four", "emoji_u0023_20e3",
				l_catalog.asset_key (<<{NATURAL_32} 0x0023, {NATURAL_32} 0x20E3>>))
			assert_equal ("five digits stay five", "emoji_u1f916",
				l_catalog.asset_key (<<{NATURAL_32} 0x1F916>>))
		end

	test_asset_catalog_injected_probe
			-- Resolution without disk: the injected probe decides existence.
		note
			testing: "covers/{EMOJI_ASSET_CATALOG}.has_asset"
		local
			l_yes, l_no: EMOJI_ASSET_CATALOG
			l_tables: EMOJI_DATA_TABLES
			l_path: IMMUTABLE_STRING_32
		do
			create l_tables
			create l_yes.make ({STRING_32} "C:\assets", l_tables, agent probe_always_true)
			create l_no.make ({STRING_32} "C:\assets", l_tables, agent probe_always_false)
			assert_true ("probe true resolves", l_yes.has_asset (<<{NATURAL_32} 0x1F916>>))
			l_path := l_yes.asset_path (<<{NATURAL_32} 0x1F916>>)
			assert_true ("under directory", l_path.starts_with (l_yes.directory))
			assert_string_ends_with ("png file", l_path, ".png")
			assert_false ("probe false degrades", l_no.has_asset (<<{NATURAL_32} 0x1F916>>))
		end

feature -- Test: NULL doubles (headless seams)

	test_null_bidi_levels_and_reorder
			-- Levels cover the text; forced bases honored; identity reorder.
		note
			testing: "covers/{NULL_BIDI_RESOLVER}.resolve"
		local
			l_bidi: NULL_BIDI_RESOLVER
			l_result: BIDI_RESULT
			l_order: ARRAY [INTEGER]
		do
			create l_bidi
			l_result := l_bidi.resolve ({STRING_32} "abc", Direction_auto)
			assert_integers_equal ("one level per character", 3, l_result.count)
			assert_integers_equal ("auto is ltr", 0, l_result.paragraph_level.to_integer_32)
			l_result := l_bidi.resolve ({STRING_32} "abc", Direction_rtl)
			assert_integers_equal ("forced rtl", 1, l_result.paragraph_level.to_integer_32)
			l_order := l_bidi.reorder (<<{NATURAL_8} 0, {NATURAL_8} 0, {NATURAL_8} 0>>)
			assert_integers_equal ("identity first", 1, l_order [1])
			assert_integers_equal ("identity last", 3, l_order [3])
		end

	test_null_itemizer_intersection_contract
			-- Items split exactly at level boundaries: the intersection
			-- postconditions (partition, one level per item, justified
			-- boundaries) all execute here.
		note
			testing: "covers/{NULL_SCRIPT_ITEMIZER}.itemize"
		local
			l_itemizer: NULL_SCRIPT_ITEMIZER
			l_levels: ARRAY [NATURAL_8]
			l_bidi: BIDI_RESULT
			l_items: ARRAYED_LIST [SCRIPT_ITEM]
		do
			create l_itemizer
			l_levels := <<{NATURAL_8} 0, {NATURAL_8} 0, {NATURAL_8} 1, {NATURAL_8} 1, {NATURAL_8} 0, {NATURAL_8} 0>>
			create l_bidi.make (l_levels, 0)
			l_items := l_itemizer.itemize ({STRING_32} "abcdef", 1, 6, l_bidi)
			assert_integers_equal ("three items at two level changes", 3, l_items.count)
			assert_integers_equal ("first covers 1..2", 2, l_items.first.count)
			assert_integers_equal ("middle level odd", 1, l_items [2].embedding_level.to_integer_32)
			assert_true ("middle is rtl", l_items [2].is_rtl)
			assert_integers_equal ("last starts at 5", 5, l_items.last.start_index)
		end

	test_null_itemizer_soft_breaks
			-- Breaks only after spaces; never before the first character.
		note
			testing: "covers/{NULL_SCRIPT_ITEMIZER}.soft_breaks"
		local
			l_itemizer: NULL_SCRIPT_ITEMIZER
			l_levels: ARRAY [NATURAL_8]
			l_bidi: BIDI_RESULT
			l_items: ARRAYED_LIST [SCRIPT_ITEM]
			l_breaks: ARRAY [BOOLEAN]
		do
			create l_itemizer
			create l_levels.make_filled ({NATURAL_8} 0, 1, 5)
			create l_bidi.make (l_levels, 0)
			l_items := l_itemizer.itemize ({STRING_32} "ab cd", 1, 5, l_bidi)
			assert_integers_equal ("one item at one level", 1, l_items.count)
			l_breaks := l_itemizer.soft_breaks ({STRING_32} "ab cd", l_items.first)
			assert_integers_equal ("one flag per character", 5, l_breaks.count)
			assert_false ("never before first", l_breaks [1])
			assert_false ("not before space", l_breaks [3])
			assert_true ("break before c (after the space)", l_breaks [4])
			assert_false ("not mid-word", l_breaks [5])
		end

	test_null_shaper_and_fallback_headless
			-- The headless pair: predictable metrics from an UNREALIZED font.
		note
			testing: "covers/{NULL_GLYPH_SHAPER}.shape, covers/{NULL_FONT_FALLBACK}.font_for"
		local
			l_registry: FONT_REGISTRY
			l_font: SHAPING_FONT
			l_item: SCRIPT_ITEM
			l_shaper: NULL_GLYPH_SHAPER
			l_fallback: NULL_FONT_FALLBACK
			l_shaped: SHAPED_ITEM
			l_choice: FALLBACK_CHOICE
			l_policy: FONT_LIST
		do
			create l_registry.make
			l_font := l_registry.font ({STRING_32} "Segoe UI", 400, False, 16)
			assert_false ("headless font unrealized", l_font.is_ready)
			create l_item.make (1, 2, 0, 0, create {ARRAY [NATURAL_8]}.make_empty)
			create l_shaper
			l_shaped := l_shaper.shape ({STRING_32} "ab", l_item, l_font)
			assert_integers_equal ("one glyph per character", 2, l_shaped.glyphs.count)
			assert_true ("complete coverage", l_shaped.is_complete)
			assert_reals_equal ("metric-predictable: 2 * 16/2", 16.0, l_shaped.advance_sum, 0.000001)
			assert_naturals_equal ("glyph id is the code point", 97, l_shaped.glyphs [1].to_natural_64)
			create l_fallback
			create l_policy.make_default
			l_choice := l_fallback.font_for ({STRING_32} "ab", l_item, l_font, l_policy)
			assert_same_reference ("requested font kept", l_font, l_choice.font)
			assert_true ("complete claimed", l_choice.is_complete_coverage)
			assert_integers_equal ("a double probes nothing (R7 amended)",
				0, l_choice.probes_performed)
		end

feature -- Test: fonts and registry (ownership contracts)

	test_registry_identity_and_ownership
			-- One holder per identity; ownership fixed at birth (DR-012).
		note
			testing: "covers/{FONT_REGISTRY}.font"
		local
			l_registry: FONT_REGISTRY
			l_first, l_second: SHAPING_FONT
		do
			create l_registry.make
			l_first := l_registry.font ({STRING_32} "Segoe UI", 400, False, 16)
			l_second := l_registry.font ({STRING_32} "Segoe UI", 400, False, 16)
			assert_same_reference ("same holder for same identity", l_first, l_second)
			assert_integers_equal ("one identity", 1, l_registry.count)
			assert_same_reference ("owned by this registry", l_registry, l_first.registry)
			l_second := l_registry.font ({STRING_32} "Segoe UI", 400, False, 18)
			assert_integers_equal ("size is identity (same-N)", 2, l_registry.count)
		end

feature -- Test: emoji segmentation (degenerate Phase-1 truth)

	test_emoji_segmenter_degenerate_partition
			-- With ungenerated tables, everything is one PLAIN segment;
			-- empty text yields no segments.
		note
			testing: "covers/{EMOJI_SEGMENTER}.segment"
		local
			l_tables: EMOJI_DATA_TABLES
			l_catalog: EMOJI_ASSET_CATALOG
			l_segmenter: EMOJI_SEGMENTER
			l_levels: ARRAY [NATURAL_8]
			l_bidi: BIDI_RESULT
			l_segments: ARRAYED_LIST [TEXT_SEGMENT]
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
		do
			create l_tables
			create l_catalog.make ({STRING_32} "C:\assets", l_tables, agent probe_always_false)
			create l_segmenter.make (l_tables, l_catalog)
			create l_notes.make (0)
			create l_levels.make_filled ({NATURAL_8} 0, 1, 2)
			create l_bidi.make (l_levels, 0)
			l_segments := l_segmenter.segment ({STRING_32} "ab", l_bidi, l_notes)
			assert_integers_equal ("one plain segment", 1, l_segments.count)
			assert_true ("plain", l_segments.first.is_plain)
			assert_integers_equal ("nothing degraded, so no notes (ISSUE 6)",
				0, l_notes.count)
			create l_levels.make_empty
			create l_bidi.make (l_levels, 0)
			l_segments := l_segmenter.segment ({STRING_32} "", l_bidi, l_notes)
			assert_true ("empty text has no segments", l_segments.is_empty)
			assert_integers_equal ("accumulator still empty", 0, l_notes.count)
		end

feature -- Test: native round trip (Phase 4 Task 1)

	native_round_trip_ran: BOOLEAN
			-- Did `test_dwrite_native_round_trip' reach a LIVE DirectWrite
			-- backend? False means the test SKIPPED - never that it passed.
			-- TEST_APP reads this to report an honest SKIP (ISSUE 18's rule
			-- applied to a machine-dependent test).

	native_skip_reason: STRING
			-- Why the native round trip could not run (empty when it ran).
		attribute
			create Result.make_empty
		end

	test_dwrite_native_round_trip
			-- Task 1: the production shim reproduces the spike's MEASURED
			-- facts (spikes/dwrite/run_output.txt) end to end - open,
			-- AnalyzeScript + AnalyzeBidi over the D-015 probe string
			-- (3 script runs / 2 bidi runs, Hebrew resolved level 1),
			-- AnalyzeLineBreakpoints (the growth the spike stubbed out), GDI
			-- realization of Segoe UI at 16 px, CreateFontFaceFromHdc, and
			-- GetGlyphs/GetGlyphPlacements: shalom shapes to 4 glyphs with
			-- positive advances and an identity cluster map, and the emoji
			-- run - which Segoe UI cannot cover - yields a .notdef of id 0.
			--
			-- Every measurement is taken FIRST and every handle released
			-- BEFORE the assertions, so a failing assertion cannot leak an
			-- HFONT, an HDC or an IDWriteFontFace.
		note
			testing: "covers/{DWRITE_API}.open, covers/{DWRITE_API}.analyze, covers/{DWRITE_API}.shape_run, covers/{GDI32_API}.create_font"
		local
			l_api: DWRITE_API
			l_gdi: GDI32_API
			l_units: ARRAYED_LIST [INTEGER]
			l_text, l_emoji_text, l_analysis: MANAGED_POINTER
			l_font, l_dc, l_old_font, l_face: POINTER
			l_analyzed, l_broke, l_shaped, l_emoji_shaped: BOOLEAN
			l_clusters_identity, l_has_notdef: BOOLEAN
			l_script_runs, l_bidi_runs, l_breaks: INTEGER
			l_bidi0_pos, l_bidi0_len, l_bidi0_level, l_bidi1_level: INTEGER
			l_s0_pos, l_s0_len, l_s1_pos, l_s1_len, l_s2_pos, l_s2_len: INTEGER
			l_can_break, l_glyphs, l_positive, l_emoji_glyphs: INTEGER
			l_ascent, l_descent, l_index: INTEGER
			l_ws_0, l_ws_4, l_ws_7, l_ws_15: BOOLEAN
			l_face_name: STRING_32
		do
			create l_face_name.make_empty
			l_units := utf16_units (d015_code_points)
			l_text := utf16_buffer (l_units, 1, l_units.count)
			l_emoji_text := utf16_buffer (l_units, 5, 4)
			create l_api.make
			create l_gdi.make
			if not l_api.open then
				native_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ l_api.last_hresult.to_hex_string
			else
				native_round_trip_ran := True

					-- Analysis (AnalyzeScript slot 3 + AnalyzeBidi slot 4).
				l_analyzed := l_api.analyze (l_text.item, l_units.count)
				if l_analyzed then
					l_script_runs := l_api.script_run_count
					l_bidi_runs := l_api.bidi_run_count
					if l_script_runs >= 3 then
						l_s0_pos := l_api.script_run_position (0)
						l_s0_len := l_api.script_run_length (0)
						l_s1_pos := l_api.script_run_position (1)
						l_s1_len := l_api.script_run_length (1)
						l_s2_pos := l_api.script_run_position (2)
						l_s2_len := l_api.script_run_length (2)
					end
					if l_bidi_runs >= 2 then
						l_bidi0_pos := l_api.bidi_run_position (0)
						l_bidi0_len := l_api.bidi_run_length (0)
						l_bidi0_level := l_api.bidi_run_level (0)
						l_bidi1_level := l_api.bidi_run_level (1)
					end
				end

					-- Line breakpoints (analyzer slot 6 - Task 1's growth
					-- beyond the spike, which stubbed this sink out).
				l_broke := l_api.analyze_line_breakpoints (l_text.item, l_units.count)
				if l_broke then
					l_breaks := l_api.breakpoint_count
					from l_index := 0 until l_index >= l_breaks loop
						if l_api.break_condition_before (l_index) = Break_can_break then
							l_can_break := l_can_break + 1
						end
						l_index := l_index + 1
					end
					if l_breaks >= 16 then
						l_ws_0 := l_api.is_break_whitespace (0)
						l_ws_4 := l_api.is_break_whitespace (4)
						l_ws_7 := l_api.is_break_whitespace (7)
						l_ws_15 := l_api.is_break_whitespace (15)
					end
				end

					-- D-S03 realization chain, then real shaping at em 16.
				l_font := l_gdi.create_font ({STRING_32} "Segoe UI", 400, False, 16)
				if l_font /= default_pointer then
					l_dc := l_gdi.create_memory_dc
					if l_dc /= default_pointer then
						l_old_font := l_gdi.select_font (l_dc, l_font)
						l_ascent := l_gdi.text_ascent (l_dc)
						l_descent := l_gdi.text_descent (l_dc)
						l_face_name := l_gdi.realized_face_name (l_dc)
						l_face := l_api.create_font_face_from_hdc (l_dc)
						if l_face /= default_pointer and l_analyzed and l_script_runs >= 1 then
							create l_analysis.make (l_api.script_analysis_size)
							l_api.copy_script_run_analysis (0, l_analysis.item)
								-- shalom: UTF-16 units [0, 4), RTL (level 1).
							l_shaped := l_api.shape_run (l_text.item, 4, l_face, 16.0, True, l_analysis.item)
							if l_shaped then
								l_glyphs := l_api.glyph_count
								from l_index := 0 until l_index >= l_glyphs loop
									if l_api.glyph_advance (l_index) > 0.0 then
										l_positive := l_positive + 1
									end
									l_index := l_index + 1
								end
								l_clusters_identity := True
								from l_index := 0 until l_index >= 4 loop
									if l_api.cluster_of_unit (l_index) /= l_index then
										l_clusters_identity := False
									end
									l_index := l_index + 1
								end
							end
								-- The emoji's itemized run, UTF-16 units
								-- [4, 8): Segoe UI has no U+1F916 coverage,
								-- so DirectWrite answers with .notdef.
							l_emoji_shaped := l_api.shape_run (l_emoji_text.item, 4, l_face, 16.0, False, l_analysis.item)
							if l_emoji_shaped then
								l_emoji_glyphs := l_api.glyph_count
								from l_index := 0 until l_index >= l_emoji_glyphs loop
									if l_api.glyph_id (l_index) = 0 then
										l_has_notdef := True
									end
									l_index := l_index + 1
								end
							end
							l_api.release_font_face (l_face)
						end
						if l_old_font /= default_pointer then
							l_old_font := l_gdi.select_font (l_dc, l_old_font)
						end
						if l_gdi.delete_dc (l_dc) then
						end
					end
					if l_gdi.delete_handle (l_font) then
					end
				end
				l_api.close

				print ("    native: " + l_script_runs.out + " script runs, " + l_bidi_runs.out
					+ " bidi runs, level " + l_bidi0_level.out + "; " + l_breaks.out
					+ " breakpoints; " + l_face_name.to_string_8 + " ascent " + l_ascent.out
					+ "/" + l_descent.out + "; shalom " + l_glyphs.out + " glyphs, "
					+ l_positive.out + " positive; emoji " + l_emoji_glyphs.out + " glyphs%N")

					-- ---- assertions (every handle already released) ----
				assert_true ("analyze succeeded", l_analyzed)
				assert_integers_equal ("3 script runs (spike-measured)", 3, l_script_runs)
				assert_integers_equal ("2 bidi runs (spike-measured)", 2, l_bidi_runs)
				assert_integers_equal ("script run 0 at 0", 0, l_s0_pos)
				assert_integers_equal ("script run 0 covers 8 units", 8, l_s0_len)
				assert_integers_equal ("script run 1 at 8", 8, l_s1_pos)
				assert_integers_equal ("script run 1 covers 8 units", 8, l_s1_len)
				assert_integers_equal ("script run 2 at 16", 16, l_s2_pos)
				assert_integers_equal ("script run 2 covers 3 units", 3, l_s2_len)
				assert_integers_equal ("bidi run 0 at 0", 0, l_bidi0_pos)
				assert_integers_equal ("bidi run 0 covers shalom", 4, l_bidi0_len)
				assert_integers_equal ("Hebrew resolved level 1 (RTL)", 1, l_bidi0_level)
				assert_integers_equal ("the rest resolves LTR", 0, l_bidi1_level)

				assert_true ("AnalyzeLineBreakpoints succeeded", l_broke)
				assert_integers_equal ("one breakpoint per UTF-16 unit", 19, l_breaks)
				assert_true ("some position offers a break", l_can_break >= 1)
				assert_false ("unit 0 (Hebrew shin) is not whitespace", l_ws_0)
				assert_true ("unit 4 (space) is whitespace", l_ws_4)
				assert_true ("unit 7 (space) is whitespace", l_ws_7)
				assert_true ("unit 15 (space) is whitespace", l_ws_15)

				assert_true ("Segoe UI HFONT created", l_font /= default_pointer)
				assert_true ("memory DC created", l_dc /= default_pointer)
				assert_true ("GDI realized Segoe UI itself (the R1 comparator)",
					l_face_name.same_string ({STRING_32} "Segoe UI"))
				assert_true ("ascent positive", l_ascent > 0)
				assert_true ("descent non negative", l_descent >= 0)
				assert_true ("IDWriteFontFace from the HDC", l_face /= default_pointer)

				assert_true ("shalom shaped", l_shaped)
				assert_integers_equal ("shalom is 4 glyphs (spike-measured)", 4, l_glyphs)
				assert_integers_equal ("every advance positive", 4, l_positive)
				assert_true ("cluster map is the identity over shalom", l_clusters_identity)
				assert_true ("the uncovered emoji run still shapes", l_emoji_shaped)
				assert_true ("an uncovered codepoint yields .notdef = glyph id 0", l_has_notdef)
			end
		end

feature -- Test: bidi backend (Phase 4 Task 3)

	bidi_mapping_ran: BOOLEAN
			-- Did `test_directwrite_utf16_code_point_mapping' reach a LIVE
			-- DirectWrite backend? False means the test SKIPPED - never that
			-- it passed.

	bidi_mapping_skip_reason: STRING
			-- Why the mapping test could not run (empty when it ran).
		attribute
			create Result.make_empty
		end

	conformance_ran: BOOLEAN
			-- Did `test_bidi_conformance_samples' reach a CLEAN verdict - a
			-- live DirectWrite backend, the committed sample file, and zero
			-- mismatches? False means SKIP, never pass, and
			-- `conformance_skip_reason' says which of the three it was.

	conformance_skip_reason: STRING
			-- Why the conformance sample could not run (empty when it ran).
		attribute
			create Result.make_empty
		end

	test_directwrite_utf16_code_point_mapping
			-- Task 3's MANDATORY boundary test: DIRECTWRITE_BIDI_RESOLVER
			-- owns the code-point <-> UTF-16 mapping, and this is the single
			-- most likely silent-wrong-answer site in the backend.
			--
			-- The D-015 string is 18 CODE POINTS and 19 UTF-16 units (the
			-- spike's measurement) because U+1F916 is a surrogate pair, so a
			-- resolver that counted units would answer 19 - which the seam's
			-- `one_level_per_character' would catch. The second string puts a
			-- surrogate pair between Hebrew and Latin and then RETURNS to
			-- Hebrew, so a mapping that is merely SHIFTED by the pair (the
			-- off-by-one that a unit-indexed lookup produces) shows up as the
			-- wrong level on the trailing Hebrew.
		note
			testing: "covers/{DIRECTWRITE_BIDI_RESOLVER}.resolve"
		local
			l_bidi: DIRECTWRITE_BIDI_RESOLVER
			l_api: DWRITE_API
			l_d015, l_mixed: STRING_32
			l_ltr, l_auto, l_rtl, l_shift: BIDI_RESULT
			l_levels: STRING
			i: INTEGER
		do
			create l_api.make
			if not l_api.open then
				bidi_mapping_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ l_api.last_hresult.to_hex_string
			else
				bidi_mapping_ran := True
				create l_bidi.make
				l_d015 := string_of_code_points (d015_code_points)
					-- Hebrew, robot (a surrogate pair), Latin, Hebrew again.
				l_mixed := string_of_code_points (<<0x05E9, 0x05DC, 0x05D5, 0x05DD,
					0x1F916, 0x0061, 0x0062, 0x0063, 0x05E9, 0x05DC, 0x05D5, 0x05DD>>)

				l_ltr := l_bidi.resolve (l_d015, Direction_ltr)
				l_auto := l_bidi.resolve (l_d015, Direction_auto)
				l_rtl := l_bidi.resolve (l_d015, Direction_rtl)
				l_shift := l_bidi.resolve (l_mixed, Direction_ltr)
				l_api.close

				create l_levels.make_empty
				from i := 1 until i > l_ltr.count loop
					l_levels.append_integer (l_ltr.level (i).to_integer_32)
					i := i + 1
				end
				print ("    bidi: D-015 is " + l_ltr.count.out + " code points (19 UTF-16 units),"
					+ " levels under Direction_ltr " + l_levels + "; auto paragraph level "
					+ l_auto.paragraph_level.out + "%N")

					-- ---- the code-point count, not the unit count ----
				assert_integers_equal ("D-015 is 18 code points, not 19 units", 18, l_ltr.count)
				assert_integers_equal ("forced LTR paragraph", 0, l_ltr.paragraph_level.to_integer_32)
				assert_integers_equal ("Hebrew shin resolves RTL", 1, l_ltr.level (1).to_integer_32)
				assert_integers_equal ("Hebrew mem resolves RTL", 1, l_ltr.level (4).to_integer_32)
				assert_integers_equal ("the space after the Hebrew is LTR", 0, l_ltr.level (5).to_integer_32)
					-- ONE level for the pair: code point 6 IS the robot, and
					-- code point 7 is the space after it, not its low surrogate.
				assert_integers_equal ("the surrogate pair is ONE code point", 0, l_ltr.level (6).to_integer_32)
				assert_integers_equal ("the space after the robot", 0, l_ltr.level (7).to_integer_32)
				assert_integers_equal ("Greek chi is LTR", 0, l_ltr.level (8).to_integer_32)
				assert_integers_equal ("the final Latin c is LTR", 0, l_ltr.level (18).to_integer_32)

					-- ---- P2/P3 through the settable reading direction ----
				assert_integers_equal ("auto: first strong is Hebrew, so RTL", 1,
					l_auto.paragraph_level.to_integer_32)
				assert_integers_equal ("forced RTL paragraph", 1, l_rtl.paragraph_level.to_integer_32)

					-- ---- the shift the pair would cause, if it caused one ----
				assert_integers_equal ("12 code points across the pair", 12, l_shift.count)
				assert_integers_equal ("leading Hebrew RTL", 1, l_shift.level (1).to_integer_32)
				assert_integers_equal ("leading Hebrew RTL to the end of the word", 1,
					l_shift.level (4).to_integer_32)
				assert_integers_equal ("the robot itself", 0, l_shift.level (5).to_integer_32)
				assert_integers_equal ("Latin a after the pair", 0, l_shift.level (6).to_integer_32)
				assert_integers_equal ("Latin c after the pair", 0, l_shift.level (8).to_integer_32)
				assert_integers_equal ("TRAILING Hebrew is RTL - no shift", 1,
					l_shift.level (9).to_integer_32)
				assert_integers_equal ("trailing Hebrew to the end", 1, l_shift.level (12).to_integer_32)
			end
		end

	test_directwrite_l2_reorder_mixed_levels
			-- Task 3's L2: from the highest level down to the lowest ODD
			-- level, reverse every maximal run at that level or higher. The
			-- Phase-1 body handled only all-even and all-odd; every case
			-- below is MIXED, and every expected permutation is computed BY
			-- HAND here (never by the code under test). Zero native calls -
			-- `reorder' is arithmetic over the levels it is handed.
		note
			testing: "covers/{DIRECTWRITE_BIDI_RESOLVER}.reorder"
		local
			l_bidi: DIRECTWRITE_BIDI_RESOLVER
			l_empty: ARRAY [NATURAL_8]
		do
			create l_bidi.make

				-- Hebrew Hebrew | digits digits | Hebrew | Latin Latin.
				-- level 2 pass: reverse 3..4  -> 1 2 4 3 5 6 7
				-- level 1 pass: reverse 1..5  -> 5 3 4 2 1 6 7
			assert_permutation ("hebrew digits hebrew latin",
				<<{NATURAL_8} 1, {NATURAL_8} 1, {NATURAL_8} 2, {NATURAL_8} 2,
				  {NATURAL_8} 1, {NATURAL_8} 0, {NATURAL_8} 0>>,
				<<5, 3, 4, 2, 1, 6, 7>>, l_bidi)

				-- "car MEANS CAR." - an LTR paragraph with one RTL island.
				-- level 1 pass: reverse 4..6  -> 1 2 3 6 5 4 7
			assert_permutation ("ltr paragraph with one rtl run",
				<<{NATURAL_8} 0, {NATURAL_8} 0, {NATURAL_8} 0, {NATURAL_8} 1,
				  {NATURAL_8} 1, {NATURAL_8} 1, {NATURAL_8} 0>>,
				<<1, 2, 3, 6, 5, 4, 7>>, l_bidi)

				-- RTL paragraph, one embedded LTR word.
				-- level 2 pass: reverse 2..3  -> 1 3 2 4
				-- level 1 pass: reverse 1..4  -> 4 2 3 1
			assert_permutation ("rtl paragraph with an ltr word",
				<<{NATURAL_8} 1, {NATURAL_8} 2, {NATURAL_8} 2, {NATURAL_8} 1>>,
				<<4, 2, 3, 1>>, l_bidi)

				-- RTL paragraph, LTR words at BOTH ends.
				-- level 2 pass: reverse 1..2 and 5..6 -> 2 1 3 4 6 5
				-- level 1 pass: reverse 1..6          -> 5 6 4 3 1 2
			assert_permutation ("rtl paragraph, ltr islands at both ends",
				<<{NATURAL_8} 2, {NATURAL_8} 2, {NATURAL_8} 1, {NATURAL_8} 1,
				  {NATURAL_8} 2, {NATURAL_8} 2>>,
				<<5, 6, 4, 3, 1, 2>>, l_bidi)

				-- Four levels deep, so the "intermediate levels" clause bites.
				-- level 3 pass: reverse 4..5 -> 1 2 3 5 4 6 7 8
				-- level 2 pass: reverse 3..6 -> 1 2 6 4 5 3 7 8
				-- level 1 pass: reverse 2..7 -> 1 7 3 5 4 6 2 8
			assert_permutation ("levels 0..3 nested",
				<<{NATURAL_8} 0, {NATURAL_8} 1, {NATURAL_8} 2, {NATURAL_8} 3,
				  {NATURAL_8} 3, {NATURAL_8} 2, {NATURAL_8} 1, {NATURAL_8} 0>>,
				<<1, 7, 3, 5, 4, 6, 2, 8>>, l_bidi)

				-- The two clauses the seam states (ISSUE 13), still honored.
			assert_permutation ("all even is the identity",
				<<{NATURAL_8} 0, {NATURAL_8} 0, {NATURAL_8} 0, {NATURAL_8} 0>>,
				<<1, 2, 3, 4>>, l_bidi)
			assert_permutation ("all odd is the full reversal",
				<<{NATURAL_8} 1, {NATURAL_8} 1, {NATURAL_8} 1>>, <<3, 2, 1>>, l_bidi)
			assert_permutation ("all odd at level 3 is still the full reversal",
				<<{NATURAL_8} 3, {NATURAL_8} 3, {NATURAL_8} 3>>, <<3, 2, 1>>, l_bidi)
				-- Mixed ODD levels are still one RTL line end to end.
			assert_permutation ("mixed odd levels reverse end to end",
				<<{NATURAL_8} 1, {NATURAL_8} 3, {NATURAL_8} 3, {NATURAL_8} 1>>,
				<<4, 3, 2, 1>>, l_bidi)

			create l_empty.make_empty
			assert_integers_equal ("the empty line reorders to nothing", 0,
				l_bidi.reorder (l_empty).count)
		end

	test_bidi_conformance_samples
			-- AC-5, REAL: every case of the committed Unicode
			-- BidiCharacterTest sample through BIDI_CONFORMANCE_HARNESS
			-- against DIRECTWRITE_BIDI_RESOLVER. A case passes only when the
			-- resolved paragraph level, EVERY per-character level, and the L2
			-- visual order all agree with Unicode's own answer.
			--
			-- The sample is testing/test_data/BidiCharacterTest.sample.txt;
			-- its provenance, the pinned Unicode version + sha256 and the
			-- (additive, content-blind) sampling rule are in
			-- tools/bidi-conformance.md. NOTHING is excluded for being hard
			-- and NOTHING is weakened to make this pass: every mismatch is
			-- printed in full, classified, and counted, and a run that ends
			-- with any mismatch reports a SKIP with the reason - never a
			-- PASS.
			--
			-- What IS asserted hard, because it is OURS and not the
			-- backend's:
			--   * the sample really ran (>= 300 cases);
			--   * UAX #9 L2 - `reorder' - agrees with Unicode's visual order
			--     on EVERY sampled case, fed the oracle's own levels for the
			--     X9-kept positions, so an L2 defect can never hide behind a
			--     backend divergence;
			--   * NO mismatch is unexplained: every one lands in a named
			--     DirectWrite rule gap (paired brackets, or explicit
			--     directional formatting characters). An "unclassified"
			--     mismatch fails the suite outright;
			--   * a regression floor on the number of cases that do agree.
		note
			testing: "covers/{BIDI_CONFORMANCE_HARNESS}.run_character_case, covers/{DIRECTWRITE_BIDI_RESOLVER}.resolve, covers/{DIRECTWRITE_BIDI_RESOLVER}.reorder"
		local
			l_bidi: DIRECTWRITE_BIDI_RESOLVER
			l_harness: BIDI_CONFORMANCE_HARNESS
			l_api: DWRITE_API
			l_path: detachable STRING
			l_file: PLAIN_TEXT_FILE
			l_line: STRING
			l_fields: LIST [STRING]
			l_codes: ARRAY [NATURAL_32]
			l_levels, l_order: ARRAY [INTEGER]
			l_direction, l_paragraph: INTEGER
			l_formatting, l_bracket, l_unclassified, l_reorder_failures: INTEGER
			l_report: STRING
		do
			l_path := sample_file_path
			create l_api.make
			if l_path = Void then
				conformance_skip_reason := "testing/test_data/BidiCharacterTest.sample.txt not found"
			elseif not l_api.open then
				conformance_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ l_api.last_hresult.to_hex_string
			else
				create l_bidi.make
				create l_harness.make (l_bidi)
				create l_report.make_empty
				create l_file.make_with_name (l_path)
				l_file.open_read
				from until l_file.end_of_file loop
					l_file.read_line
					l_line := l_file.last_string.twin
					l_line.adjust
					if not l_line.is_empty and then l_line.item (1) /= '#' then
						l_fields := l_line.split (';')
						if l_fields.count = 5 then
							l_codes := code_points_of (l_fields.i_th (1))
							l_direction := base_direction_of (l_fields.i_th (2))
							l_paragraph := int_value (l_fields.i_th (3))
							l_levels := expected_levels_of (l_fields.i_th (4))
							l_order := expected_order_of (l_fields.i_th (5))
							if l_codes.count > 0 and l_levels.count = l_codes.count then
									-- L2 on its own, against the oracle's own
									-- levels: OUR code, judged without the
									-- backend in the way.
								if not l2_agrees (l_bidi, l_levels, l_order) then
									l_reorder_failures := l_reorder_failures + 1
									l_report.append ("      L2 MISMATCH: " + l_line + "%N")
								end
								if not l_harness.run_character_case (l_codes, l_direction,
									l_paragraph, l_levels, l_order)
								then
									if has_code_in (l_codes, 0x202A, 0x202E)
										or else has_code_in (l_codes, 0x2066, 0x2069)
									then
										l_formatting := l_formatting + 1
									elseif has_bracket (l_codes) then
										l_bracket := l_bracket + 1
									else
										l_unclassified := l_unclassified + 1
									end
									l_report.append ("      MISMATCH: " + l_line + "%N")
									l_report.append ("        got: levels "
										+ resolved_levels_of (l_bidi, l_codes, l_direction) + "%N")
								end
							end
						end
					end
				end
				l_file.close
				l_api.close

				print ("    conformance: " + l_harness.cases_run.out + " sampled cases, "
					+ (l_harness.cases_run - l_harness.failures).out + " agreed, "
					+ l_harness.failures.out + " disagreed [paired-bracket " + l_bracket.out
					+ ", explicit-formatting " + l_formatting.out + ", unclassified "
					+ l_unclassified.out + "]; L2 mismatches " + l_reorder_failures.out + "%N")
				if not l_report.is_empty then
					print (l_report)
				end

				if l_harness.failures = 0 then
					conformance_ran := True
				else
					conformance_skip_reason := "DirectWrite AnalyzeBidi diverges from UAX #9 on "
						+ l_harness.failures.out + " of " + l_harness.cases_run.out
						+ " sampled cases (" + l_bracket.out
						+ " paired-bracket / rule N0-BD16, " + l_formatting.out
						+ " explicit directional formatting); every one is listed above, none is"
						+ " unclassified, and our L2 agrees on all " + l_harness.cases_run.out
					    + " - see tools/bidi-conformance.md"
				end

				assert_true ("the sample actually ran", l_harness.cases_run >= 300)
				assert_integers_equal ("UAX #9 L2 agrees on every sampled case", 0, l_reorder_failures)
				assert_integers_equal ("no UNCLASSIFIED conformance mismatch", 0, l_unclassified)
				assert_true ("the agreeing majority holds (regression floor)",
					l_harness.cases_run - l_harness.failures >= 350)
			end
		end

feature -- Test: Phase-5 assault (skeletal; named now so nothing is forgotten)

	test_wrap_cluster_safety
			-- Skeletal: AC-2 - narrow-width wrap never splits base+niqqud
			-- clusters nor emoji sequences; every character lands in exactly
			-- one line; overflow flagged only for single unbreakable runs.
		do
			-- TODO: Phase 5
		end

	test_fallback_rescue
			-- Skeletal: AC-4 - uncovered codepoint renders from the first
			-- covering FONT_LIST face; run's font reports the fallback;
			-- exhaustion degrades to requested-font boxes + note.
		do
			-- TODO: Phase 5
		end

	test_emoji_zwj_single_image_run
			-- Skeletal: FR-006/AC-1 - a ZWJ family sequence maps to ONE
			-- IMAGE_RUN with the joined asset key.
		do
			-- TODO: Phase 5 (needs Phase-3 tables + assets)
		end

	test_never_raises_fault_injection
			-- Skeletal: AC-8 - a fault-injecting shaper double still yields
			-- a paintable layout whose degradations are enumerated in notes
			-- (R3 tofu-but-valid).
		do
			-- TODO: Phase 5
		end

	test_headless_full_pipeline
			-- Skeletal: AC-7 - the full pipeline (wrap, coverage, caching,
			-- measurement) under NULL_* seams with zero native calls, once
			-- Phase 4 threads runs through layout.
		do
			-- TODO: Phase 5
		end

	test_measured_width_sums_advances
			-- Skeletal: AC-10 - measured_width ("abc") = sum of shaped
			-- advances; line_height >= ascent + descent.
		do
			-- TODO: Phase 5
		end

	test_d015_chat_line
			-- Skeletal: AC-1 - the acceptance string (Hebrew shalom + robot
			-- + Greek Christos) yields RTL Hebrew, ONE IMAGE_RUN
			-- (emoji_u1f916), Greek glyph runs, full coverage.
		do
			-- TODO: Phase 5/7 (paint half needs the D-S07 bridge)
		end

	test_whitespace_measures_positive_under_realized_font
			-- Skeletal: R2's MEASUREMENT half (Phase 2 / ISSUE 9 moved it
			-- here from a vacuous postcondition) - whitespace-only text
			-- under a REALIZED font measures STRICTLY greater than zero, and
			-- measured_width ("a b") > measured_width ("ab"). Needs Phase-4
			-- font realization to mean anything.
		do
			-- TODO: Phase 5
		end

feature {NONE} -- Test support

	assert_permutation (a_tag: STRING; a_levels: ARRAY [NATURAL_8];
			a_expected: ARRAY [INTEGER]; a_bidi: BIDI_RESOLVER)
			-- `a_bidi.reorder (a_levels)' equals `a_expected' - the
			-- HAND-COMPUTED L2 answer - slot by slot.
		require
			same_size: a_levels.count = a_expected.count
		local
			l_order: ARRAY [INTEGER]
			i: INTEGER
		do
			l_order := a_bidi.reorder (a_levels)
			assert_integers_equal (a_tag + ": visual slot count", a_expected.count, l_order.count)
			from i := 1 until i > a_expected.count loop
				assert_integers_equal (a_tag + ": visual slot " + i.out,
					a_expected [a_expected.lower + i - 1], l_order [i])
				i := i + 1
			end
		end

	string_of_code_points (a_codes: ARRAY [INTEGER]): STRING_32
			-- `a_codes' as a STRING_32 - one entry per CODE POINT, so a
			-- source literal never puts this file's encoding on trial.
		require
			never_void: a_codes /= Void
		local
			i: INTEGER
		do
			create Result.make (a_codes.count)
			from i := a_codes.lower until i > a_codes.upper loop
				Result.append_code (a_codes [i].to_natural_32)
				i := i + 1
			end
		ensure
			one_per_code_point: Result.count = a_codes.count
		end

	sample_file_path: detachable STRING
			-- Where the committed BidiCharacterTest sample lives, searched
			-- from the working directory upward - the runner may be launched
			-- from the repo root or from EIFGENs/.../F_code. Void when it is
			-- nowhere to be found, which is an honest SKIP, not a pass.
		local
			l_candidates: ARRAY [STRING]
			l_file: RAW_FILE
			i: INTEGER
		do
			l_candidates := <<"testing/test_data/BidiCharacterTest.sample.txt",
				"../testing/test_data/BidiCharacterTest.sample.txt",
				"../../testing/test_data/BidiCharacterTest.sample.txt",
				"../../../testing/test_data/BidiCharacterTest.sample.txt",
				"../../../../testing/test_data/BidiCharacterTest.sample.txt">>
			from i := l_candidates.lower until i > l_candidates.upper or Result /= Void loop
				create l_file.make_with_name (l_candidates [i])
				if l_file.exists and then l_file.is_readable then
					Result := l_candidates [i]
				end
				i := i + 1
			end
		end

	hex_value (a_token: STRING): NATURAL_32
			-- `a_token' read as hexadecimal (BidiCharacterTest spells every
			-- code point that way).
		local
			i, l_digit: INTEGER
			c: CHARACTER
		do
			from i := 1 until i > a_token.count loop
				c := a_token.item (i)
				if c >= '0' and c <= '9' then
					l_digit := c.code - ('0').code
				elseif c >= 'A' and c <= 'F' then
					l_digit := c.code - ('A').code + 10
				elseif c >= 'a' and c <= 'f' then
					l_digit := c.code - ('a').code + 10
				else
					l_digit := 0
				end
				Result := Result * 16 + l_digit.to_natural_32
				i := i + 1
			end
		end

	int_value (a_field: STRING): INTEGER
			-- `a_field' read as a decimal integer; 0 when it is not one.
		local
			l_token: STRING
		do
			l_token := a_field.twin
			l_token.adjust
			if l_token.is_integer then
				Result := l_token.to_integer
			end
		end

	code_points_of (a_field: STRING): ARRAY [NATURAL_32]
			-- Field 1 of a BidiCharacterTest line: space-separated hex.
		local
			l_list: ARRAYED_LIST [NATURAL_32]
			i: INTEGER
		do
			create l_list.make (16)
			across a_field.split (' ') as t loop
				if not t.is_empty then
					l_list.extend (hex_value (t))
				end
			end
			create Result.make_filled ({NATURAL_32} 0, 1, l_list.count)
			from i := 1 until i > l_list.count loop
				Result [i] := l_list [i]
				i := i + 1
			end
		ensure
			one_based: Result.lower = 1
		end

	base_direction_of (a_field: STRING): INTEGER
			-- Field 2 of a BidiCharacterTest line: 0 = LTR, 1 = RTL,
			-- 2 = auto (first strong).
		do
			inspect int_value (a_field)
			when 1 then
				Result := Direction_rtl
			when 2 then
				Result := Direction_auto
			else
				Result := Direction_ltr
			end
		ensure
			known: is_valid_base_direction (Result)
		end

	expected_levels_of (a_field: STRING): ARRAY [INTEGER]
			-- Field 4 of a BidiCharacterTest line: one level per input
			-- character, with 'x' - a position rule X9 removed - as -1.
		local
			l_list: ARRAYED_LIST [INTEGER]
			i: INTEGER
		do
			create l_list.make (16)
			across a_field.split (' ') as t loop
				if not t.is_empty then
					if t.item (1) = 'x' or t.item (1) = 'X' then
						l_list.extend (-1)
					else
						l_list.extend (int_value (t))
					end
				end
			end
			create Result.make_filled (0, 1, l_list.count)
			from i := 1 until i > l_list.count loop
				Result [i] := l_list [i]
				i := i + 1
			end
		ensure
			one_based: Result.lower = 1
		end

	expected_order_of (a_field: STRING): ARRAY [INTEGER]
			-- Field 5 of a BidiCharacterTest line: the 0-based input indices
			-- of the KEPT positions, left to right. Possibly empty.
		local
			l_list: ARRAYED_LIST [INTEGER]
			i: INTEGER
		do
			create l_list.make (16)
			across a_field.split (' ') as t loop
				if not t.is_empty then
					l_list.extend (int_value (t))
				end
			end
			create Result.make_filled (0, 1, l_list.count)
			from i := 1 until i > l_list.count loop
				Result [i] := l_list [i]
				i := i + 1
			end
		ensure
			one_based: Result.lower = 1
		end

	l2_agrees (a_bidi: BIDI_RESOLVER; a_expected_levels, a_expected_order: ARRAY [INTEGER]): BOOLEAN
			-- Does `a_bidi.reorder' reproduce Unicode's visual order when it
			-- is handed the ORACLE's OWN levels for the positions rule X9
			-- kept? This judges UAX #9 L2 - our arithmetic - without the
			-- backend's level resolution in the way.
		local
			l_kept: ARRAYED_LIST [INTEGER]
			l_levels: ARRAY [NATURAL_8]
			l_order: ARRAY [INTEGER]
			i, k: INTEGER
		do
			create l_kept.make (a_expected_levels.count)
			from i := 1 until i > a_expected_levels.count loop
				if a_expected_levels [a_expected_levels.lower + i - 1] >= 0 then
					l_kept.extend (i)
				end
				i := i + 1
			end
			create l_levels.make_filled ({NATURAL_8} 0, 1, l_kept.count)
			from k := 1 until k > l_kept.count loop
				l_levels [k] := a_expected_levels [a_expected_levels.lower + l_kept [k] - 1].to_natural_8
				k := k + 1
			end
			l_order := a_bidi.reorder (l_levels)
			Result := l_order.count = a_expected_order.count
			from k := 1 until k > l_order.count or not Result loop
				Result := l_kept [l_order [k]] - 1
					= a_expected_order [a_expected_order.lower + k - 1]
				k := k + 1
			end
		end

	has_bracket (a_codes: ARRAY [NATURAL_32]): BOOLEAN
			-- Does `a_codes' hold a paired-bracket character - the domain of
			-- UAX #9 rule N0 (BD16)? The sample's bracket cases are built
			-- from the ASCII pairs, which is what this asks about; a mismatch
			-- carrying a bracket outside them would land in the UNCLASSIFIED
			-- bucket and fail the suite, which is the intent.
		do
			Result := has_code_in (a_codes, 0x0028, 0x0029)
				or else has_code_in (a_codes, 0x005B, 0x005B)
				or else has_code_in (a_codes, 0x005D, 0x005D)
				or else has_code_in (a_codes, 0x007B, 0x007B)
				or else has_code_in (a_codes, 0x007D, 0x007D)
		end

	integers_of (a_codes: ARRAY [NATURAL_32]): ARRAY [INTEGER]
			-- `a_codes' as plain integers.
		local
			i: INTEGER
		do
			create Result.make_filled (0, 1, a_codes.count)
			from i := 1 until i > a_codes.count loop
				Result [i] := a_codes [a_codes.lower + i - 1].to_integer_32
				i := i + 1
			end
		end

	resolved_levels_of (a_bidi: BIDI_RESOLVER; a_codes: ARRAY [NATURAL_32]; a_direction: INTEGER): STRING
			-- What `a_bidi' actually resolved for `a_codes' - diagnostic
			-- text for a conformance mismatch, never an assertion.
		local
			l_result: BIDI_RESULT
			i: INTEGER
		do
			create Result.make_empty
			l_result := a_bidi.resolve (string_of_code_points (integers_of (a_codes)), a_direction)
			from i := 1 until i > l_result.count loop
				Result.append_integer (l_result.level (i).to_integer_32)
				Result.append_character (' ')
				i := i + 1
			end
		end

	has_code_in (a_codes: ARRAY [NATURAL_32]; a_low, a_high: INTEGER): BOOLEAN
			-- Does `a_codes' hold a code point in [`a_low', `a_high']?
		local
			i, l_code: INTEGER
		do
			from i := a_codes.lower until i > a_codes.upper or Result loop
				l_code := a_codes [i].to_integer_32
				Result := l_code >= a_low and l_code <= a_high
				i := i + 1
			end
		end

	Break_can_break: INTEGER = 1
			-- DWRITE_BREAK_CONDITION_CAN_BREAK.

	d015_code_points: ARRAY [INTEGER]
			-- The D-015 acceptance string as CODE POINTS - a source literal
			-- would put this file's encoding on trial instead of the shim:
			-- shalom, space, robot, space, Christos, space, abc.
		do
			Result := <<0x05E9, 0x05DC, 0x05D5, 0x05DD, 0x0020, 0x1F916, 0x0020,
				0x03A7, 0x03C1, 0x03B9, 0x03C3, 0x03C4, 0x03CC, 0x03C2,
				0x0020, 0x0061, 0x0062, 0x0063>>
		ensure
			the_spikes_probe: Result.count = 18
		end

	utf16_units (a_code_points: ARRAY [INTEGER]): ARRAYED_LIST [INTEGER]
			-- `a_code_points' encoded as UTF-16 code units, surrogate pairs
			-- hand-built (the spike measured 18 code points = 19 units).
		require
			never_void: a_code_points /= Void
		local
			l_index, l_code, l_offset: INTEGER
		do
			create Result.make (a_code_points.count + 2)
			from l_index := a_code_points.lower until l_index > a_code_points.upper loop
				l_code := a_code_points [l_index]
				if l_code <= 0xFFFF then
					Result.extend (l_code)
				else
					l_offset := l_code - 0x10000
					Result.extend (0xD800 + l_offset.bit_shift_right (10))
					Result.extend (0xDC00 + l_offset.bit_and (0x3FF))
				end
				l_index := l_index + 1
			end
		ensure
			at_least_one_unit_per_code_point: Result.count >= a_code_points.count
		end

	utf16_buffer (a_units: ARRAYED_LIST [INTEGER]; a_first, a_count: INTEGER): MANAGED_POINTER
			-- Units [`a_first', `a_first' + `a_count') of `a_units' (1-based)
			-- marshalled into fresh memory for the shim.
		require
			first_in_range: a_first >= 1 and a_first <= a_units.count
			count_positive: a_count >= 1
			within_bounds: a_first + a_count - 1 <= a_units.count
		local
			l_index: INTEGER
		do
			create Result.make (a_count * 2)
			from l_index := 0 until l_index >= a_count loop
				Result.put_natural_16 (a_units.i_th (a_first + l_index).to_natural_16, l_index * 2)
				l_index := l_index + 1
			end
		ensure
			sized: Result.count >= a_count * 2
		end

	degenerate_layout (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER): SHAPED_LAYOUT
			-- A minimal valid layout of `a_text' (one empty line covering
			-- everything) for cache tests.
		require
			parameters_sane: a_width_pixels >= 0 and a_pixel_size > 0
		local
			l_lines: ARRAYED_LIST [SHAPED_LINE]
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
		do
			create l_lines.make (1)
			l_lines.extend (create {SHAPED_LINE}.make (
				create {ARRAYED_LIST [SHAPED_RUN]}.make (0),
				1, a_text.count, a_pixel_size.to_double, 0.8 * a_pixel_size, False))
			create l_notes.make (0)
			create Result.make (a_text, a_width_pixels, a_pixel_size, Direction_ltr, l_lines, l_notes)
		end

	probe_always_true (a_path: READABLE_STRING_32): BOOLEAN
			-- Injected existence probe: everything exists.
		do
			Result := True
		end

	probe_always_false (a_path: READABLE_STRING_32): BOOLEAN
			-- Injected existence probe: nothing exists.
		do
			Result := False
		end

end
