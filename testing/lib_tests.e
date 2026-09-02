note
	description: "[
		Phase-1 test set for simple_shaping: REAL tests wherever Phase 1
		carries real logic (value classes, FONT_LIST policy/digest,
		LAYOUT_CACHE with R8 verification and LRU eviction, the asset
		catalog's naming scheme and injected resolution, the NULL doubles,
		the facade's degenerate total-function layout with its cache
		discipline), plus SKELETAL stubs naming the Phase-5 assault
		(AC-1..AC-10) so nothing can be quietly forgotten.

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
feature -- Test: pinned emoji data and assets (Tasks 6 and 7)

	test_emoji_tables_pinned_version
			-- DR-013: the generated constant IS the acquisition record's
			-- Unicode emoji version, and a catalog built over those tables
			-- pins the same string - the invariant
			-- `tables_and_assets_pinned_together' is what keeps the shipped
			-- png set and the detection tables from drifting apart.
		note
			testing: "covers/{EMOJI_DATA_TABLES}.unicode_version"
		local
			l_tables: EMOJI_DATA_TABLES
			l_catalog: EMOJI_ASSET_CATALOG
		do
			create l_tables
			assert_equal ("R4 record: noto-emoji v2.051 states Unicode 17.0",
				"17.0", l_tables.unicode_version)
			create l_catalog.make ({STRING_32} "C:\assets", l_tables, agent probe_always_false)
			assert_equal ("catalog expectation pinned to the tables",
				"17.0", l_catalog.expected_unicode_version)
		end

	test_emoji_tables_extended_pictographic
			-- D-S08: the generated Extended_Pictographic table is real now,
			-- so the segmenter can finally SEE an emoji.
		note
			testing: "covers/{EMOJI_DATA_TABLES}.is_extended_pictographic"
		local
			l_tables: EMOJI_DATA_TABLES
		do
			create l_tables
			assert_true ("robot is pictographic",
				l_tables.is_extended_pictographic ({NATURAL_32} 0x1F916))
			assert_false ("latin A is not",
				l_tables.is_extended_pictographic ({NATURAL_32} 0x0041))
			assert_true ("copyright is pictographic (its asset is emoji_u00a9)",
				l_tables.is_extended_pictographic ({NATURAL_32} 0x00A9))
			assert_true ("regional indicator A is a regional indicator",
				l_tables.is_regional_indicator ({NATURAL_32} 0x1F1E6))
			assert_false ("regional indicators are NOT Extended_Pictographic",
				l_tables.is_extended_pictographic ({NATURAL_32} 0x1F1E6))
			assert_false ("the keycap base '#' is a component, not pictographic",
				l_tables.is_extended_pictographic ({NATURAL_32} 0x0023))
			assert_true ("robot starts a sequence",
				l_tables.is_emoji_starter ({NATURAL_32} 0x1F916))
			assert_true ("a regional indicator starts a sequence",
				l_tables.is_emoji_starter ({NATURAL_32} 0x1F1E6))
			assert_false ("latin A starts nothing",
				l_tables.is_emoji_starter ({NATURAL_32} 0x0041))
			assert_false ("a bare ZWJ starts nothing",
				l_tables.is_emoji_starter ({NATURAL_32} 0x200D))
		end

	test_emoji_tables_rgi_sequences
			-- Gate decision 4: the generator emits the RGI lookups the
			-- Task-8 longest match will call. VS16 is not significant -
			-- the key is canonicalized exactly as the catalog's is.
		note
			testing: "covers/{EMOJI_DATA_TABLES}.is_rgi_sequence"
		local
			l_tables: EMOJI_DATA_TABLES
			l_text: STRING_32
		do
			create l_tables
			assert_greater_than ("the RGI set is populated",
				l_tables.Rgi_sequence_count, 3000)
			assert_true ("woman technologist is an RGI ZWJ sequence",
				l_tables.is_rgi_sequence (<<{NATURAL_32} 0x1F469, {NATURAL_32} 0x200D, {NATURAL_32} 0x1F4BB>>))
			assert_true ("robot alone is RGI",
				l_tables.is_rgi_sequence (<<{NATURAL_32} 0x1F916>>))
			assert_true ("keycap # is RGI when fully qualified",
				l_tables.is_rgi_sequence (<<{NATURAL_32} 0x0023, {NATURAL_32} 0xFE0F, {NATURAL_32} 0x20E3>>))
			assert_true ("and the same keycap spelled without VS16",
				l_tables.is_rgi_sequence (<<{NATURAL_32} 0x0023, {NATURAL_32} 0x20E3>>))
			assert_true ("a skin-tone modifier sequence is RGI",
				l_tables.is_rgi_sequence (<<{NATURAL_32} 0x1F469, {NATURAL_32} 0x1F3FD>>))
			assert_false ("a bare keycap base is a component, not RGI",
				l_tables.is_rgi_sequence (<<{NATURAL_32} 0x0023>>))
			assert_false ("latin A is not RGI",
				l_tables.is_rgi_sequence (<<{NATURAL_32} 0x0041>>))
			assert_false ("two robots in a row are not one sequence",
				l_tables.is_rgi_sequence (<<{NATURAL_32} 0x1F916, {NATURAL_32} 0x1F916>>))

				-- Longest match: woman + ZWJ + laptop + 'A'.
			create l_text.make (4)
			l_text.append_code ({NATURAL_32} 0x1F469)
			l_text.append_code ({NATURAL_32} 0x200D)
			l_text.append_code ({NATURAL_32} 0x1F4BB)
			l_text.append_code ({NATURAL_32} 0x0041)
			assert_integers_equal ("the whole ZWJ family is one match",
				3, l_tables.longest_rgi_prefix_length (l_text, 1))
			assert_integers_equal ("nothing starts at the trailing A",
				0, l_tables.longest_rgi_prefix_length (l_text, 4))

				-- Longest match over a fully qualified keycap: # VS16 20E3.
			create l_text.make (3)
			l_text.append_code ({NATURAL_32} 0x0023)
			l_text.append_code ({NATURAL_32} 0xFE0F)
			l_text.append_code ({NATURAL_32} 0x20E3)
			assert_integers_equal ("the VS16 is consumed by the keycap match",
				3, l_tables.longest_rgi_prefix_length (l_text, 1))

				-- A lone woman followed by plain text matches only herself.
			create l_text.make (2)
			l_text.append_code ({NATURAL_32} 0x1F469)
			l_text.append_code ({NATURAL_32} 0x0041)
			assert_integers_equal ("one codepoint, not two",
				1, l_tables.longest_rgi_prefix_length (l_text, 1))
		end

	test_asset_catalog_over_real_assets
			-- Task 6: the ACQUIRED png/128 set, probed with a REAL file
			-- probe, resolves through the ISSUE-5 padded names. This is the
			-- test that would have caught unpadded `emoji_ua9.png'.
		note
			testing: "covers/{EMOJI_ASSET_CATALOG}.has_asset"
		local
			l_tables: EMOJI_DATA_TABLES
			l_catalog: EMOJI_ASSET_CATALOG
			l_directory: STRING_32
			l_path: IMMUTABLE_STRING_32
		do
			create l_tables
			l_directory := real_asset_directory
			assert_false ("assets\noto-emoji\png\128 located from CWD or the exe",
				l_directory.is_empty)
			create l_catalog.make (l_directory, l_tables, agent file_exists)
			assert_true ("the D-015 robot resolves",
				l_catalog.has_asset (<<{NATURAL_32} 0x1F916>>))
			l_path := l_catalog.asset_path (<<{NATURAL_32} 0x1F916>>)
			assert_true ("under the configured directory",
				l_path.starts_with (l_catalog.directory))
			assert_string_ends_with ("the Noto file name", l_path, "emoji_u1f916.png")
			assert_true ("copyright resolves through the four-digit padding",
				l_catalog.has_asset (<<{NATURAL_32} 0x00A9>>))
			assert_true ("registered resolves too",
				l_catalog.has_asset (<<{NATURAL_32} 0x00AE>>))
			assert_true ("the keycap resolves (VS16 dropped, base padded)",
				l_catalog.has_asset (<<{NATURAL_32} 0x0023, {NATURAL_32} 0xFE0F, {NATURAL_32} 0x20E3>>))
			assert_true ("the ZWJ family has a full-sequence asset (ladder rung 1)",
				l_catalog.has_asset (<<{NATURAL_32} 0x1F469, {NATURAL_32} 0x200D, {NATURAL_32} 0x1F4BB>>))
			assert_false ("two robots have no joint asset, so the ladder falls through",
				l_catalog.has_asset (<<{NATURAL_32} 0x1F916, {NATURAL_32} 0x1F916>>))
			assert_false ("a flag PAIR has no png in this release (rung 2 territory)",
				l_catalog.has_asset (<<{NATURAL_32} 0x1F1FA, {NATURAL_32} 0x1F1F8>>))
			assert_true ("but each flag half does",
				l_catalog.has_asset (<<{NATURAL_32} 0x1F1FA>>))
		end

