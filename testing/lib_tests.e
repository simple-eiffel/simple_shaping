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
			l_cache.put ("k1", l_layout)
			l_hit := l_cache.item_verified ("k1", {STRING_32} "abc", 100, 16)
			assert_true ("verified hit is the stored layout", l_hit = l_layout)
			assert_void ("text mismatch demotes",
				l_cache.item_verified ("k1", {STRING_32} "abx", 100, 16))
			assert_void ("width mismatch demotes",
				l_cache.item_verified ("k1", {STRING_32} "abc", 99, 16))
			assert_void ("size mismatch demotes",
				l_cache.item_verified ("k1", {STRING_32} "abc", 100, 17))
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
			l_cache.put ("k1", l_layout)
			l_cache.put ("k2", l_layout)
			l_touched := l_cache.item_verified ("k1", {STRING_32} "abc", 100, 16)
			assert_true ("k1 touched for recency", l_touched /= Void)
			l_cache.put ("k3", l_layout)
			assert_integers_equal ("still bounded", 2, l_cache.count)
			assert_true ("k1 survived (touched)",
				l_cache.has_verified ("k1", {STRING_32} "abc", 100, 16))
			assert_false ("k2 evicted (oldest untouched)",
				l_cache.has_verified ("k2", {STRING_32} "abc", 100, 16))
			assert_true ("k3 present",
				l_cache.has_verified ("k3", {STRING_32} "abc", 100, 16))
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
			l_choice := l_fallback.font_for ({STRING_32} "ab", l_item, l_font)
			assert_same_reference ("requested font kept", l_font, l_choice.font)
			assert_true ("complete claimed", l_choice.is_complete_coverage)
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
		do
			create l_tables
			create l_catalog.make ({STRING_32} "C:\assets", l_tables, agent probe_always_false)
			create l_segmenter.make (l_tables, l_catalog)
			create l_levels.make_filled ({NATURAL_8} 0, 1, 2)
			create l_bidi.make (l_levels, 0)
			l_segments := l_segmenter.segment ({STRING_32} "ab", l_bidi)
			assert_integers_equal ("one plain segment", 1, l_segments.count)
			assert_true ("plain", l_segments.first.is_plain)
			create l_levels.make_empty
			create l_bidi.make (l_levels, 0)
			l_segments := l_segmenter.segment ({STRING_32} "", l_bidi)
			assert_true ("empty text has no segments", l_segments.is_empty)
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

feature {NONE} -- Test support

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