feature -- Test: Phase-5 assault (skeletal; named now so nothing is forgotten)

	test_bidi_conformance_samples
			-- Skeletal: AC-5 - sampled BidiCharacterTest.txt cases through
			-- DIRECTWRITE_BIDI_RESOLVER via BIDI_CONFORMANCE_HARNESS
			-- (all-Hebrew, Hebrew+digits, mixed Hebrew/Latin).
		do
			-- TODO: Phase 5
		end

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

	file_exists (a_path: READABLE_STRING_32): BOOLEAN
			-- The PRODUCTION-shaped existence probe: does `a_path' name a
			-- file that is really on disk? Injected into EMOJI_ASSET_CATALOG
			-- for the tests that run over the acquired assets.
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			Result := l_file.exists
		end

	real_asset_directory: STRING_32
			-- Where the acquired Noto png/128 set lives, or empty when it
			-- cannot be found.
			--
			-- ROBUST PATH (documented because a test runner's working
			-- directory is not a contract): the search starts BOTH from the
			-- current working directory AND from the directory holding the
			-- running executable - the finalized test exe sits three levels
			-- below the repository root, in
			-- EIFGENs\simple_shaping_tests\F_code\ - and walks UP to six
			-- ancestors from each, taking the first that holds
			-- assets\noto-emoji\png\128\emoji_u1f916.png. So the suite passes
			-- whether it is launched from the repository root, from EIFGENs,
			-- or from the F_code folder itself.
		local
			l_environment: EXECUTION_ENVIRONMENT
			l_starts: ARRAYED_LIST [PATH]
			l_base, l_candidate: PATH
			i, l_step: INTEGER
			l_found: BOOLEAN
		do
			create Result.make_empty
			create l_environment
			create l_starts.make (2)
			l_starts.extend (l_environment.current_working_path)
			l_starts.extend ((create {PATH}.make_from_string (l_environment.arguments.command_name)).parent)
			from i := 1 until i > l_starts.count or l_found loop
				l_base := l_starts [i]
				from l_step := 0 until l_step > 6 or l_found loop
					l_candidate := l_base.extended ("assets").extended ("noto-emoji").extended ("png").extended ("128")
					if file_exists (l_candidate.extended ("emoji_u1f916.png").name) then
						Result := l_candidate.name.to_string_32
						l_found := True
					else
						l_base := l_base.parent
					end
					l_step := l_step + 1
				end
				i := i + 1
			end
		end

end
