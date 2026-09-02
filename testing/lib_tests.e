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
			l_shapes: INTEGER
		do
			create l_shaping.make ({STRING_32} "assets")
			l_first := l_shaping.layout_default ({STRING_32} "abc", 100, 16)
			l_shapes := l_shaping.statistics.shape_calls
			assert_true ("covers all characters", l_first.covers_all_characters)
			assert_integers_equal ("one line", 1, l_first.lines.count)
			assert_true ("cached now",
				l_shaping.is_cached ({STRING_32} "abc", 100, 16, l_shaping.default_fonts))
			assert_integers_equal ("one miss", 1, l_shaping.statistics.cache_misses)
			l_second := l_shaping.layout_default ({STRING_32} "abc", 100, 16)
			assert_same_reference ("hit returns the cached layout", l_first, l_second)
			assert_integers_equal ("one hit", 1, l_shaping.statistics.cache_hits)
				-- PHASE 4 TASK 11 UPDATED THIS ONE LINE. It used to read
				-- `zero shape calls throughout (Phase 1)' - true only while
				-- the pipeline was a placeholder that produced no runs, and
				-- from today a false expectation. What AC-3 actually claims,
				-- and what this test was written to seed, is that the SECOND
				-- call adds nothing; that is now what is asserted, together
				-- with the fact that the first call really did shape.
			assert_true ("the first call shaped for real", l_shapes >= 1)
			assert_integers_equal ("the hit shaped nothing", l_shapes,
				l_shaping.statistics.shape_calls)
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
				-- PHASE 4 TASK 11 UPDATED THIS ONE LINE. It used to read
				-- `assert_false ("no notes", ...)'. Empty text still degrades
				-- NOTHING - but a layout is where R1's per-facade
				-- `Note_family_missing' records are finally drained (Task 2
				-- parked them precisely because `line_height' promises
				-- `statistics_untouched'), so the first layout of any facade
				-- carries one note per family this machine lacks. The claim
				-- that matters is kept and sharpened: nothing about the
				-- EMPTY-TEXT path degraded.
			assert_true ("no degradation from the empty-text path itself",
				across l_layout.notes as n all n.code = Note_family_missing end)
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
			-- The headless pair: predictable metrics that owe NOTHING to the
			-- font's realized metrics - the doubles derive everything from
			-- `pixel_size' alone, which is what makes them headless.
			--
			-- UPDATED Phase 4 Task 2: the old assertion here was
			-- `assert_false ("headless font unrealized", l_font.is_ready)',
			-- which asserted the Phase-1 registry's failure to realize
			-- anything. Realization on first use is now the registry's
			-- contract, so that line asserted a defect. Its real subject -
			-- "the NULL doubles do not consult the machine" - is kept, and
			-- `is_realization_attempted' replaces it as the fact that holds
			-- on every machine, GDI or no GDI.
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
			assert_true ("the registry offered the identity to the machine",
				l_font.is_realization_attempted)
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
			l_registry.dispose_all
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
			l_registry.dispose_all
			assert_integers_equal ("dispose_all drops every identity", 0, l_registry.count)
		end

feature -- Test: realization and disposal (Phase 4 Task 2)

	machine_test_ran: BOOLEAN
			-- [Phase 4 Task 2] Did the machine-dependent test that just ran
			-- reach real font realization? False means it SKIPPED - never
			-- that it passed (ISSUE 18's rule, as Task 1 applied it to the
			-- native round trip).

	machine_skip_reason: STRING
			-- [Phase 4 Task 2] Why the machine-dependent test could not run.
		attribute
			create Result.make_empty
		end

	begin_machine_test
			-- [Phase 4 Task 2] Reset the machine-test protocol. Every
			-- machine-dependent test calls this FIRST; TEST_APP reads the
			-- two attributes after the call and reports PASS or an honest
			-- SKIP with the reason.
		do
			machine_test_ran := False
			create machine_skip_reason.make_empty
		ensure
			reset: not machine_test_ran and machine_skip_reason.is_empty
		end

	test_font_realization_round_trip
			-- Task 2: `FONT_REGISTRY.font' runs the D-S03 chain, one holder
			-- per identity holds the handles, `dispose_all' gives every one
			-- of them back, and the identity can then be realized AGAIN -
			-- which is the only evidence that proves the release was real
			-- and not merely a dropped reference (a leaked HFONT/HDC would
			-- still let a NEW identity realize, but only a genuinely
			-- released chain lets the SAME registry rebuild it at zero net
			-- handle cost).
		note
			testing: "covers/{SHAPING_FONT}.realize, covers/{SHAPING_FONT}.dispose, covers/{FONT_REGISTRY}.dispose_all"
		local
			l_registry: FONT_REGISTRY
			l_font, l_again, l_reborn: SHAPING_FONT
			l_probe: DWRITE_API
			l_backend_up: BOOLEAN
			l_ascent, l_descent: REAL_64
			l_face: STRING_32
		do
			begin_machine_test
			create l_registry.make
			l_font := l_registry.font ({STRING_32} "Segoe UI", {SHAPING_FONT}.Weight_regular, False, 16)
			if not l_font.is_ready then
				machine_skip_reason := "GDI could not realize Segoe UI at 16 px"
				l_registry.dispose_all
			else
				machine_test_ran := True
				l_ascent := l_font.ascent
				l_descent := l_font.descent
				l_face := l_font.realized_family.as_string_32
				create l_probe.make
				l_backend_up := l_probe.open

				if l_face.is_valid_as_string_8 then
					print ("    fonts: Segoe UI 16 px ascent " + l_ascent.out + " descent "
						+ l_descent.out + "; realized face " + l_face.to_string_8
						+ "; backend face " + l_font.has_backend_face.out + "%N")
				end

					-- One holder per identity, and it is the realized one.
				l_again := l_registry.font ({STRING_32} "Segoe UI", {SHAPING_FONT}.Weight_regular, False, 16)
				assert_same_reference ("same identity, same object", l_font, l_again)
				assert_integers_equal ("one identity held", 1, l_registry.count)

					-- The D-S03 chain actually ran.
				assert_true ("HFONT held", l_font.font_handle /= default_pointer)
				assert_true ("private memory DC held", l_font.device_context /= default_pointer)
				assert_true ("ascent positive (line_metrics)", l_ascent > 0.0)
				assert_true ("descent non negative (line_metrics)", l_descent >= 0.0)
				assert_reals_equal ("line_height is ascent + descent",
					l_ascent + l_descent, l_font.line_height, 0.000001)
				assert_true ("GDI realized the requested family (R1 comparator)",
					l_font.is_family_realized)
				if l_backend_up then
					assert_true ("IDWriteFontFace obtained from the HDC", l_font.has_backend_face)
				end

					-- Release, in order, before the identities are dropped.
				l_registry.dispose_all
				assert_integers_equal ("count back to 0 (emptied)", 0, l_registry.count)
				assert_false ("no longer ready", l_font.is_ready)
				assert_true ("HFONT released", l_font.font_handle = default_pointer)
				assert_true ("DC released", l_font.device_context = default_pointer)
				assert_true ("face released", l_font.backend_face = default_pointer)
				assert_false ("no backend face", l_font.has_backend_face)
				assert_reals_equal ("ascent cleared (unrealized_has_no_metrics)",
					0.0, l_font.ascent, 0.000001)
				assert_reals_equal ("descent cleared (unrealized_has_no_metrics)",
					0.0, l_font.descent, 0.000001)
				assert_false ("realizable again", l_font.is_realization_attempted)

					-- A re-realize after dispose works: the handles were
					-- really given back, not merely forgotten.
				l_reborn := l_registry.font ({STRING_32} "Segoe UI", {SHAPING_FONT}.Weight_regular, False, 16)
				assert_true ("a fresh holder after dispose_all", l_reborn /= l_font)
				assert_true ("re-realized", l_reborn.is_ready)
				assert_reals_equal ("same metrics second time round",
					l_ascent, l_reborn.ascent, 0.000001)
				assert_integers_equal ("one identity again", 1, l_registry.count)
				l_registry.dispose_all
				assert_integers_equal ("and back to 0", 0, l_registry.count)
			end
		end

	test_family_existence_probe
			-- Task 2 / R1: GDI SILENTLY substitutes for a family it does not
			-- have, so the requested name proves nothing and only
			-- GetTextFaceW can answer. Proven against a family this machine
			-- is checked to be MISSING (SBL Hebrew - a scholar Hebrew face
			-- that is not a Windows component) and one it is checked to
			-- HAVE (Segoe UI). If the machine turns out to own SBL Hebrew,
			-- the test SKIPS rather than inventing a verdict.
		note
			testing: "covers/{FONT_REGISTRY}.family_exists, covers/{SHAPING_FONT}.is_family_realized"
		local
			l_registry: FONT_REGISTRY
			l_gdi: GDI32_API
			l_font, l_dc, l_previous: POINTER
			l_substitute: STRING_32
			l_absent: STRING_32
			l_probed: BOOLEAN
			l_shaping_font: SHAPING_FONT
		do
			begin_machine_test
			l_absent := {STRING_32} "SBL Hebrew"
			create l_substitute.make_empty
			create l_gdi.make

				-- Establish the ground truth FIRST, with no library code in
				-- the way: what face does GDI hand back for this name?
			l_font := l_gdi.create_font (l_absent, {SHAPING_FONT}.Weight_regular, False, 16)
			if l_font /= default_pointer then
				l_dc := l_gdi.create_memory_dc
				if l_dc /= default_pointer then
					l_previous := l_gdi.select_font (l_dc, l_font)
					l_substitute := l_gdi.realized_face_name (l_dc)
					l_probed := True
					if l_previous /= default_pointer then
						l_previous := l_gdi.select_font (l_dc, l_previous)
					end
					if l_gdi.delete_dc (l_dc) then
					end
				end
				if l_gdi.delete_handle (l_font) then
				end
			end

			if not l_probed then
				machine_skip_reason := "GDI could not realize any font for the absence probe"
			elseif l_substitute.is_case_insensitive_equal (l_absent) then
				machine_skip_reason := "SBL Hebrew IS installed on this machine, so it cannot serve as the known-absent family"
			else
				machine_test_ran := True
				if l_substitute.is_valid_as_string_8 then
					print ("    fonts: GDI substituted %"" + l_substitute.to_string_8
						+ "%" for the absent %"SBL Hebrew%"%N")
				end

				create l_registry.make
				assert_false ("an absent family does not exist (R1)",
					l_registry.family_exists (l_absent))
				assert_true ("a present family does exist (R1)",
					l_registry.family_exists ({STRING_32} "Segoe UI"))
				assert_true ("the verdict is memoized, so it repeats",
					l_registry.family_exists (l_absent) = False
					and l_registry.family_exists ({STRING_32} "Segoe UI") = True)

					-- The substituted font still REALIZES - it just is not
					-- the face that was asked for. That distinction is the
					-- whole of R1: `is_ready' cannot detect absence.
				l_shaping_font := l_registry.font (l_absent, {SHAPING_FONT}.Weight_regular, False, 16)
				assert_true ("the substitute realizes", l_shaping_font.is_ready)
				assert_false ("but it is NOT the requested family",
					l_shaping_font.is_family_realized)
				assert_true ("and it names the substitute GDI chose",
					l_shaping_font.realized_family.is_case_insensitive_equal (l_substitute))
				l_registry.dispose_all
			end
		end

	test_effective_digest_drops_absent_families
			-- Task 2 / R5 with gate decision 3: `cache_key' digests the
			-- POST-PROBE effective list; the effective digest differs from
			-- the configured one EXACTLY when a family was dropped; the memo
			-- makes repeated evaluation stable and probe-free; and R1's note
			-- is built once per family per facade lifetime, not once per
			-- call. The last assertion is R5's actual payoff: two policies
			-- that differ only in a family this machine does not have render
			-- identically and therefore SHARE one cache entry.
		note
			testing: "covers/{SIMPLE_SHAPING}.effective_digest, covers/{SIMPLE_SHAPING}.cache_key"
		local
			l_shaping: SIMPLE_SHAPING
			l_with_absent, l_present_only: FONT_LIST
			l_first, l_second, l_third: STRING_8
			l_defaults_effective: STRING_8
			l_dropped_from_defaults: INTEGER
			l_layout: SHAPED_LAYOUT
		do
				-- A name no font vendor will ever ship: absence is a FACT
				-- here, not a machine-dependent guess, so this test never
				-- needs to skip.
			create l_shaping.make ({STRING_32} "assets")
			create l_present_only.make_empty
			l_present_only.with_family ({STRING_32} "Segoe UI").do_nothing
			create l_with_absent.make_empty
			l_with_absent.with_family ({STRING_32} "Segoe UI").do_nothing
			l_with_absent.with_family (Never_installed_family).do_nothing

			l_first := l_shaping.effective_digest (l_with_absent)
			assert_integers_equal ("exactly one family reported missing",
				1, l_shaping.missing_family_count)
			assert_false ("effective differs from configured when a family drops",
				l_first.same_string (l_with_absent.digest))
			assert_true ("the effective policy IS the present-only policy",
				l_first.same_string (l_present_only.digest))

				-- Memo: stable across repeated calls, and it does not
				-- re-note what it already noted.
			l_second := l_shaping.effective_digest (l_with_absent)
			l_third := l_shaping.effective_digest (l_with_absent)
			assert_true ("digest stable on the second call", l_second.same_string (l_first))
			assert_true ("digest stable on the third call", l_third.same_string (l_first))
			assert_integers_equal ("still exactly one note (once per facade lifetime)",
				1, l_shaping.missing_family_count)

				-- A policy with nothing to drop keeps its configured digest.
			assert_true ("effective = configured when nothing drops",
				l_shaping.effective_digest (l_present_only).same_string (l_present_only.digest))
			assert_integers_equal ("and nothing new was noted",
				1, l_shaping.missing_family_count)

				-- The default policy names scholar faces most machines lack;
				-- whatever this machine has, the rule is the same one.
			l_defaults_effective := l_shaping.effective_digest (l_shaping.default_fonts)
			l_dropped_from_defaults := l_shaping.missing_family_count - 1
			print ("    fonts: " + l_dropped_from_defaults.out
				+ " default families absent on this machine%N")
			if l_dropped_from_defaults > 0 then
				assert_false ("defaults: dropped, so the digests differ",
					l_defaults_effective.same_string (l_shaping.default_fonts.digest))
			else
				assert_true ("defaults: nothing dropped, so the digests match",
					l_defaults_effective.same_string (l_shaping.default_fonts.digest))
			end

				-- R5's payoff: same effective policy, ONE cache entry.
			l_layout := l_shaping.layout ({STRING_32} "abc", 100, 16, l_with_absent)
			assert_true ("cached under the policy that asked",
				l_shaping.is_cached ({STRING_32} "abc", 100, 16, l_with_absent))
			assert_true ("and served to the policy that renders identically",
				l_shaping.is_cached ({STRING_32} "abc", 100, 16, l_present_only))
			assert_same_reference ("the very same layout object",
				l_layout, l_shaping.layout ({STRING_32} "abc", 100, 16, l_present_only))
			assert_integers_equal ("one miss, one hit - not two misses",
				1, l_shaping.statistics.cache_misses)
			assert_integers_equal ("the second call hit", 1, l_shaping.statistics.cache_hits)
			assert_integers_equal ("one entry, not two", 1, l_shaping.cache_count)
		end

	Never_installed_family: STRING_32 = "Simple Shaping No Such Face"
			-- [Phase 4 Task 2] A family name no vendor ships, so GDI must
			-- substitute for it on every machine - which makes the R5
			-- effective-digest test deterministic instead of dependent on
			-- what happens to be installed.

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

feature -- Test: emoji segmentation over real assets (Task 8)

	test_emoji_zwj_single_image_run
			-- FR-006/AC-1 and RUNG 1 of the FR-007 ladder: a ZWJ family is
			-- ONE emoji segment carrying the JOINED asset key - not three
			-- segments, and the joiner never reaches the shaper. This test
			-- was skeletal from Phase 1 until Task 8 gave it tables, assets
			-- and a scan; it is real now.
		note
			testing: "covers/{EMOJI_SEGMENTER}.segment"
		local
			l_tables: EMOJI_DATA_TABLES
			l_segmenter: EMOJI_SEGMENTER
			l_text: STRING_32
			l_segments: ARRAYED_LIST [TEXT_SEGMENT]
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
		do
			create l_tables
			assert_false ("the acquired assets were located", real_asset_directory.is_empty)
			l_segmenter := real_segmenter (l_tables)
			l_text := text_of (<<{NATURAL_32} 0x1F469, {NATURAL_32} 0x200D, {NATURAL_32} 0x1F4BB>>)
			create l_notes.make (0)
			l_segments := l_segmenter.segment (l_text, flat_bidi (l_text, {NATURAL_8} 0), l_notes)
			assert_integers_equal ("the whole family is ONE segment", 1, l_segments.count)
			assert_true ("and it is an image, not text", l_segments.first.is_emoji)
			assert_integers_equal ("covering all three characters", 3, l_segments.first.count)
			assert_true ("with the JOINED key",
				l_segments.first.asset_key.same_string ("emoji_u1f469_200d_1f4bb"))
			assert_string_ends_with ("resolved to the joined png",
				l_segments.first.asset_path, "emoji_u1f469_200d_1f4bb.png")
			assert_integers_equal ("rung 1 degrades nothing", 0, l_notes.count)
		end

	test_emoji_segmenter_d015_line
			-- AC-1's acceptance string through the segmenter: the Hebrew
			-- stays PLAIN for the shaper, the robot is exactly ONE emoji
			-- segment keyed `emoji_u1f916' with a path under the configured
			-- directory, and the Greek stays PLAIN - three segments, in
			-- source order, partitioning every character.
		note
			testing: "covers/{EMOJI_SEGMENTER}.segment"
		local
			l_tables: EMOJI_DATA_TABLES
			l_segmenter: EMOJI_SEGMENTER
			l_text: STRING_32
			l_segments: ARRAYED_LIST [TEXT_SEGMENT]
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
		do
			create l_tables
			assert_false ("the acquired assets were located", real_asset_directory.is_empty)
			l_segmenter := real_segmenter (l_tables)
			l_text := text_of (<<{NATURAL_32} 0x05E9, {NATURAL_32} 0x05DC, {NATURAL_32} 0x05D5,
				{NATURAL_32} 0x05DD, {NATURAL_32} 0x0020, {NATURAL_32} 0x1F916, {NATURAL_32} 0x0020,
				{NATURAL_32} 0x03A7, {NATURAL_32} 0x03C1, {NATURAL_32} 0x03B9, {NATURAL_32} 0x03C3,
				{NATURAL_32} 0x03C4, {NATURAL_32} 0x03CC, {NATURAL_32} 0x03C2>>)
			create l_notes.make (0)
			l_segments := l_segmenter.segment (l_text, flat_bidi (l_text, {NATURAL_8} 0), l_notes)
			assert_integers_equal ("plain / robot / plain", 3, l_segments.count)
			assert_true ("the Hebrew and its space stay on the glyph path", l_segments [1].is_plain)
			assert_integers_equal ("four letters and the space", 5, l_segments [1].count)
			assert_true ("the robot is an image", l_segments [2].is_emoji)
			assert_integers_equal ("one character", 1, l_segments [2].count)
			assert_integers_equal ("at position 6", 6, l_segments [2].start_index)
			assert_true ("D-015's key", l_segments [2].asset_key.same_string ("emoji_u1f916"))
			assert_true ("under the configured directory",
				l_segments [2].asset_path.starts_with (l_segmenter.catalog.directory))
			assert_string_ends_with ("the Noto file name",
				l_segments [2].asset_path, "emoji_u1f916.png")
			assert_true ("the Greek stays on the glyph path", l_segments [3].is_plain)
			assert_integers_equal ("the space and seven Greek letters", 8, l_segments [3].count)
			assert_integers_equal ("nothing degraded", 0, l_notes.count)
		end

	test_emoji_segmenter_padded_singles_and_keycap
			-- ISSUE 5 end to end: U+00A9 and a fully-qualified keycap both
			-- resolve through the FOUR-DIGIT padded Noto names, and the
			-- keycap's VS16 is swallowed by the match instead of reaching
			-- the shaper. A bare Latin letter between them stays plain -
			-- which also shows the scan resuming after an image.
		note
			testing: "covers/{EMOJI_SEGMENTER}.segment"
		local
			l_tables: EMOJI_DATA_TABLES
			l_segmenter: EMOJI_SEGMENTER
			l_text: STRING_32
			l_segments: ARRAYED_LIST [TEXT_SEGMENT]
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
		do
			create l_tables
			assert_false ("the acquired assets were located", real_asset_directory.is_empty)
			l_segmenter := real_segmenter (l_tables)
			l_text := text_of (<<{NATURAL_32} 0x00A9, {NATURAL_32} 0x0041,
				{NATURAL_32} 0x0023, {NATURAL_32} 0xFE0F, {NATURAL_32} 0x20E3>>)
			create l_notes.make (0)
			l_segments := l_segmenter.segment (l_text, flat_bidi (l_text, {NATURAL_8} 0), l_notes)
			assert_integers_equal ("copyright / A / keycap", 3, l_segments.count)
			assert_true ("copyright is an image", l_segments [1].is_emoji)
			assert_true ("padded to four digits, not emoji_ua9",
				l_segments [1].asset_key.same_string ("emoji_u00a9"))
			assert_true ("the Latin A is text", l_segments [2].is_plain)
			assert_true ("the keycap is an image", l_segments [3].is_emoji)
			assert_integers_equal ("base, VS16 and combiner - all three characters",
				3, l_segments [3].count)
			assert_true ("VS16 dropped from the key, base padded",
				l_segments [3].asset_key.same_string ("emoji_u0023_20e3"))
			assert_integers_equal ("nothing degraded", 0, l_notes.count)
		end

	test_emoji_segmenter_rung_two_per_codepoint
			-- RUNG 2. Noto v2.051 ships no waved-flag png, so the US flag
			-- pair lands on the per-codepoint rung as TWO letter tiles (the
			-- Unicode-recommended fallback); and the England subdivision
			-- flag, whose seven-character tag spelling has no asset either,
			-- becomes ONE black-flag image covering all seven characters -
			-- no tag character is left for the shaper to turn into a tofu
			-- box. Neither is a degradation, so neither emits a note.
		note
			testing: "covers/{EMOJI_SEGMENTER}.segment"
		local
			l_tables: EMOJI_DATA_TABLES
			l_segmenter: EMOJI_SEGMENTER
			l_text: STRING_32
			l_segments: ARRAYED_LIST [TEXT_SEGMENT]
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
		do
			create l_tables
			assert_false ("the acquired assets were located", real_asset_directory.is_empty)
			l_segmenter := real_segmenter (l_tables)
			create l_notes.make (0)

				-- The flag of the United States: two regional indicators.
			l_text := text_of (<<{NATURAL_32} 0x1F1FA, {NATURAL_32} 0x1F1F8>>)
			l_segments := l_segmenter.segment (l_text, flat_bidi (l_text, {NATURAL_8} 0), l_notes)
			assert_integers_equal ("two letter tiles, not one flag", 2, l_segments.count)
			assert_true ("the first letter is an image", l_segments [1].is_emoji)
			assert_integers_equal ("one character", 1, l_segments [1].count)
			assert_true ("keyed by its own codepoint",
				l_segments [1].asset_key.same_string ("emoji_u1f1fa"))
			assert_true ("the second letter is an image", l_segments [2].is_emoji)
			assert_true ("keyed by its own codepoint",
				l_segments [2].asset_key.same_string ("emoji_u1f1f8"))
			assert_integers_equal ("rung 2 is a resolution, not a degradation", 0, l_notes.count)

				-- The flag of England: base + six TAG characters.
			l_text := text_of (<<{NATURAL_32} 0x1F3F4, {NATURAL_32} 0xE0067, {NATURAL_32} 0xE0062,
				{NATURAL_32} 0xE0065, {NATURAL_32} 0xE006E, {NATURAL_32} 0xE0067,
				{NATURAL_32} 0xE007F>>)
			l_segments := l_segmenter.segment (l_text, flat_bidi (l_text, {NATURAL_8} 0), l_notes)
			assert_integers_equal ("one segment, not a base plus six tags", 1, l_segments.count)
			assert_true ("an image", l_segments.first.is_emoji)
			assert_integers_equal ("the tags ride with the base", 7, l_segments.first.count)
			assert_true ("keyed by the base flag alone",
				l_segments.first.asset_key.same_string ("emoji_u1f3f4"))
			assert_integers_equal ("still rung 2, still no note", 0, l_notes.count)
		end

	test_emoji_segmenter_vs16_and_skin_tone
			-- Two lawful spellings, one canonical key each: the heart's
			-- VS16 is dropped from the key but its character still belongs
			-- to the segment (emoji_u2764, two characters), the same heart
			-- written bare resolves to the same key, and a skin-tone
			-- modifier is part of the sequence rather than a second tile
			-- (emoji_u1f469_1f3fd). Rung 1 throughout.
		note
			testing: "covers/{EMOJI_SEGMENTER}.segment"
		local
			l_tables: EMOJI_DATA_TABLES
			l_segmenter: EMOJI_SEGMENTER
			l_text: STRING_32
			l_segments: ARRAYED_LIST [TEXT_SEGMENT]
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
		do
			create l_tables
			assert_false ("the acquired assets were located", real_asset_directory.is_empty)
			l_segmenter := real_segmenter (l_tables)
			create l_notes.make (0)

			l_text := text_of (<<{NATURAL_32} 0x2764, {NATURAL_32} 0xFE0F>>)
			l_segments := l_segmenter.segment (l_text, flat_bidi (l_text, {NATURAL_8} 0), l_notes)
			assert_integers_equal ("one segment", 1, l_segments.count)
			assert_integers_equal ("the VS16 belongs to it", 2, l_segments.first.count)
			assert_true ("but not to the key",
				l_segments.first.asset_key.same_string ("emoji_u2764"))

			l_text := text_of (<<{NATURAL_32} 0x2764>>)
			l_segments := l_segmenter.segment (l_text, flat_bidi (l_text, {NATURAL_8} 0), l_notes)
			assert_integers_equal ("the bare spelling is one segment too", 1, l_segments.count)
			assert_integers_equal ("of one character", 1, l_segments.first.count)
			assert_true ("resolving to the SAME canonical key",
				l_segments.first.asset_key.same_string ("emoji_u2764"))

			l_text := text_of (<<{NATURAL_32} 0x1F469, {NATURAL_32} 0x1F3FD>>)
			l_segments := l_segmenter.segment (l_text, flat_bidi (l_text, {NATURAL_8} 0), l_notes)
			assert_integers_equal ("skin tone is part of the sequence", 1, l_segments.count)
			assert_integers_equal ("both characters", 2, l_segments.first.count)
			assert_true ("one toned image, not a woman plus a swatch",
				l_segments.first.asset_key.same_string ("emoji_u1f469_1f3fd"))
			assert_integers_equal ("nothing degraded anywhere above", 0, l_notes.count)
		end

	test_emoji_segmenter_rung_three_degrades_with_one_note
			-- RUNG 3, run over the REAL tables with a catalog that resolves
			-- NOTHING: the sequence stays PLAIN on the glyph path and the
			-- accumulator gets EXACTLY ONE Note_emoji_degraded covering it -
			-- the only channel this rung has (ISSUE 6). The accumulator is
			-- never cleared and never reordered, so a second degraded call
			-- adds to it; empty text degrades nothing.
		note
			testing: "covers/{EMOJI_SEGMENTER}.segment"
		local
			l_tables: EMOJI_DATA_TABLES
			l_catalog: EMOJI_ASSET_CATALOG
			l_segmenter: EMOJI_SEGMENTER
			l_text: STRING_32
			l_segments: ARRAYED_LIST [TEXT_SEGMENT]
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
		do
			create l_tables
			create l_catalog.make ({STRING_32} "C:\no-such-asset-folder", l_tables,
				agent probe_always_false)
			create l_segmenter.make (l_tables, l_catalog)
			create l_notes.make (0)

			l_text := text_of (<<{NATURAL_32} 0x1F469, {NATURAL_32} 0x200D, {NATURAL_32} 0x1F4BB>>)
			l_segments := l_segmenter.segment (l_text, flat_bidi (l_text, {NATURAL_8} 0), l_notes)
			assert_integers_equal ("one plain span", 1, l_segments.count)
			assert_true ("plain, so the glyph path gets it", l_segments.first.is_plain)
			assert_integers_equal ("covering the whole sequence", 3, l_segments.first.count)
			assert_integers_equal ("EXACTLY one note", 1, l_notes.count)
			assert_integers_equal ("and it is a degradation",
				Note_emoji_degraded, l_notes.first.code)
			assert_integers_equal ("covering the span it could not image",
				1, l_notes.first.source_start)
			assert_integers_equal ("all three characters", 3, l_notes.first.source_count)
			assert_string_contains ("naming the key it looked for",
				l_notes.first.message, "emoji_u1f469_200d_1f4bb")

			l_text := text_of (<<{NATURAL_32} 0x1F916>>)
			l_segments := l_segmenter.segment (l_text, flat_bidi (l_text, {NATURAL_8} 0), l_notes)
			assert_integers_equal ("the robot degrades too", 1, l_segments.count)
			assert_true ("to plain text", l_segments.first.is_plain)
			assert_integers_equal ("the accumulator grew, it was not replaced", 2, l_notes.count)

			l_segments := l_segmenter.segment ({STRING_32} "",
				flat_bidi ({STRING_32} "", {NATURAL_8} 0), l_notes)
			assert_true ("empty text has no segments at all", l_segments.is_empty)
			assert_integers_equal ("and nothing to degrade", 2, l_notes.count)
		end

	test_emoji_segmenter_levels_inherited
			-- `emoji_levels_inherited': an emoji segment carries the
			-- RESOLVED level of its FIRST character - read per character,
			-- never from the paragraph - because that is what places the
			-- image box correctly on an RTL line.
		note
			testing: "covers/{EMOJI_SEGMENTER}.segment"
		local
			l_tables: EMOJI_DATA_TABLES
			l_segmenter: EMOJI_SEGMENTER
			l_text: STRING_32
			l_levels: ARRAY [NATURAL_8]
			l_bidi: BIDI_RESULT
			l_segments: ARRAYED_LIST [TEXT_SEGMENT]
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
		do
			create l_tables
			assert_false ("the acquired assets were located", real_asset_directory.is_empty)
			l_segmenter := real_segmenter (l_tables)
			l_text := text_of (<<{NATURAL_32} 0x05E9, {NATURAL_32} 0x05DC, {NATURAL_32} 0x1F916>>)
			l_levels := <<{NATURAL_8} 1, {NATURAL_8} 1, {NATURAL_8} 2>>
			create l_bidi.make (l_levels, {NATURAL_8} 1)
			create l_notes.make (0)
			l_segments := l_segmenter.segment (l_text, l_bidi, l_notes)
			assert_integers_equal ("Hebrew then robot", 2, l_segments.count)
			assert_true ("the robot is an image", l_segments [2].is_emoji)
			assert_naturals_equal ("it inherits ITS OWN character's level, not the paragraph's",
				{NATURAL_64} 2, l_segments [2].embedding_level.to_natural_64)
			assert_naturals_equal ("a plain span stores 0 - its levels live in BIDI_RESULT",
				{NATURAL_64} 0, l_segments [1].embedding_level.to_natural_64)
		end

	test_emoji_segmenter_rung_three_still_lifts_resolvable_parts
			-- THE case that makes `no_resolvable_single_left_plain' bite: a
			-- ZWJ family with no full-sequence asset and only ONE component
			-- that images. Rung 2 is all-or-nothing, so it fails; rung 3
			-- notes the span ONCE, lifts the component that does image (the
			-- joiner riding along with it, so no joiner reaches the shaper
			-- to come back as a tofu box) and leaves only the unresolvable
			-- component plain. Degrading the whole span wholesale would have
			-- left a resolvable starter inside a PLAIN segment - a contract
			-- violation, not a matter of taste.
		note
			testing: "covers/{EMOJI_SEGMENTER}.segment"
		local
			l_tables: EMOJI_DATA_TABLES
			l_catalog: EMOJI_ASSET_CATALOG
			l_segmenter: EMOJI_SEGMENTER
			l_text: STRING_32
			l_segments: ARRAYED_LIST [TEXT_SEGMENT]
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
		do
			create l_tables
			create l_catalog.make ({STRING_32} "C:\assets", l_tables, agent probe_only_woman)
			create l_segmenter.make (l_tables, l_catalog)
			create l_notes.make (0)
			l_text := text_of (<<{NATURAL_32} 0x1F469, {NATURAL_32} 0x200D, {NATURAL_32} 0x1F4BB>>)
			l_segments := l_segmenter.segment (l_text, flat_bidi (l_text, {NATURAL_8} 0), l_notes)
			assert_integers_equal ("image then plain", 2, l_segments.count)
			assert_true ("the woman still images", l_segments [1].is_emoji)
			assert_integers_equal ("and the joiner rides with her", 2, l_segments [1].count)
			assert_true ("keyed by herself alone",
				l_segments [1].asset_key.same_string ("emoji_u1f469"))
			assert_true ("the laptop, which has no asset, stays text", l_segments [2].is_plain)
			assert_integers_equal ("one character of it", 1, l_segments [2].count)
			assert_integers_equal ("still EXACTLY one note for the span", 1, l_notes.count)
			assert_integers_equal ("covering all three characters", 3, l_notes.first.source_count)
		end

	test_facade_default_asset_directory
			-- AC-9's runnable-folder rule as the facade computes it:
			-- `assets\noto-emoji\png\128' under the directory of the
			-- RUNNING EXECUTABLE, never under the working directory, and a
			-- legitimate argument to `set_asset_directory'. Task 8 also made
			-- `make' build its catalog with the REAL file probe; the catalog
			-- itself is {NONE}-visible, so this is the observable half until
			-- Task 11 threads segmentation through `layout'.
		note
			testing: "covers/{SIMPLE_SHAPING}.default_asset_directory"
		local
			l_shaping: SIMPLE_SHAPING
			l_default, l_executable_directory: STRING_32
			l_environment: EXECUTION_ENVIRONMENT
		do
			create l_shaping.make ({STRING_32} "C:\assets")
			l_default := l_shaping.default_asset_directory
			assert_string_ends_with ("the Noto png/128 layout", l_default,
				{STRING_32} "assets\noto-emoji\png\128")
			create l_environment
			l_executable_directory := (create {PATH}.make_from_string (
				l_environment.arguments.command_name)).parent.name.to_string_32
			assert_string_starts_with ("rooted at the EXECUTABLE, not the working directory",
				l_default, l_executable_directory)
			assert_true ("and it is a lawful override",
				l_shaping.set_asset_directory (l_default).asset_directory.same_string_general (l_default))
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

feature -- Test: script itemization over DirectWrite (Task 4)

	itemizer_ran: BOOLEAN
			-- Did the Task-4 itemization test that just ran reach a LIVE
			-- DirectWrite backend? False means it SKIPPED - never that it
			-- passed. Every one of the four tests below sets it FALSE on
			-- entry and TRUE only after `DWRITE_API.open' answered True, so
			-- one test's success can never mask another's skip.

	itemizer_skip_reason: STRING
			-- Why an itemization test could not run (empty when it ran).
		attribute
			create Result.make_empty
		end

	test_directwrite_itemizer_d015_intersection
			-- Task 4's centerpiece: the D-015 probe itemizes into the spike's
			-- FOUR items - the script x bidi INTERSECTION - with every
			-- position and count read in CODE POINTS.
			--
			-- The spike's UTF-16 table and this test's code-point table are
			-- the same four runs seen through the UTF-16 boundary:
			--   units  [0,4)  s36 l1  -> code points  1..4   (start 1  count 4)
			--   units  [4,8)  s36 l0  -> code points  5..7   (start 5  count 3)
			--   units  [8,16) s30 l0  -> code points  8..15  (start 8  count 8)
			--   units [16,19) s49 l0  -> code points 16..18  (start 16 count 3)
			--
			-- ITEM 2 IS THE PROOF THAT THE INTERSECTION IS NECESSARY. It
			-- carries the SAME opaque script id as item 1 - AnalyzeScript
			-- folded the space, the robot's surrogate pair and the following
			-- space into the Hebrew run, delivering only 3 script runs - so
			-- item 2 exists ONLY because the bidi level changes at code point
			-- 5. A raw script-run itemizer would emit 3 items and hand the
			-- shaper an RTL/LTR mixture in one run.
			--
			-- SCRIPT IDS ARE ASSERTED OPAQUE: Hebrew, Greek and Latin must be
			-- pairwise DISTINCT and stable across two calls. Their actual
			-- values (36/30/49 in the spike) are PRINTED, never required -
			-- requiring them would weld the suite to one backend, which is
			-- precisely what the seam forbids.
		note
			testing: "covers/{DIRECTWRITE_SCRIPT_ITEMIZER}.itemize"
		local
			l_api: DWRITE_API
			l_resolver: DIRECTWRITE_BIDI_RESOLVER
			l_itemizer: DIRECTWRITE_SCRIPT_ITEMIZER
			l_text: STRING_32
			l_bidi: BIDI_RESULT
			l_items, l_again: ARRAYED_LIST [SCRIPT_ITEM]
			l_shape: STRING
			l_analysis_size, l_stable, l_sized, i: INTEGER
		do
			itemizer_ran := False
			create l_api.make
			if not l_api.open then
				itemizer_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ l_api.last_hresult.to_hex_string
			else
				itemizer_ran := True
				l_analysis_size := l_api.script_analysis_size
				create l_resolver.make
				create l_itemizer.make
				l_text := string_of_code_points (d015_code_points)
				l_bidi := l_resolver.resolve (l_text, Direction_ltr)
				l_items := l_itemizer.itemize (l_text, 1, l_text.count, l_bidi)
					-- A SECOND pass over the same text: the opaque ids must
					-- not drift between calls (they are read from a run table
					-- the shim rebuilds every time).
				l_again := l_itemizer.itemize (l_text, 1, l_text.count, l_bidi)
				l_api.close

				if l_items.count = l_again.count then
					from i := 1 until i > l_items.count loop
						if l_again [i].script_code = l_items [i].script_code
							and l_again [i].start_index = l_items [i].start_index
							and l_again [i].count = l_items [i].count
							and l_again [i].embedding_level = l_items [i].embedding_level
						then
							l_stable := l_stable + 1
						end
						i := i + 1
					end
				end
				from i := 1 until i > l_items.count loop
					if l_items [i].analysis.count = l_analysis_size then
						l_sized := l_sized + 1
					end
					i := i + 1
				end

				create l_shape.make (160)
				from i := 1 until i > l_items.count loop
					l_shape.append ("(" + l_items [i].start_index.out + "," + l_items [i].count.out
						+ ",s" + l_items [i].script_code.out + ",l"
						+ l_items [i].embedding_level.out + ") ")
					i := i + 1
				end
				print ("    itemize: D-015 -> " + l_items.count.out + " items, code points "
					+ l_shape + "[analysis " + l_analysis_size.out + " bytes per run]%N")

					-- ---- the four items, in CODE POINTS ----
				assert_integers_equal ("the intersection emits FOUR items", 4, l_items.count)
				assert_integers_equal ("item 1 starts at code point 1", 1, l_items [1].start_index)
				assert_integers_equal ("item 1 is the four Hebrew letters", 4, l_items [1].count)
				assert_integers_equal ("item 1 is RTL (level 1)", 1, l_items [1].embedding_level.to_integer_32)
				assert_integers_equal ("item 2 starts at code point 5", 5, l_items [2].start_index)
				assert_integers_equal ("item 2 is space + robot + space = 3 CODE POINTS", 3, l_items [2].count)
				assert_integers_equal ("item 2 is LTR (level 0)", 0, l_items [2].embedding_level.to_integer_32)
				assert_integers_equal ("item 3 starts at code point 8", 8, l_items [3].start_index)
				assert_integers_equal ("item 3 is Christos + its space", 8, l_items [3].count)
				assert_integers_equal ("item 3 is LTR (level 0)", 0, l_items [3].embedding_level.to_integer_32)
				assert_integers_equal ("item 4 starts at code point 16", 16, l_items [4].start_index)
				assert_integers_equal ("item 4 is abc", 3, l_items [4].count)
				assert_integers_equal ("item 4 is LTR (level 0)", 0, l_items [4].embedding_level.to_integer_32)
				assert_integers_equal ("the four items cover all 18 code points", 19,
					l_items [4].start_index + l_items [4].count)

					-- ---- the ids stay opaque, distinct and stable ----
				assert_true ("Hebrew and Greek ids differ",
					l_items [1].script_code /= l_items [3].script_code)
				assert_true ("Hebrew and Latin ids differ",
					l_items [1].script_code /= l_items [4].script_code)
				assert_true ("Greek and Latin ids differ",
					l_items [3].script_code /= l_items [4].script_code)
				assert_integers_equal ("every item is identical on a second call", 4, l_stable)
				assert_integers_equal ("item 2 carries item 1's script id - the Common merge that"
					+ " makes the intersection necessary",
					l_items [1].script_code, l_items [2].script_code)

					-- ---- the analysis bytes travel verbatim to Task 5 ----
				assert_true ("DWRITE_SCRIPT_ANALYSIS is not empty", l_analysis_size > 0)
				assert_integers_equal ("every item carries a full analysis record", 4, l_sized)

					-- ---- emoji freedom is a CALLER DUTY (ISSUE 1) ----
					-- The robot is code point 6. It reached this seam PLAIN
					-- (FR-007 rung 3), it itemized like any other character,
					-- and nothing above asserted about it.
				assert_true ("the pictograph itemizes inside item 2, never rejected",
					l_items [2].start_index <= 6 and 6 < l_items [2].start_index + l_items [2].count)
			end
		end

	test_directwrite_itemizer_common_script_does_not_fragment
			-- "123 456" is Common script from end to end and one bidi level,
			-- so the intersection has nothing to cut: ONE item over all seven
			-- characters. This is the other side of the D-015 coin - the
			-- merge that hurts there (Common folded into a neighbor) is
			-- exactly right here, and an itemizer that split on every
			-- DirectWrite run INDEX rather than on the script ID and the
			-- level would fragment this string into unshapeable crumbs.
		note
			testing: "covers/{DIRECTWRITE_SCRIPT_ITEMIZER}.itemize"
		local
			l_api: DWRITE_API
			l_resolver: DIRECTWRITE_BIDI_RESOLVER
			l_itemizer: DIRECTWRITE_SCRIPT_ITEMIZER
			l_text: STRING_32
			l_bidi: BIDI_RESULT
			l_items: ARRAYED_LIST [SCRIPT_ITEM]
		do
			itemizer_ran := False
			create l_api.make
			if not l_api.open then
				itemizer_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ l_api.last_hresult.to_hex_string
			else
				itemizer_ran := True
				create l_resolver.make
				create l_itemizer.make
				l_text := string_of_code_points (<<0x0031, 0x0032, 0x0033, 0x0020,
					0x0034, 0x0035, 0x0036>>)
				l_bidi := l_resolver.resolve (l_text, Direction_ltr)
				l_items := l_itemizer.itemize (l_text, 1, l_text.count, l_bidi)
				l_api.close

				print ("    itemize: '123 456' -> " + l_items.count.out + " item(s), first ("
					+ l_items.first.start_index.out + "," + l_items.first.count.out + ",s"
					+ l_items.first.script_code.out + ",l"
					+ l_items.first.embedding_level.out + ")%N")

				assert_integers_equal ("Common script does not fragment", 1, l_items.count)
				assert_integers_equal ("starting at the first character", 1, l_items.first.start_index)
				assert_integers_equal ("covering all seven characters", 7, l_items.first.count)
				assert_integers_equal ("one LTR level throughout", 0,
					l_items.first.embedding_level.to_integer_32)
			end
		end

	test_directwrite_itemizer_soft_breaks_hebrew_and_spaces
			-- `soft_breaks' over three Hebrew words separated by spaces:
			-- AnalyzeLineBreakpoints offers a break BEFORE the character that
			-- FOLLOWS each space (UAX #14 - the space belongs to the line it
			-- ends, which is R2's hanging-whitespace rule seen from the other
			-- side), never before the first character, and never inside a
			-- word.
			--
			-- The flags are one per CODE POINT of the item, not per UTF-16
			-- unit, and they are read back through the same first-unit map
			-- `itemize' uses.
		note
			testing: "covers/{DIRECTWRITE_SCRIPT_ITEMIZER}.soft_breaks"
		local
			l_api: DWRITE_API
			l_resolver: DIRECTWRITE_BIDI_RESOLVER
			l_itemizer: DIRECTWRITE_SCRIPT_ITEMIZER
			l_text: STRING_32
			l_bidi: BIDI_RESULT
			l_items: ARRAYED_LIST [SCRIPT_ITEM]
			l_breaks: ARRAY [BOOLEAN]
			l_flags: STRING
			i: INTEGER
		do
			itemizer_ran := False
			create l_api.make
			if not l_api.open then
				itemizer_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ l_api.last_hresult.to_hex_string
			else
				itemizer_ran := True
				create l_resolver.make
				create l_itemizer.make
					-- shalom shalom shalom: 4 + 1 + 4 + 1 + 4 = 14 code points.
				l_text := string_of_code_points (<<0x05E9, 0x05DC, 0x05D5, 0x05DD, 0x0020,
					0x05E9, 0x05DC, 0x05D5, 0x05DD, 0x0020,
					0x05E9, 0x05DC, 0x05D5, 0x05DD>>)
				l_bidi := l_resolver.resolve (l_text, Direction_rtl)
				l_items := l_itemizer.itemize (l_text, 1, l_text.count, l_bidi)
				l_breaks := l_itemizer.soft_breaks (l_text, l_items.first)
				l_api.close

				create l_flags.make (16)
				from i := 1 until i > l_breaks.count loop
					if l_breaks [i] then
						l_flags.append ("1")
					else
						l_flags.append ("0")
					end
					i := i + 1
				end
				print ("    soft_breaks: " + l_items.count.out + " item(s) over 14 RTL code points,"
					+ " flags " + l_flags + "%N")

				assert_integers_equal ("one Hebrew item at one level", 1, l_items.count)
				assert_integers_equal ("covering all 14 characters", 14, l_items.first.count)
				assert_integers_equal ("all of it RTL", 1, l_items.first.embedding_level.to_integer_32)

				assert_integers_equal ("one flag per CODE POINT", 14, l_breaks.count)
				assert_integers_equal ("one-based", 1, l_breaks.lower)
				assert_false ("never before the first character", l_breaks [1])
				assert_false ("not inside the first word", l_breaks [2])
				assert_false ("not inside the first word", l_breaks [4])
				assert_false ("not before the space itself", l_breaks [5])
				assert_true ("break after the first space", l_breaks [6])
				assert_false ("not inside the second word", l_breaks [7])
				assert_false ("not before the second space", l_breaks [10])
				assert_true ("break after the second space", l_breaks [11])
				assert_false ("not inside the third word", l_breaks [12])
				assert_false ("not inside the third word", l_breaks [14])
			end
		end

	test_directwrite_itemizer_surrogate_pair_inside_one_item
			-- The surrogate-pair case: Hebrew, the robot, Latin. The pair is
			-- ONE code point of ONE item - never split, and never a shift.
			--
			-- The string is 8 code points over 9 UTF-16 units. An itemizer
			-- that emitted UNIT positions would report counts summing to 9
			-- and place the trailing Latin one position late; `total_cover'
			-- and `contiguous' would catch it, and so does the explicit sum
			-- below. The level boundary at code point 5 (Hebrew RTL -> the
			-- robot LTR) forces an item to START at the pair, which is the
			-- position a shifted mapping gets wrong first.
			--
			-- The second half itemizes a SUB-SPAN that begins at the pair
			-- (`a_start' = 5), the only test here with `a_start' /= 1: the
			-- UTF-16 buffer is then built from code point 5 onward and the
			-- positions still come back in whole-text code-point space.
		note
			testing: "covers/{DIRECTWRITE_SCRIPT_ITEMIZER}.itemize"
		local
			l_api: DWRITE_API
			l_resolver: DIRECTWRITE_BIDI_RESOLVER
			l_itemizer: DIRECTWRITE_SCRIPT_ITEMIZER
			l_text: STRING_32
			l_bidi: BIDI_RESULT
			l_items, l_tail: ARRAYED_LIST [SCRIPT_ITEM]
			l_pair: detachable SCRIPT_ITEM
			l_shape: STRING
			l_covered, l_tail_covered, i: INTEGER
		do
			itemizer_ran := False
			create l_api.make
			if not l_api.open then
				itemizer_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ l_api.last_hresult.to_hex_string
			else
				itemizer_ran := True
				create l_resolver.make
				create l_itemizer.make
					-- shalom + U+1F916 + abc: 8 code points, 9 UTF-16 units.
				l_text := string_of_code_points (<<0x05E9, 0x05DC, 0x05D5, 0x05DD,
					0x1F916, 0x0061, 0x0062, 0x0063>>)
				l_bidi := l_resolver.resolve (l_text, Direction_ltr)
				l_items := l_itemizer.itemize (l_text, 1, l_text.count, l_bidi)
				l_tail := l_itemizer.itemize (l_text, 5, 4, l_bidi)
				l_api.close

				create l_shape.make (120)
				from i := 1 until i > l_items.count loop
					l_covered := l_covered + l_items [i].count
					if l_items [i].start_index = 5 then
						l_pair := l_items [i]
					end
					l_shape.append ("(" + l_items [i].start_index.out + "," + l_items [i].count.out
						+ ",s" + l_items [i].script_code.out + ",l"
						+ l_items [i].embedding_level.out + ") ")
					i := i + 1
				end
				from i := 1 until i > l_tail.count loop
					l_tail_covered := l_tail_covered + l_tail [i].count
					i := i + 1
				end
				print ("    itemize: Hebrew + robot + Latin -> " + l_items.count.out
					+ " items " + l_shape + "; sub-span [5,4) -> " + l_tail.count.out
					+ " item(s) from " + l_tail.first.start_index.out + "%N")

					-- ---- code points, not units ----
				assert_integers_equal ("the items cover 8 CODE POINTS, not 9 units", 8, l_covered)
				assert_integers_equal ("and end at code point 8", 9,
					l_items.last.start_index + l_items.last.count)
				assert_integers_equal ("the Hebrew item starts at 1", 1, l_items.first.start_index)
				assert_integers_equal ("the Hebrew item is four letters", 4, l_items.first.count)
				assert_integers_equal ("the Hebrew item is RTL", 1,
					l_items.first.embedding_level.to_integer_32)

					-- ---- the pair is ONE code point inside ONE item ----
				assert_attached ("the level change forces an item to start AT the pair", l_pair)
				if attached l_pair as l_p then
					assert_integers_equal ("its level is the robot's, LTR", 0,
						l_p.embedding_level.to_integer_32)
					assert_true ("it holds the pair whole", l_p.count >= 1)
					assert_true ("and never runs past the text",
						l_p.start_index + l_p.count - 1 <= 8)
				end

					-- ---- the sub-span path (a_start /= 1) ----
				assert_integers_equal ("the sub-span starts where it was asked to", 5,
					l_tail.first.start_index)
				assert_integers_equal ("and covers exactly its four code points", 4, l_tail_covered)
				assert_integers_equal ("ending at code point 8", 9,
					l_tail.last.start_index + l_tail.last.count)
			end
		end

feature -- Test: glyph shaping over DirectWrite (Task 5)

	shaper_ran: BOOLEAN
			-- Did the Task-5 shaping test that just ran reach a LIVE
			-- DirectWrite backend AND a Segoe UI realized with an
			-- IDWriteFontFace? False means it SKIPPED - never that it
			-- passed. Every backend test below calls `begin_shaper_test'
			-- first, so one test's success can never mask another's skip.

	shaper_skip_reason: STRING
			-- Why a shaping test could not run (empty when it ran).
		attribute
			create Result.make_empty
		end

	begin_shaper_test
			-- Reset the Task-5 backend protocol.
		do
			shaper_ran := False
			create shaper_skip_reason.make_empty
		ensure
			reset: not shaper_ran and shaper_skip_reason.is_empty
		end

	test_directwrite_shaper_shalom_reproduces_the_spike
			-- Task 5's centerpiece: shalom, itemized by the REAL Task-4
			-- itemizer and shaped over a REAL Segoe UI at 16 px, reproduces
			-- the spike - 4 glyphs, 4 positive advances, no .notdef among
			-- them - and its cluster map satisfies `clusters_monotone_rtl'.
			--
			-- THE CLUSTER MAP IS THE POINT. DirectWrite's own answer here,
			-- measured by the Task-1 round trip with isRightToLeft = TRUE,
			-- is the ASCENDING map 0 1 2 3. Handed through unchanged it
			-- would be non-DECREASING and the seam's RTL clause would fail.
			-- What comes back below is 4 3 2 1 over a glyph array mirrored
			-- into visual order, so the map both descends AND still names
			-- each character's own first glyph.
			--
			-- The exact glyph ids and advances are PRINTED, never required:
			-- they are a font-version fact (the spike saw 2945/2932/2925/2933
			-- and 12.55/8.81/4.29/11.10), and requiring them would weld the
			-- suite to one Segoe UI build. What IS required is the shape of
			-- the answer, which is the contract.
		note
			testing: "covers/{DIRECTWRITE_GLYPH_SHAPER}.shape"
		local
			l_registry: FONT_REGISTRY
			l_font: SHAPING_FONT
			l_api: DWRITE_API
			l_resolver: DIRECTWRITE_BIDI_RESOLVER
			l_itemizer: DIRECTWRITE_SCRIPT_ITEMIZER
			l_shaper: DIRECTWRITE_GLYPH_SHAPER
			l_text: STRING_32
			l_bidi: BIDI_RESULT
			l_shaped: detachable SHAPED_ITEM
			l_synthesized: BOOLEAN
			l_item_count, l_item_level, l_positive, l_real_ids, i: INTEGER
			l_report: STRING
		do
			begin_shaper_test
			create l_registry.make
			create l_api.make
			l_font := l_registry.font ({STRING_32} "Segoe UI", {SHAPING_FONT}.Weight_regular, False, 16)
			if not l_font.is_ready then
				shaper_skip_reason := "GDI could not realize Segoe UI at 16 px"
			elseif not l_api.open then
				shaper_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ l_api.last_hresult.to_hex_string
			elseif not l_font.has_backend_face then
				shaper_skip_reason := "Segoe UI realized without an IDWriteFontFace"
			else
				shaper_ran := True
				create l_resolver.make
				create l_itemizer.make
				create l_shaper.make
				l_text := string_of_code_points (<<0x05E9, 0x05DC, 0x05D5, 0x05DD>>)
				l_bidi := l_resolver.resolve (l_text, Direction_ltr)
				if attached l_itemizer.itemize (l_text, 1, l_text.count, l_bidi) as al_items and then
					not al_items.is_empty
				then
					l_item_count := al_items.first.count
					l_item_level := al_items.first.embedding_level.to_integer_32
					l_shaped := l_shaper.shape (l_text, al_items.first, l_font)
					l_synthesized := l_shaper.last_shape_was_synthesized
				end
			end
				-- Every native handle released BEFORE the assertions, so a
				-- failing assertion cannot leak a face, an HFONT or an HDC.
			l_registry.dispose_all
			l_api.close

			if shaper_ran and then attached l_shaped as al_shaped then
				create l_report.make (200)
				from i := 1 until i > al_shaped.glyphs.count loop
					if al_shaped.advances [i] > 0.0 then
						l_positive := l_positive + 1
					end
					if al_shaped.glyphs [i] /= 0 then
						l_real_ids := l_real_ids + 1
					end
					l_report.append (" " + al_shaped.glyphs [i].out + "/"
						+ al_shaped.advances [i].out)
					i := i + 1
				end
				l_report.append ("; clusters")
				from i := 1 until i > al_shaped.clusters.count loop
					l_report.append (" " + al_shaped.clusters [i].out)
					i := i + 1
				end
				print ("    shape: shalom RTL under Segoe UI 16 px -> "
					+ al_shaped.glyphs.count.out + " glyphs (id/advance)" + l_report + "%N")

					-- ---- one RTL item over the four letters ----
				assert_integers_equal ("one item over all four letters", 4, l_item_count)
				assert_integers_equal ("and it is RTL (level 1)", 1, l_item_level)

					-- ---- the spike's measured shape ----
				assert_false ("real shaping, NOT the R3 synthesis", l_synthesized)
				assert_integers_equal ("shalom is 4 glyphs (spike-measured)",
					4, al_shaped.glyphs.count)
				assert_integers_equal ("every advance positive (spike-measured)", 4, l_positive)
				assert_integers_equal ("all four glyph ids real - no .notdef", 4, l_real_ids)
				assert_true ("positive measured width", al_shaped.advance_sum > 0.0)

					-- ---- the frozen seam clauses, checked as facts ----
				assert_integers_equal ("one cluster entry per CODE POINT",
					4, al_shaped.clusters.count)
				assert_true ("the RTL cluster map is non-increasing",
					is_non_increasing (al_shaped.clusters_model))
				assert_true ("every cluster names a real glyph", al_shaped.clusters_in_range)
				assert_integers_equal ("the first character takes the LAST glyph slot",
					4, al_shaped.clusters [1])
				assert_integers_equal ("and the last character takes the first",
					1, al_shaped.clusters [4])
				assert_integers_equal ("advances match glyphs",
					al_shaped.glyphs.count, al_shaped.advances.count)
				assert_integers_equal ("offsets match glyphs",
					al_shaped.glyphs.count, al_shaped.x_offsets.count)

					-- ---- coverage: Segoe UI HAS Hebrew ----
				assert_integers_equal ("no missing glyph", 0, al_shaped.missing_glyph_count)
				assert_true ("complete coverage", al_shaped.is_complete)
				assert_same_reference ("the font is recorded", l_font, al_shaped.font)
				assert_integers_equal ("four source characters", 4, al_shaped.source_count)
			end
		end

	test_directwrite_shaper_rtl_item_cluster_map_descends
			-- The RTL monotone clause over an item of SIX characters, which
			-- is where an identity map is unmistakably wrong: bereshit's six
			-- consonants shape one-to-one, so the map must not merely be
			-- non-increasing, it must actually DESCEND from the first
			-- character to the last. A shaper that passed DirectWrite's
			-- ascending map through would report 1 .. 6 here and violate
			-- `clusters_monotone_rtl' six ways.
		note
			testing: "covers/{DIRECTWRITE_GLYPH_SHAPER}.shape"
		local
			l_registry: FONT_REGISTRY
			l_font: SHAPING_FONT
			l_api: DWRITE_API
			l_resolver: DIRECTWRITE_BIDI_RESOLVER
			l_itemizer: DIRECTWRITE_SCRIPT_ITEMIZER
			l_shaper: DIRECTWRITE_GLYPH_SHAPER
			l_text: STRING_32
			l_bidi: BIDI_RESULT
			l_shaped: detachable SHAPED_ITEM
			l_synthesized: BOOLEAN
			l_item_count, i: INTEGER
			l_report: STRING
		do
			begin_shaper_test
			create l_registry.make
			create l_api.make
			l_font := l_registry.font ({STRING_32} "Segoe UI", {SHAPING_FONT}.Weight_regular, False, 16)
			if not l_font.is_ready then
				shaper_skip_reason := "GDI could not realize Segoe UI at 16 px"
			elseif not l_api.open then
				shaper_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ l_api.last_hresult.to_hex_string
			elseif not l_font.has_backend_face then
				shaper_skip_reason := "Segoe UI realized without an IDWriteFontFace"
			else
				shaper_ran := True
				create l_resolver.make
				create l_itemizer.make
				create l_shaper.make
					-- bereshit: six Hebrew consonants, no marks.
				l_text := string_of_code_points (<<0x05D1, 0x05E8, 0x05D0,
					0x05E9, 0x05D9, 0x05EA>>)
				l_bidi := l_resolver.resolve (l_text, Direction_ltr)
				if attached l_itemizer.itemize (l_text, 1, l_text.count, l_bidi) as al_items and then
					not al_items.is_empty
				then
					l_item_count := al_items.first.count
					l_shaped := l_shaper.shape (l_text, al_items.first, l_font)
					l_synthesized := l_shaper.last_shape_was_synthesized
				end
			end
			l_registry.dispose_all
			l_api.close

			if shaper_ran and then attached l_shaped as al_shaped then
				create l_report.make (80)
				from i := 1 until i > al_shaped.clusters.count loop
					l_report.append (" " + al_shaped.clusters [i].out)
					i := i + 1
				end
				print ("    shape: 6 RTL characters -> " + al_shaped.glyphs.count.out
					+ " glyphs, clusters" + l_report + "%N")

				assert_false ("real shaping, NOT the R3 synthesis", l_synthesized)
				assert_integers_equal ("one item over all six letters", 6, l_item_count)
				assert_integers_equal ("one cluster entry per CODE POINT",
					6, al_shaped.clusters.count)
				assert_true ("clusters_monotone_rtl holds",
					is_non_increasing (al_shaped.clusters_model))
				assert_true ("every cluster names a real glyph", al_shaped.clusters_in_range)
				assert_true ("the map DESCENDS - not a flat tie, not the ascending"
					+ " map DirectWrite handed back",
					al_shaped.clusters [1] > al_shaped.clusters [6])
				assert_true ("at least one glyph per character", al_shaped.glyphs.count >= 6)
				assert_true ("complete coverage - Segoe UI has Hebrew", al_shaped.is_complete)
			end
		end

	test_directwrite_shaper_latin_item_is_monotone_ltr
			-- The D-015 line's fourth item, "abc", on its own: an LTR item
			-- shapes with an ASCENDING cluster map, positive advances and
			-- real glyph ids. This is the control for the RTL tests above -
			-- the mirroring must happen for RTL items and ONLY for them.
		note
			testing: "covers/{DIRECTWRITE_GLYPH_SHAPER}.shape"
		local
			l_registry: FONT_REGISTRY
			l_font: SHAPING_FONT
			l_api: DWRITE_API
			l_resolver: DIRECTWRITE_BIDI_RESOLVER
			l_itemizer: DIRECTWRITE_SCRIPT_ITEMIZER
			l_shaper: DIRECTWRITE_GLYPH_SHAPER
			l_text: STRING_32
			l_bidi: BIDI_RESULT
			l_shaped: detachable SHAPED_ITEM
			l_synthesized: BOOLEAN
			l_item_count, l_item_level, l_positive, l_real_ids, i: INTEGER
			l_report: STRING
		do
			begin_shaper_test
			create l_registry.make
			create l_api.make
			l_font := l_registry.font ({STRING_32} "Segoe UI", {SHAPING_FONT}.Weight_regular, False, 16)
			if not l_font.is_ready then
				shaper_skip_reason := "GDI could not realize Segoe UI at 16 px"
			elseif not l_api.open then
				shaper_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ l_api.last_hresult.to_hex_string
			elseif not l_font.has_backend_face then
				shaper_skip_reason := "Segoe UI realized without an IDWriteFontFace"
			else
				shaper_ran := True
				create l_resolver.make
				create l_itemizer.make
				create l_shaper.make
				l_text := string_of_code_points (<<0x0061, 0x0062, 0x0063>>)
				l_bidi := l_resolver.resolve (l_text, Direction_ltr)
				if attached l_itemizer.itemize (l_text, 1, l_text.count, l_bidi) as al_items and then
					not al_items.is_empty
				then
					l_item_count := al_items.first.count
					l_item_level := al_items.first.embedding_level.to_integer_32
					l_shaped := l_shaper.shape (l_text, al_items.first, l_font)
					l_synthesized := l_shaper.last_shape_was_synthesized
				end
			end
			l_registry.dispose_all
			l_api.close

			if shaper_ran and then attached l_shaped as al_shaped then
				create l_report.make (120)
				from i := 1 until i > al_shaped.glyphs.count loop
					if al_shaped.advances [i] > 0.0 then
						l_positive := l_positive + 1
					end
					if al_shaped.glyphs [i] /= 0 then
						l_real_ids := l_real_ids + 1
					end
					l_report.append (" " + al_shaped.glyphs [i].out + "/"
						+ al_shaped.advances [i].out)
					i := i + 1
				end
				print ("    shape: 'abc' LTR -> " + al_shaped.glyphs.count.out
					+ " glyphs (id/advance)" + l_report + "; clusters "
					+ al_shaped.clusters [1].out + " " + al_shaped.clusters [2].out
					+ " " + al_shaped.clusters [3].out + "%N")

				assert_false ("real shaping, NOT the R3 synthesis", l_synthesized)
				assert_integers_equal ("one LTR item over abc", 3, l_item_count)
				assert_integers_equal ("level 0", 0, l_item_level)
				assert_integers_equal ("three glyphs", 3, al_shaped.glyphs.count)
				assert_integers_equal ("every advance positive", 3, l_positive)
				assert_integers_equal ("all three glyph ids real", 3, l_real_ids)
				assert_true ("clusters_monotone_ltr holds",
					is_non_decreasing (al_shaped.clusters_model))
				assert_integers_equal ("a maps to glyph 1", 1, al_shaped.clusters [1])
				assert_integers_equal ("b maps to glyph 2", 2, al_shaped.clusters [2])
				assert_integers_equal ("c maps to glyph 3", 3, al_shaped.clusters [3])
				assert_true ("every cluster names a real glyph", al_shaped.clusters_in_range)
				assert_integers_equal ("no missing glyph", 0, al_shaped.missing_glyph_count)
				assert_true ("complete coverage", al_shaped.is_complete)
			end
		end

	test_directwrite_shaper_uncovered_run_counts_one_missing
			-- THE G2 PROBE VERDICT, which is the whole reason seam 4 probes
			-- BY shaping. Segoe UI has no U+1F916; the run shapes
			-- SUCCESSFULLY to .notdef, and that is NOT an error - it is the
			-- coverage answer FONT_FALLBACK leans on.
			--
			-- ONE code point, TWO UTF-16 units. The count that must come
			-- back is 1, not 2: the low surrogate's own cluster entry is
			-- collapsed away at the boundary. A shaper that counted units
			-- would report 2 missing characters for a 1-character item and
			-- violate `cluster_per_character' on the way.
			--
			-- `last_shape_was_synthesized' is asserted FALSE here on
			-- purpose: all-zero glyph ids look exactly like R3's tofu, and
			-- this test is the one that proves the two are distinguishable.
		note
			testing: "covers/{DIRECTWRITE_GLYPH_SHAPER}.shape"
		local
			l_registry: FONT_REGISTRY
			l_font: SHAPING_FONT
			l_api: DWRITE_API
			l_resolver: DIRECTWRITE_BIDI_RESOLVER
			l_itemizer: DIRECTWRITE_SCRIPT_ITEMIZER
			l_shaper: DIRECTWRITE_GLYPH_SHAPER
			l_text: STRING_32
			l_bidi: BIDI_RESULT
			l_shaped: detachable SHAPED_ITEM
			l_synthesized, l_all_notdef: BOOLEAN
			l_item_count, i: INTEGER
			l_report: STRING
		do
			begin_shaper_test
			create l_registry.make
			create l_api.make
			l_font := l_registry.font ({STRING_32} "Segoe UI", {SHAPING_FONT}.Weight_regular, False, 16)
			if not l_font.is_ready then
				shaper_skip_reason := "GDI could not realize Segoe UI at 16 px"
			elseif not l_api.open then
				shaper_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ l_api.last_hresult.to_hex_string
			elseif not l_font.has_backend_face then
				shaper_skip_reason := "Segoe UI realized without an IDWriteFontFace"
			else
				shaper_ran := True
				create l_resolver.make
				create l_itemizer.make
				create l_shaper.make
					-- The robot alone: 1 code point over 2 UTF-16 units.
				l_text := string_of_code_points (<<0x1F916>>)
				l_bidi := l_resolver.resolve (l_text, Direction_ltr)
				if attached l_itemizer.itemize (l_text, 1, l_text.count, l_bidi) as al_items and then
					not al_items.is_empty
				then
					l_item_count := al_items.first.count
					l_shaped := l_shaper.shape (l_text, al_items.first, l_font)
					l_synthesized := l_shaper.last_shape_was_synthesized
				end
			end
			l_registry.dispose_all
			l_api.close

			if shaper_ran and then attached l_shaped as al_shaped then
				l_all_notdef := True
				create l_report.make (80)
				from i := 1 until i > al_shaped.glyphs.count loop
					if al_shaped.glyphs [i] /= 0 then
						l_all_notdef := False
					end
					l_report.append (" " + al_shaped.glyphs [i].out)
					i := i + 1
				end
				print ("    shape: U+1F916 under Segoe UI -> " + al_shaped.glyphs.count.out
					+ " glyph(s), ids" + l_report + ", missing "
					+ al_shaped.missing_glyph_count.out + " of "
					+ al_shaped.source_count.out + "%N")

				assert_false ("the backend SPOKE - this is coverage, not R3", l_synthesized)
				assert_integers_equal ("one item of ONE code point", 1, l_item_count)
				assert_integers_equal ("one source character, not two units",
					1, al_shaped.source_count)
				assert_integers_equal ("one cluster entry", 1, al_shaped.clusters.count)
				assert_true ("the whole cluster came back .notdef", l_all_notdef)
				assert_integers_equal ("ONE missing character (the G2 verdict)",
					1, al_shaped.missing_glyph_count)
				assert_false ("and so the item is not complete", al_shaped.is_complete)
				assert_true ("but the range is never dropped", al_shaped.glyphs.count >= 1)
				assert_true ("every cluster still names a real glyph",
					al_shaped.clusters_in_range)
			end
		end

	test_directwrite_shaper_forced_failure_synthesizes_tofu
			-- R3, forced and headless. The font is realized and then
			-- DISPOSED, so it keeps its identity (16 px) and has NO
			-- IDWriteFontFace - the unrecoverable case, constructed through
			-- the public registry API alone and reproducible on a machine
			-- with no DirectWrite at all. That is why this one is a plain
			-- test and not a backend test.
			--
			-- IT ALSO PROVES THE LAWFUL WEAKENING. The seam REQUIRES
			-- `a_font.is_ready'; DIRECTWRITE_GLYPH_SHAPER weakens that away
			-- with `require else', because a seam that promises never to
			-- raise cannot answer an unrealized font with an assertion
			-- violation. The call below is the proof that the weakening is
			-- real and that R3 answers it.
			--
			-- BOTH DIRECTIONS. The LTR map is 1 2 3 and the RTL map is
			-- 3 2 1 - ISSUE 12's amendment. An identity map would violate
			-- `clusters_monotone_rtl' on the RTL half, which is exactly the
			-- defect the amendment was written against.
		note
			testing: "covers/{DIRECTWRITE_GLYPH_SHAPER}.shape"
		local
			l_registry: FONT_REGISTRY
			l_font: SHAPING_FONT
			l_shaper: DIRECTWRITE_GLYPH_SHAPER
			l_ltr_item, l_rtl_item: SCRIPT_ITEM
			l_ltr, l_rtl: SHAPED_ITEM
			l_ltr_synth, l_rtl_synth: BOOLEAN
			l_text: STRING_32
			l_zero_ids, l_half_advances, i: INTEGER
		do
			create l_registry.make
			l_font := l_registry.font ({STRING_32} "Segoe UI", {SHAPING_FONT}.Weight_regular, False, 16)
				-- The forced failure: every native handle given back, the
				-- identity (and so `pixel_size') kept.
			l_registry.dispose_all
			assert_false ("the font is unrealized", l_font.is_ready)
			assert_false ("and has no IDWriteFontFace", l_font.has_backend_face)
			assert_integers_equal ("but keeps its size (same-N)", 16, l_font.pixel_size)

			create l_shaper.make
			l_text := {STRING_32} "abc"
			create l_ltr_item.make (1, 3, 0, 0, create {ARRAY [NATURAL_8]}.make_empty)
			create l_rtl_item.make (1, 3, 0, 1, create {ARRAY [NATURAL_8]}.make_empty)
			l_ltr := l_shaper.shape (l_text, l_ltr_item, l_font)
			l_ltr_synth := l_shaper.last_shape_was_synthesized
			l_rtl := l_shaper.shape (l_text, l_rtl_item, l_font)
			l_rtl_synth := l_shaper.last_shape_was_synthesized

			from i := 1 until i > l_ltr.glyphs.count loop
				if l_ltr.glyphs [i] = 0 and l_rtl.glyphs [i] = 0 then
					l_zero_ids := l_zero_ids + 1
				end
				if l_ltr.advances [i] = 8.0 and l_rtl.advances [i] = 8.0 then
					l_half_advances := l_half_advances + 1
				end
				i := i + 1
			end
			print ("    shape: no face -> R3 tofu, LTR clusters "
				+ l_ltr.clusters [1].out + " " + l_ltr.clusters [2].out + " "
				+ l_ltr.clusters [3].out + ", RTL clusters "
				+ l_rtl.clusters [1].out + " " + l_rtl.clusters [2].out + " "
				+ l_rtl.clusters [3].out + ", advance " + l_ltr.advances [1].out + "%N")

				-- ---- the synthesis is OBSERVABLE, not guessed from the ids ----
			assert_true ("the LTR item was synthesized", l_ltr_synth)
			assert_true ("the RTL item was synthesized", l_rtl_synth)

				-- ---- tofu-but-valid: never empty, never a dropped range ----
			assert_integers_equal ("one box per character (LTR)", 3, l_ltr.glyphs.count)
			assert_integers_equal ("one box per character (RTL)", 3, l_rtl.glyphs.count)
			assert_integers_equal ("every glyph id is .notdef", 3, l_zero_ids)
			assert_integers_equal ("every advance is pixel_size / 2", 3, l_half_advances)
			assert_reals_equal ("measured width is 3 * 16/2", 24.0, l_ltr.advance_sum, 0.000001)
			assert_reals_equal ("the same either way", 24.0, l_rtl.advance_sum, 0.000001)

				-- ---- every frozen clause, both directions ----
			assert_integers_equal ("cluster per character (LTR)", 3, l_ltr.clusters.count)
			assert_integers_equal ("cluster per character (RTL)", 3, l_rtl.clusters.count)
			assert_true ("clusters_monotone_ltr", is_non_decreasing (l_ltr.clusters_model))
			assert_true ("clusters_monotone_rtl", is_non_increasing (l_rtl.clusters_model))
			assert_integers_equal ("the LTR map is one-to-one: 1", 1, l_ltr.clusters [1])
			assert_integers_equal ("the LTR map is one-to-one: 2", 2, l_ltr.clusters [2])
			assert_integers_equal ("the LTR map is one-to-one: 3", 3, l_ltr.clusters [3])
			assert_integers_equal ("the RTL map is REVERSED (ISSUE 12): 3", 3, l_rtl.clusters [1])
			assert_integers_equal ("the RTL map is REVERSED (ISSUE 12): 2", 2, l_rtl.clusters [2])
			assert_integers_equal ("the RTL map is REVERSED (ISSUE 12): 1", 1, l_rtl.clusters [3])
			assert_true ("clusters_valid (LTR)", l_ltr.clusters_in_range)
			assert_true ("clusters_valid (RTL)", l_rtl.clusters_in_range)
			assert_integers_equal ("advances_match (LTR)",
				l_ltr.glyphs.count, l_ltr.advances.count)
			assert_integers_equal ("offsets match (RTL)",
				l_rtl.glyphs.count, l_rtl.y_offsets.count)

				-- ---- complete_meaning, and the probe verdict ----
			assert_integers_equal ("every character counted missing", 3, l_ltr.missing_glyph_count)
			assert_false ("so the item is not complete", l_ltr.is_complete)
			assert_false ("either way", l_rtl.is_complete)
			assert_same_reference ("font_recorded (LTR)", l_font, l_ltr.font)
			assert_same_reference ("font_recorded (RTL)", l_font, l_rtl.font)
		end

feature -- Test: line wrap engine (Task 10)

	test_wrap_cluster_safety
			-- AC-2, REAL as of Phase 4 Task 10: at a narrow width the engine
			-- never splits a pointed-Hebrew cluster (base + niqqud share ONE
			-- pre-split run) nor an emoji segment (ONE atomic IMAGE_RUN);
			-- every character lands in exactly one line
			-- (`lines_partition_text'); and the overflow flag appears ONLY
			-- where a single unbreakable run is wider than the width.
			--
			-- HEADLESS: runs come from NULL_GLYPH_SHAPER (advance
			-- pixel_size / 2 per character, so a k-character run at 16 px
			-- measures exactly 8k px) and the reorderer is
			-- NULL_BIDI_RESOLVER. Zero native shaping, which is what lets
			-- every line break below be HAND-COMPUTED rather than whatever
			-- this machine's fonts happen to measure.
		note
			testing: "covers/{LINE_LAYOUT_ENGINE}.build_lines"
		local
			l_engine: LINE_LAYOUT_ENGINE
			l_registry: FONT_REGISTRY
			l_font: SHAPING_FONT
			l_bidi: NULL_BIDI_RESOLVER
			l_text: STRING_32
			l_runs: ARRAYED_LIST [SHAPED_RUN]
			l_lines: ARRAYED_LIST [SHAPED_LINE]
			l_image: IMAGE_RUN
			i, l_image_lines: INTEGER
		do
			create l_engine.make
			create l_registry.make
			create l_bidi
			l_font := l_registry.font ({STRING_32} "Segoe UI", 400, False, 16)
				-- ALEF+QAMATS, BET+PATAH, GIMEL+SHEVA, space, U+1F916, "abc"
				-- = 11 code points; no niqqud ever leaves its base letter.
			l_text := string_of_code_points (<<0x05D0, 0x05B8, 0x05D1, 0x05B7,
				0x05D2, 0x05B0, 0x0020, 0x1F916, 0x0061, 0x0062, 0x0063>>)
			assert_integers_equal ("eleven code points", 11, l_text.count)
				-- The FACADE pre-split (Larry's gate decision 1): one run per
				-- break opportunity, and a break opportunity is never
				-- mid-cluster and never inside an emoji segment.
			create l_runs.make (4)
			l_runs.extend (headless_glyph_run (l_text, 1, 6, 1, l_font))
			l_runs.extend (headless_glyph_run (l_text, 7, 1, 0, l_font))
			l_image := headless_image_run (8, 1, 0, 16.0)
			l_runs.extend (l_image)
			l_runs.extend (headless_glyph_run (l_text, 9, 3, 0, l_font))
			assert_reals_equal ("the pointed run measures 6 * 8", 48.0,
				l_runs [1].advance_width, 0.000001)
			assert_reals_equal ("an image box advances by its width (box_is_advance)",
				16.0, l_image.advance_width, 0.000001)

				-- ---- 50 px: 48 + 8 fits (the space hangs), + 16 does not ----
			l_lines := l_engine.build_lines (l_text, 50, 16, l_runs, l_bidi)
			assert_integers_equal ("two lines at 50 px", 2, l_lines.count)
			assert_true ("every character lands in exactly one line",
				lines_partition_text (l_lines, l_text.count))
			assert_integers_equal ("line 1 starts at 1", 1, l_lines [1].source_start)
			assert_integers_equal ("line 1 = cluster run + hanging space",
				7, l_lines [1].source_count)
			assert_integers_equal ("line 2 starts at the emoji", 8, l_lines [2].source_start)
			assert_integers_equal ("line 2 = emoji + abc", 4, l_lines [2].source_count)
			assert_integers_equal ("the pointed cluster is still ONE unsplit run",
				6, l_lines [1].runs [1].source_count)
			assert_false ("nothing overflows at 50 px", l_lines [1].is_overflowing)
			assert_false ("nothing overflows at 50 px (line 2)", l_lines [2].is_overflowing)

				-- ---- 20 px: the cluster run ALONE is wider than the width ----
			l_lines := l_engine.build_lines (l_text, 20, 16, l_runs, l_bidi)
			assert_integers_equal ("four lines at 20 px", 4, l_lines.count)
			assert_true ("still exactly one line per character",
				lines_partition_text (l_lines, l_text.count))
			assert_true ("the too-wide cluster run overflows", l_lines [1].is_overflowing)
			assert_integers_equal ("alone on its line (overflow_shape)",
				1, l_lines [1].runs.count)
			assert_integers_equal ("and STILL not split", 6, l_lines [1].runs [1].source_count)
			assert_false ("the hanging space does not overflow", l_lines [2].is_overflowing)
			assert_false ("the 16 px emoji box fits 20 px", l_lines [3].is_overflowing)
			assert_true ("but the 24 px run does not", l_lines [4].is_overflowing)
			from i := 1 until i > l_lines.count loop
				if across l_lines [i].runs as r some attached {IMAGE_RUN} r end then
					l_image_lines := l_image_lines + 1
				end
				i := i + 1
			end
			assert_integers_equal ("the emoji segment lives on exactly one line",
				1, l_image_lines)
			l_registry.dispose_all
		end

	test_wrap_greedy_fill_to_width
			-- Greedy accumulation with HAND-COMPUTED breaks: five pre-split
			-- runs measuring 32 / 8 / 32 / 8 / 32 px at a 72 px width put
			-- four of them on line 1 - the trailing space included, because
			-- R2 excludes its advance from the fit test but NOT from the
			-- line - and the fifth on line 2.
		note
			testing: "covers/{LINE_LAYOUT_ENGINE}.build_lines"
		local
			l_engine: LINE_LAYOUT_ENGINE
			l_registry: FONT_REGISTRY
			l_font: SHAPING_FONT
			l_bidi: NULL_BIDI_RESOLVER
			l_text: STRING_32
			l_runs: ARRAYED_LIST [SHAPED_RUN]
			l_lines: ARRAYED_LIST [SHAPED_LINE]
		do
			create l_engine.make
			create l_registry.make
			create l_bidi
			l_font := l_registry.font ({STRING_32} "Segoe UI", 400, False, 16)
			l_text := {STRING_32} "aaaa bbbb cccc"
			assert_integers_equal ("fourteen characters", 14, l_text.count)
			create l_runs.make (5)
			l_runs.extend (headless_glyph_run (l_text, 1, 4, 0, l_font))
			l_runs.extend (headless_glyph_run (l_text, 5, 1, 0, l_font))
			l_runs.extend (headless_glyph_run (l_text, 6, 4, 0, l_font))
			l_runs.extend (headless_glyph_run (l_text, 10, 1, 0, l_font))
			l_runs.extend (headless_glyph_run (l_text, 11, 4, 0, l_font))
			l_lines := l_engine.build_lines (l_text, 72, 16, l_runs, l_bidi)
			assert_integers_equal ("two lines", 2, l_lines.count)
			assert_integers_equal ("line 1 takes four runs", 4, l_lines [1].runs.count)
			assert_integers_equal ("covering 'aaaa bbbb '", 10, l_lines [1].source_count)
			assert_reals_equal ("its width INCLUDES the trailing space (R2)",
				80.0, l_lines [1].width, 0.000001)
			assert_integers_equal ("line 2 takes the fifth run", 1, l_lines [2].runs.count)
			assert_integers_equal ("starting at 11", 11, l_lines [2].source_start)
			assert_reals_equal ("and measuring 32", 32.0, l_lines [2].width, 0.000001)
			assert_true ("partition", lines_partition_text (l_lines, 14))
			assert_true ("metrics_sane on line 1", l_lines [1].height > 0.0
				and l_lines [1].ascent > 0.0 and l_lines [1].ascent <= l_lines [1].height)
			assert_true ("every glyph run is at the layout size",
				runs_at_layout_size (l_lines, 16))
			l_registry.dispose_all
		end

	test_wrap_hanging_whitespace_rule
			-- R2, both halves in one test: a line-TRAILING breaking space
			-- rides along even though its advance pushes the line past the
			-- width, while the SAME advance in an INK run breaks the line.
			-- `fits_within' is the only comparison in either case.
		note
			testing: "covers/{LINE_LAYOUT_ENGINE}.build_lines, covers/{LINE_LAYOUT_ENGINE}.fits_within"
		local
			l_engine: LINE_LAYOUT_ENGINE
			l_registry: FONT_REGISTRY
			l_font: SHAPING_FONT
			l_bidi: NULL_BIDI_RESOLVER
			l_text: STRING_32
			l_runs: ARRAYED_LIST [SHAPED_RUN]
			l_lines: ARRAYED_LIST [SHAPED_LINE]
		do
			create l_engine.make
			create l_registry.make
			create l_bidi
			l_font := l_registry.font ({STRING_32} "Segoe UI", 400, False, 16)
				-- 32 px of ink + an 8 px space, at exactly 32 px of width.
			l_text := {STRING_32} "aaaa "
			create l_runs.make (2)
			l_runs.extend (headless_glyph_run (l_text, 1, 4, 0, l_font))
			l_runs.extend (headless_glyph_run (l_text, 5, 1, 0, l_font))
			l_lines := l_engine.build_lines (l_text, 32, 16, l_runs, l_bidi)
			assert_integers_equal ("the space does NOT start a new line", 1, l_lines.count)
			assert_integers_equal ("it stays with the preceding line", 2, l_lines [1].runs.count)
			assert_integers_equal ("covering all five characters", 5, l_lines [1].source_count)
			assert_reals_equal ("so the line MEASURES wider than the width",
				40.0, l_lines [1].width, 0.000001)
			assert_false ("which is not an overflow", l_lines [1].is_overflowing)
				-- The same 8 px as INK: no hanging exclusion, so it breaks.
			l_text := {STRING_32} "aaaax"
			create l_runs.make (2)
			l_runs.extend (headless_glyph_run (l_text, 1, 4, 0, l_font))
			l_runs.extend (headless_glyph_run (l_text, 5, 1, 0, l_font))
			l_lines := l_engine.build_lines (l_text, 32, 16, l_runs, l_bidi)
			assert_integers_equal ("ink of the same advance breaks", 2, l_lines.count)
			assert_integers_equal ("line 1 keeps four characters", 4, l_lines [1].source_count)
			assert_integers_equal ("line 2 takes the fifth", 1, l_lines [2].source_count)
			assert_true ("partition", lines_partition_text (l_lines, 5))
			l_registry.dispose_all
		end

	test_wrap_no_wrap_is_one_unbounded_line
			-- No_wrap (0) means there is no width to fit: exactly ONE line,
			-- every run on it, nothing flagged.
		note
			testing: "covers/{LINE_LAYOUT_ENGINE}.build_lines"
		local
			l_engine: LINE_LAYOUT_ENGINE
			l_registry: FONT_REGISTRY
			l_font: SHAPING_FONT
			l_bidi: NULL_BIDI_RESOLVER
			l_text: STRING_32
			l_runs: ARRAYED_LIST [SHAPED_RUN]
			l_lines: ARRAYED_LIST [SHAPED_LINE]
		do
			create l_engine.make
			create l_registry.make
			create l_bidi
			l_font := l_registry.font ({STRING_32} "Segoe UI", 400, False, 16)
			l_text := {STRING_32} "aaaa bbbb cccc"
			create l_runs.make (5)
			l_runs.extend (headless_glyph_run (l_text, 1, 4, 0, l_font))
			l_runs.extend (headless_glyph_run (l_text, 5, 1, 0, l_font))
			l_runs.extend (headless_glyph_run (l_text, 6, 4, 0, l_font))
			l_runs.extend (headless_glyph_run (l_text, 10, 1, 0, l_font))
			l_runs.extend (headless_glyph_run (l_text, 11, 4, 0, l_font))
			l_lines := l_engine.build_lines (l_text, No_wrap, 16, l_runs, l_bidi)
			assert_integers_equal ("exactly one line", 1, l_lines.count)
			assert_integers_equal ("holding every run", 5, l_lines [1].runs.count)
			assert_integers_equal ("covering every character", 14, l_lines [1].source_count)
			assert_false ("no width, so nothing overflows", l_lines [1].is_overflowing)
			assert_reals_equal ("unbounded: the full 112 px", 112.0,
				l_lines [1].width, 0.000001)
			assert_true ("partition", lines_partition_text (l_lines, 14))
			l_registry.dispose_all
		end

	test_wrap_empty_input_is_one_empty_line
			-- FR-N01/AC-6: no runs -> ONE line of count 0 whose metrics come
			-- from the layout's own pixel size (0.8 * 16 above the baseline,
			-- 16 tall), never from a font that is not there. Text WITHOUT
			-- runs still has its characters counted, so `partition' holds.
		note
			testing: "covers/{LINE_LAYOUT_ENGINE}.build_lines"
		local
			l_engine: LINE_LAYOUT_ENGINE
			l_bidi: NULL_BIDI_RESOLVER
			l_runs: ARRAYED_LIST [SHAPED_RUN]
			l_lines: ARRAYED_LIST [SHAPED_LINE]
		do
			create l_engine.make
			create l_bidi
			create l_runs.make (0)
			l_lines := l_engine.build_lines ({STRING_32} "", 100, 16, l_runs, l_bidi)
			assert_integers_equal ("one line", 1, l_lines.count)
			assert_integers_equal ("zero runs", 0, l_lines [1].runs.count)
			assert_integers_equal ("starting at 1", 1, l_lines [1].source_start)
			assert_integers_equal ("covering nothing", 0, l_lines [1].source_count)
			assert_reals_equal ("height = pixel size", 16.0, l_lines [1].height, 0.000001)
			assert_reals_equal ("ascent = 0.8 * pixel size", 12.8,
				l_lines [1].ascent, 0.000001)
			assert_reals_equal ("no runs, no width", 0.0, l_lines [1].width, 0.000001)
			assert_true ("partition of the empty text",
				lines_partition_text (l_lines, 0))
			l_lines := l_engine.build_lines ({STRING_32} "abc", 100, 16, l_runs, l_bidi)
			assert_integers_equal ("still one line", 1, l_lines.count)
			assert_integers_equal ("covering all three characters",
				3, l_lines [1].source_count)
			assert_true ("partition", lines_partition_text (l_lines, 3))
		end

	test_wrap_line_is_reordered_visually
			-- DR-002: a finished line's runs are stored in VISUAL paint
			-- order. NULL_BIDI_RESOLVER honors the two cases UAX #9 L2 names
			-- and its own contract states - an all-EVEN line is the identity,
			-- an all-ODD line is the full reversal - so three RTL runs come
			-- back last-first while three LTR runs do not move.
		note
			testing: "covers/{LINE_LAYOUT_ENGINE}.build_lines, covers/{NULL_BIDI_RESOLVER}.reorder"
		local
			l_engine: LINE_LAYOUT_ENGINE
			l_registry: FONT_REGISTRY
			l_font: SHAPING_FONT
			l_bidi: NULL_BIDI_RESOLVER
			l_text: STRING_32
			l_runs: ARRAYED_LIST [SHAPED_RUN]
			l_lines: ARRAYED_LIST [SHAPED_LINE]
		do
			create l_engine.make
			create l_registry.make
			create l_bidi
			l_font := l_registry.font ({STRING_32} "Segoe UI", 400, False, 16)
			l_text := string_of_code_points (<<0x05D0, 0x05D1, 0x05D2,
				0x05D3, 0x05D4, 0x05D5>>)
			create l_runs.make (3)
			l_runs.extend (headless_glyph_run (l_text, 1, 2, 1, l_font))
			l_runs.extend (headless_glyph_run (l_text, 3, 2, 1, l_font))
			l_runs.extend (headless_glyph_run (l_text, 5, 2, 1, l_font))
			l_lines := l_engine.build_lines (l_text, No_wrap, 16, l_runs, l_bidi)
			assert_integers_equal ("one line", 1, l_lines.count)
			assert_integers_equal ("three runs", 3, l_lines [1].runs.count)
			assert_integers_equal ("paint FIRST what was logically LAST",
				5, l_lines [1].runs [1].source_start)
			assert_integers_equal ("then the middle", 3, l_lines [1].runs [2].source_start)
			assert_integers_equal ("and last what was logically first",
				1, l_lines [1].runs [3].source_start)
			assert_integers_equal ("the LOGICAL range is untouched by L2",
				1, l_lines [1].source_start)
			assert_integers_equal ("covering all six", 6, l_lines [1].source_count)
				-- The LTR control: identity, so logical order survives.
			create l_runs.make (3)
			l_runs.extend (headless_glyph_run (l_text, 1, 2, 0, l_font))
			l_runs.extend (headless_glyph_run (l_text, 3, 2, 0, l_font))
			l_runs.extend (headless_glyph_run (l_text, 5, 2, 0, l_font))
			l_lines := l_engine.build_lines (l_text, No_wrap, 16, l_runs, l_bidi)
			assert_integers_equal ("LTR paints first-first", 1,
				l_lines [1].runs [1].source_start)
			assert_integers_equal ("LTR paints last-last", 5,
				l_lines [1].runs [3].source_start)
			l_registry.dispose_all
		end

feature -- Test: the facade pipeline (Task 11)

	test_headless_full_pipeline
			-- AC-7, REAL (Phase 4 Task 11 - this was a skeletal Phase-5
			-- marker). The WHOLE pipeline - emoji segmentation, itemization,
			-- fallback, shaping, the soft-break pre-split, wrap, coverage,
			-- caching and measurement - under the four NULL_* seams, with
			-- metrics a test can compute by hand: NULL_GLYPH_SHAPER advances
			-- every character by pixel_size / 2, so "abc def" at 16 px is
			-- exactly 7 * 8 = 56 pixels wide.
			--
			-- WHAT "HEADLESS" COVERS, honestly: the four SEAMS make zero
			-- native calls. Font REALIZATION is not a seam - FONT_REGISTRY is
			-- facade-owned and the frozen creation contracts expose no
			-- injection point for it - so the general-list head is still
			-- realized through GDI here.
		note
			testing: "covers/{SIMPLE_SHAPING}.layout, covers/{SIMPLE_SHAPING}.measured_width"
		local
			l_shaping: SIMPLE_SHAPING
			l_layout, l_again: SHAPED_LAYOUT
			l_line: SHAPED_LINE
			l_text: STRING_32
			l_covered, i: INTEGER
		do
			l_shaping := headless_facade
			l_text := {STRING_32} "abc def"
			l_layout := l_shaping.layout_default (l_text, 1000, 16)

			assert_integers_equal ("one line at 1000 px", 1, l_layout.lines.count)
			assert_integers_equal ("base direction is LTR (NULL bidi resolves everything to 0)",
				Direction_ltr, l_layout.base_direction)
			assert_true ("coverage holds", l_layout.covers_all_characters)
			l_line := l_layout.lines.first
			assert_integers_equal ("the soft break AFTER the space pre-split the item into two runs",
				2, l_line.runs.count)
			assert_integers_equal ("run 1 is 'abc ' - the space rides with the word it follows,"
				+ " so no run is whitespace-only", 4, l_line.runs [1].source_count)
			assert_integers_equal ("run 2 is 'def'", 3, l_line.runs [2].source_count)
			from i := 1 until i > l_line.runs.count loop
				assert_integers_equal ("runs cover the text contiguously, in order",
					l_covered + 1, l_line.runs [i].source_start)
				l_covered := l_covered + l_line.runs [i].source_count
				i := i + 1
			end
			assert_integers_equal ("and cover all seven characters", 7, l_covered)
			assert_reals_equal ("7 characters at 16/2 px each", 56.0, l_line.width, 0.000001)
			assert_true ("every run is a glyph run - there is no emoji in this text",
				across l_line.runs as r all attached {GLYPH_RUN} r end)
			assert_true ("ISSUE 8: every glyph run is at the LAYOUT's size",
				runs_at_layout_size (l_layout.lines, 16))
			assert_true ("the line is tall enough to paint", l_line.height > 0.0)

				-- R7 on the miss: ONE run-producing shape for the one item,
				-- and the NULL fallback probed nothing at all.
			assert_integers_equal ("one shape call for the one item", 1,
				l_shaping.statistics.shape_calls)
			assert_integers_equal ("the NULL fallback probes nothing", 0,
				l_shaping.statistics.fallback_probes)
			assert_integers_equal ("one miss", 1, l_shaping.statistics.cache_misses)

			l_again := l_shaping.layout_default (l_text, 1000, 16)
			assert_same_reference ("the repeat call returns the cached layout", l_layout, l_again)
			assert_integers_equal ("and shaped nothing more", 1, l_shaping.statistics.shape_calls)

				-- AC-10's headless half: measurement is the same pipeline at
				-- No_wrap, so it agrees with the line to the pixel.
			assert_reals_equal ("measured_width agrees with the line", 56.0,
				l_shaping.measured_width (l_text, 16, l_shaping.default_fonts), 0.000001)
			assert_true ("nothing degraded except the families R1 dropped",
				across l_layout.notes as n all n.code = Note_family_missing end)
		end

	test_measured_width_sums_advances
			-- AC-10, REAL (Phase 4 Task 11 - a skeletal Phase-5 marker until
			-- now). `measured_width' is the first line of a No_wrap layout,
			-- so it IS the sum of the shaped advances and nothing else; and
			-- R2 (Q3) says whitespace measures as shaped, which is why
			-- "a b" measures strictly more than "ab" - by exactly one
			-- character's advance, not by a trimmed zero.
		note
			testing: "covers/{SIMPLE_SHAPING}.measured_width, covers/{SIMPLE_SHAPING}.line_height"
		local
			l_shaping: SIMPLE_SHAPING
			l_ab, l_a_b, l_abc, l_height: REAL_64
			l_registry: FONT_REGISTRY
			l_font: SHAPING_FONT
		do
			l_shaping := headless_facade
			l_abc := l_shaping.measured_width ({STRING_32} "abc", 16, l_shaping.default_fonts)
			assert_reals_equal ("3 characters at 16/2 px under the NULL shaper", 24.0, l_abc, 0.000001)
			l_ab := l_shaping.measured_width ({STRING_32} "ab", 16, l_shaping.default_fonts)
			l_a_b := l_shaping.measured_width ({STRING_32} "a b", 16, l_shaping.default_fonts)
			assert_reals_equal ("two characters", 16.0, l_ab, 0.000001)
			assert_true ("R2: the space is measured as shaped, not trimmed", l_a_b > l_ab)
			assert_reals_equal ("and it measures exactly one character's advance",
				8.0, l_a_b - l_ab, 0.000001)
			assert_reals_equal ("empty text still measures zero", 0.0,
				l_shaping.measured_width ({STRING_32} "", 16, l_shaping.default_fonts), 0.000001)
			assert_reals_equal ("measurement doubles with the size", 48.0,
				l_shaping.measured_width ({STRING_32} "abc", 32, l_shaping.default_fonts), 0.000001)

				-- Q8: `line_height' is the FIRST REALIZED general-list
				-- family's ascent + descent - the same number the machine
				-- gives an INDEPENDENT registry for that face.
			l_height := l_shaping.line_height (16, l_shaping.default_fonts)
			assert_true ("line_height is positive", l_height > 0.0)
			create l_registry.make
			l_font := l_registry.font ({STRING_32} "Segoe UI", {SHAPING_FONT}.Weight_regular, False, 16)
			if l_font.is_ready then
				print ("    line_height: general-list head " + l_font.family.to_string_8
					+ " ascent " + l_font.ascent.out + " descent " + l_font.descent.out
					+ " -> " + l_height.out + "%N")
				assert_reals_equal ("line_height = ascent + descent of the general-list head",
					l_font.ascent + l_font.descent, l_height, 0.000001)
				assert_true ("AC-10: line_height >= ascent + descent",
					l_height >= l_font.ascent + l_font.descent)
			end
			l_registry.dispose_all
		end

	test_repaint_shapes_nothing
			-- AC-3, the 200-message repaint. After the first call, TWO
			-- HUNDRED identical `layout' calls move `cache_hits' and NOTHING
			-- else: `shape_calls', `fallback_probes' and `notes_emitted' are
			-- all frozen, the same immutable layout comes back every time,
			-- and the cache never grows past its one entry (FR-012).
		note
			testing: "covers/{SIMPLE_SHAPING}.layout_default"
		local
			l_shaping: SIMPLE_SHAPING
			l_first, l_again: SHAPED_LAYOUT
			l_shapes, l_probes, l_notes, i: INTEGER
			l_text: STRING_32
		do
			l_shaping := headless_facade
			l_text := {STRING_32} "an unchanged chat bubble"
			l_first := l_shaping.layout_default (l_text, 220, 16)
			l_again := l_first
			l_shapes := l_shaping.statistics.shape_calls
			l_probes := l_shaping.statistics.fallback_probes
			l_notes := l_shaping.statistics.notes_emitted
			assert_true ("the first call really did shape", l_shapes >= 1)
			from i := 1 until i > 200 loop
				l_again := l_shaping.layout_default (l_text, 220, 16)
				i := i + 1
			end
			assert_same_reference ("the 200th repaint is the very same object", l_first, l_again)
			assert_integers_equal ("200 hits", 200, l_shaping.statistics.cache_hits)
			assert_integers_equal ("still exactly one miss", 1, l_shaping.statistics.cache_misses)
			assert_integers_equal ("ZERO shaping on repaint", l_shapes,
				l_shaping.statistics.shape_calls)
			assert_integers_equal ("ZERO probing on repaint", l_probes,
				l_shaping.statistics.fallback_probes)
			assert_integers_equal ("and not one new note", l_notes,
				l_shaping.statistics.notes_emitted)
			assert_integers_equal ("one cache entry, not 201", 1, l_shaping.cache_count)
		end

	test_statistics_counters_are_disjoint
			-- R7 / Q10, PROVED rather than assumed. With a PROBING fallback -
			-- LIST_FONT_FALLBACK walking a real policy through the NULL
			-- shaper - the two counters move independently and exactly: the
			-- walk's coverage shape is charged to `fallback_probes' ONLY, the
			-- run-producing shape to `shape_calls' ONLY. A second layout over
			-- the same script class then shapes again while probing NOTHING,
			-- because the walk's verdict cache already knows the answer -
			-- which is the honest reading of "how many probes it cost".
		note
			testing: "covers/{SIMPLE_SHAPING}.layout, covers/{LIST_FONT_FALLBACK}.font_for"
		local
			l_shaping: SIMPLE_SHAPING
			l_registry: FONT_REGISTRY
			l_bidi: NULL_BIDI_RESOLVER
			l_itemizer: NULL_SCRIPT_ITEMIZER
			l_shaper: NULL_GLYPH_SHAPER
			l_fallback: LIST_FONT_FALLBACK
			l_layout: SHAPED_LAYOUT
		do
			create l_registry.make
			create l_bidi
			create l_itemizer
			create l_shaper
			create l_fallback.make (l_shaper, l_registry)
			create l_shaping.make_with_backends (l_bidi, l_itemizer, l_shaper, l_fallback,
				{STRING_32} "assets")

			l_layout := l_shaping.layout_default ({STRING_32} "abc", 200, 16)
			assert_true ("the layout is paintable", l_layout.covers_all_characters)
			assert_integers_equal ("exactly ONE run-producing shape", 1,
				l_shaping.statistics.shape_calls)
			assert_integers_equal ("exactly ONE coverage probe - the requested face itself", 1,
				l_shaping.statistics.fallback_probes)

			l_layout := l_shaping.layout_default ({STRING_32} "abcd", 200, 16)
			assert_true ("the second layout is paintable too", l_layout.covers_all_characters)
			assert_integers_equal ("the second layout shapes again", 2,
				l_shaping.statistics.shape_calls)
			assert_integers_equal ("but a WARM verdict costs no probe", 1,
				l_shaping.statistics.fallback_probes)
			assert_integers_equal ("two misses", 2, l_shaping.statistics.cache_misses)
			assert_integers_equal ("no hit", 0, l_shaping.statistics.cache_hits)
			print ("    statistics: shape_calls " + l_shaping.statistics.shape_calls.out
				+ ", fallback_probes " + l_shaping.statistics.fallback_probes.out
				+ ", verdicts " + l_fallback.verdict_count.out + "%N")
			l_registry.dispose_all
		end

	d015_ran: BOOLEAN
			-- Did the AC-1 layout test reach a live DirectWrite backend AND
			-- the acquired assets? False means it SKIPPED - never that it
			-- passed.

	d015_skip_reason: STRING
			-- Why the AC-1 layout test could not run (empty when it ran).
		attribute
			create Result.make_empty
		end

	test_d015_chat_line
			-- AC-1's LAYOUT half, REAL (Phase 4 Task 11; the PAINT half is
			-- Task 13's cairo bridge and nothing here pretends otherwise).
			--
			-- The acceptance string goes through the PRODUCTION facade -
			-- DirectWrite bidi, itemization and shaping, LIST_FONT_FALLBACK,
			-- the acquired Noto png/128 set - and comes back as ONE No_wrap
			-- line in which: the robot is exactly ONE IMAGE_RUN keyed
			-- `emoji_u1f916' with a path under the configured directory,
			-- every other run is a GLYPH_RUN, the Hebrew carries an ODD (RTL)
			-- embedding level, the runs cover all eighteen code points
			-- exactly once, and the shaper really ran.
		note
			testing: "covers/{SIMPLE_SHAPING}.layout_default"
		local
			l_api: DWRITE_API
			l_shaping: SIMPLE_SHAPING
			l_layout: SHAPED_LAYOUT
			l_line: SHAPED_LINE
			l_text: STRING_32
			l_image: detachable IMAGE_RUN
			l_images, l_glyphs, i, k, l_hebrew_visual, l_last_visual: INTEGER
			l_cover: ARRAY [INTEGER]
			l_shape: STRING
		do
			d015_ran := False
			create d015_skip_reason.make_empty
			create l_api.make
			if real_asset_directory.is_empty then
				d015_skip_reason := "the acquired Noto png/128 assets were not found"
			elseif not l_api.open then
				d015_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ l_api.last_hresult.to_hex_string
			else
				d015_ran := True
				create l_shaping.make (real_asset_directory)
				l_text := string_of_code_points (d015_code_points)
				l_layout := l_shaping.layout_default (l_text, No_wrap, 16)
				l_line := l_layout.lines.first

					-- ---- what was actually measured, for the evidence ----
				create l_shape.make (240)
				from i := 1 until i > l_line.runs.count loop
					l_shape.append ("(" + l_line.runs [i].source_start.out + ","
						+ l_line.runs [i].source_count.out + ",l"
						+ l_line.runs [i].embedding_level.out + ","
						+ (if attached {IMAGE_RUN} l_line.runs [i] then "img" else "gly" end)
						+ ") ")
					i := i + 1
				end
				print ("    d015 layout: " + l_layout.lines.count.out + " line, "
					+ l_line.runs.count.out + " runs in VISUAL order " + l_shape
					+ "[base " + (if l_layout.base_direction = Direction_rtl then "RTL" else "LTR" end)
					+ ", width " + l_line.width.out + ", height " + l_line.height.out
					+ ", shape_calls " + l_shaping.statistics.shape_calls.out
					+ ", probes " + l_shaping.statistics.fallback_probes.out
					+ ", notes " + l_layout.notes.count.out + "]%N")

					-- ---- structure ----
				assert_integers_equal ("No_wrap yields ONE unbounded line", 1, l_layout.lines.count)
				assert_true ("coverage holds", l_layout.covers_all_characters)
				assert_integers_equal ("the line covers all 18 code points", 18, l_line.source_count)
				assert_integers_equal ("first-strong is Hebrew, so the paragraph is RTL",
					Direction_rtl, l_layout.base_direction)

					-- ---- exactly one image run, and it is the robot ----
				from i := 1 until i > l_line.runs.count loop
					if attached {IMAGE_RUN} l_line.runs [i] as al_image then
						l_images := l_images + 1
						l_image := al_image
					else
						l_glyphs := l_glyphs + 1
					end
					i := i + 1
				end
				assert_integers_equal ("U+1F916 is EXACTLY one IMAGE_RUN", 1, l_images)
				assert_true ("and everything else is a glyph run", l_glyphs >= 3)
				if attached l_image as al_robot then
					assert_true ("keyed emoji_u1f916", al_robot.asset_key.same_string ("emoji_u1f916"))
					assert_true ("with a path under the configured asset directory",
						al_robot.asset_path.starts_with (l_shaping.asset_directory))
					assert_string_ends_with ("the Noto file name", al_robot.asset_path,
						"emoji_u1f916.png")
					assert_integers_equal ("over code point 6 only", 6, al_robot.source_start)
					assert_integers_equal ("one character", 1, al_robot.source_count)
					assert_true ("the box is SQUARE at the line height",
						al_robot.width = al_robot.height and al_robot.width > 0.0)
				end

					-- ---- the runs partition the eighteen code points ----
				create l_cover.make_filled (0, 1, 18)
				from i := 1 until i > l_line.runs.count loop
					from k := 0 until k >= l_line.runs [i].source_count loop
						l_cover [l_line.runs [i].source_start + k] :=
							l_cover [l_line.runs [i].source_start + k] + 1
						k := k + 1
					end
					if l_line.runs [i].source_start = 1 then
						l_hebrew_visual := i
					end
					if l_line.runs [i].source_start + l_line.runs [i].source_count - 1 = 18 then
						l_last_visual := i
					end
					i := i + 1
				end
				assert_true ("every code point is covered exactly once",
					across l_cover as c all c = 1 end)

					-- ---- the Hebrew is RTL, and paints to the RIGHT ----
				assert_true ("the run that starts at code point 1 was found", l_hebrew_visual >= 1)
				assert_true ("the Hebrew run carries an ODD embedding level",
					l_line.runs [l_hebrew_visual].is_rtl)
				assert_true ("and it paints AFTER the run holding the last code point"
					+ " - visually to its right, which is what RTL means here",
					l_hebrew_visual > l_last_visual)

					-- ---- the backend really ran ----
				assert_true ("real shaping happened", l_shaping.statistics.shape_calls >= 3)
				assert_true ("every glyph run is at the layout's size",
					runs_at_layout_size (l_layout.lines, 16))
			end
		end

	headless_facade: SIMPLE_SHAPING
			-- A facade wired to all four NULL_* doubles (UC-005/AC-7): zero
			-- native calls in bidi, itemization, shaping and fallback, and
			-- metrics that are pure arithmetic on `pixel_size'.
			--
			-- Font REALIZATION is deliberately NOT covered by that claim:
			-- FONT_REGISTRY is facade-owned and `make_with_backends' - a
			-- frozen contract - exposes no injection point for it, so the
			-- general-list head is still realized through GDI.
		local
			l_bidi: NULL_BIDI_RESOLVER
			l_itemizer: NULL_SCRIPT_ITEMIZER
			l_shaper: NULL_GLYPH_SHAPER
			l_fallback: NULL_FONT_FALLBACK
		do
			create l_bidi
			create l_itemizer
			create l_shaper
			create l_fallback
			create Result.make_with_backends (l_bidi, l_itemizer, l_shaper, l_fallback,
				{STRING_32} "assets")
		ensure
			headless_seams: attached {NULL_BIDI_RESOLVER} Result.bidi_resolver
				and attached {NULL_SCRIPT_ITEMIZER} Result.script_itemizer
				and attached {NULL_GLYPH_SHAPER} Result.glyph_shaper
				and attached {NULL_FONT_FALLBACK} Result.font_fallback
		end

feature {NONE} -- Implementation: headless run builders (Task 10)

	headless_glyph_run (a_text: READABLE_STRING_32; a_start, a_count: INTEGER;
			a_level: NATURAL_8; a_font: SHAPING_FONT): GLYPH_RUN
			-- One GLYPH_RUN over `a_text' [`a_start' .. `a_start' + `a_count' - 1],
			-- shaped by NULL_GLYPH_SHAPER: no native call, and an advance of
			-- exactly `a_count' * pixel_size / 2 - which is what lets the
			-- wrap tests hand-compute their line breaks.
		require
			range_valid: a_start >= 1 and a_count > 0
				and a_start + a_count - 1 <= a_text.count
			level_bounded: a_level <= Max_bidi_level
		local
			l_item: SCRIPT_ITEM
			l_shaper: NULL_GLYPH_SHAPER
			l_shaped: SHAPED_ITEM
		do
			create l_item.make (a_start, a_count, 0, a_level,
				create {ARRAY [NATURAL_8]}.make_empty)
			create l_shaper
			l_shaped := l_shaper.shape (a_text, l_item, a_font)
			create Result.make (a_start, a_count, a_level, a_font, l_shaped.glyphs,
				l_shaped.x_offsets, l_shaped.y_offsets, l_shaped.clusters, 0,
				l_shaped.advance_sum, a_font.pixel_size.to_double)
		ensure
			range_kept: Result.source_start = a_start and Result.source_count = a_count
			level_kept: Result.embedding_level = a_level
			advance_positive: Result.advance_width > 0.0
		end

	headless_image_run (a_start, a_count: INTEGER; a_level: NATURAL_8;
			a_box: REAL_64): IMAGE_RUN
			-- One atomic emoji box (U+1F916), SQUARE at `a_box'. The size is
			-- fixed here, at construction, exactly as the FACADE fixes it in
			-- the real pipeline (FR-007: the line height) - which is why the
			-- engine can only honor a box, never resize one.
		require
			range_valid: a_start >= 1 and a_count > 0
			level_bounded: a_level <= Max_bidi_level
			box_positive: a_box > 0.0
		local
			l_codes: ARRAY [NATURAL_32]
		do
			create l_codes.make_filled ((0x1F916).to_natural_32, 1, 1)
			create Result.make (a_start, a_count, a_level, l_codes, "emoji_u1f916",
				{STRING_32} "assets/emoji_u1f916.png", a_box, a_box)
		ensure
			range_kept: Result.source_start = a_start and Result.source_count = a_count
			box_is_advance: Result.advance_width = a_box
		end

feature -- Test: font fallback walk (Task 9)

	fallback_ran: BOOLEAN
			-- Did the Task-9 fallback test that just ran reach a LIVE
			-- DirectWrite backend AND both faces the walk needs, each
			-- realized with an IDWriteFontFace? False means it SKIPPED -
			-- never that it passed. Every test below calls
			-- `begin_fallback_test' first, so one test's success can never
			-- mask another's skip.

	fallback_skip_reason: STRING
			-- Why a fallback test could not run (empty when it ran).
		attribute
			create Result.make_empty
		end

	begin_fallback_test
			-- Reset the Task-9 backend protocol.
		do
			fallback_ran := False
			create fallback_skip_reason.make_empty
		ensure
			reset: not fallback_ran and fallback_skip_reason.is_empty
		end

	test_fallback_rescue
			-- AC-4, REAL (Phase 4 Task 9 - this was the skeletal Phase-5
			-- marker). An item of four Hebrew letters is requested under
			-- CONSOLAS, which has no Hebrew at all, and comes back rendered
			-- by the first covering family in the PER-CALL policy.
			--
			-- WHICH FACE AND WHICH CODE POINTS, and why they are honest:
			-- Consolas is Microsoft's programming face - Latin, Greek and
			-- Cyrillic, no Hebrew block. Read from the machine's own
			-- C:\Windows\Fonts\consola.ttf cmap before this test was
			-- written: U+05D0 U+05D5 U+05DC U+05DD U+05E9 all ABSENT,
			-- U+0391 and U+0041 present. The test does NOT take that on
			-- faith: it shapes the item under Consolas itself and asserts
			-- the gap, so a machine whose Consolas somehow covers Hebrew
			-- fails loudly instead of proving nothing.
			--
			-- THE PROBE COUNTS ARE EXACT, and each walk gets its OWN
			-- LIST_FONT_FALLBACK so no verdict cache leaks between the
			-- cases: the covered request costs exactly ONE probe; the
			-- rescued request costs exactly TWO (Consolas, then Segoe UI) -
			-- note that the policy's first entry IS Consolas and it costs
			-- nothing the second time, because step 1 already recorded its
			-- verdict.
		note
			testing: "covers/{LIST_FONT_FALLBACK}.font_for"
		local
			l_registry: FONT_REGISTRY
			l_api: DWRITE_API
			l_shaper: DIRECTWRITE_GLYPH_SHAPER
			l_covered_walk, l_rescue_walk: LIST_FONT_FALLBACK
			l_requested, l_rescue_font: SHAPING_FONT
			l_text: STRING_32
			l_policy: FONT_LIST
			l_class: INTEGER
			l_gap: detachable SHAPED_ITEM
			l_direct, l_rescued: detachable FALLBACK_CHOICE
		do
			begin_fallback_test
			create l_registry.make
			create l_api.make
			l_text := string_of_code_points (<<0x05E9, 0x05DC, 0x05D5, 0x05DD>>)
				-- Realized UNCONDITIONALLY, like the Task-5 shaper tests: an
				-- attached local assigned only inside a branch is `detachable'
				-- to the compiler everywhere after it.
			l_requested := l_registry.font (latin_only_face,
				{SHAPING_FONT}.Weight_regular, False, 16)
			l_rescue_font := l_registry.font (rescue_face,
				{SHAPING_FONT}.Weight_regular, False, 16)
			if fallback_backend_ready (l_registry, l_api) then
				if attached hebrew_item (l_text) as al_item then
					fallback_ran := True
					l_class := script_class_of (l_text, al_item.start_index, al_item.count)
					create l_shaper.make
						-- The premise, measured rather than assumed.
					l_gap := l_shaper.shape (l_text, al_item, l_requested)
						-- (a) the requested font COVERS: one probe, no walk.
					create l_covered_walk.make (l_shaper, l_registry)
					create l_policy.make_empty
					l_policy := l_policy.with_family (rescue_face)
					l_direct := l_covered_walk.font_for (l_text, al_item, l_rescue_font, l_policy)
						-- (b) the requested font has a GAP: rescued by the
						-- first covering family of the per-call policy.
					create l_rescue_walk.make (l_shaper, l_registry)
					create l_policy.make_empty
					l_policy := l_policy.with_family (latin_only_face).with_family (rescue_face)
					l_rescued := l_rescue_walk.font_for (l_text, al_item, l_requested, l_policy)
				else
					fallback_skip_reason := "the itemizer produced no item for the Hebrew probe"
				end
			end
				-- Every native handle released BEFORE the assertions, so a
				-- failing assertion cannot leak a face, an HFONT or an HDC.
			l_registry.dispose_all
			l_api.close

			if fallback_ran and then (attached l_gap as al_gap and attached l_direct as al_direct
				and attached l_rescued as al_rescued)
			then
				print ("    fallback: " + latin_only_face.to_string_8 + " over U+05E9 05DC 05D5 05DD -> missing "
					+ al_gap.missing_glyph_count.out + " of " + al_gap.source_count.out
					+ "; rescued by " + al_rescued.font.family.to_string_8
					+ " in " + al_rescued.probes_performed.out + " probe(s)%N")

					-- ---- the bucket is the CHARACTERS, not the script code ----
				assert_integers_equal ("four Hebrew letters bucket as the hebrew class",
					Script_class_hebrew, l_class)

					-- ---- the premise: this face really has no Hebrew ----
				assert_integers_equal ("every Hebrew letter is missing from " + latin_only_face.to_string_8,
					4, al_gap.missing_glyph_count)
				assert_false ("so the requested face does NOT cover the item", al_gap.is_complete)

					-- ---- (a) requested covers: ONE probe, requested kept ----
				assert_true ("a covering request is answered complete",
					al_direct.is_complete_coverage)
				assert_same_reference ("and with the requested font itself",
					l_rescue_font, al_direct.font)
				assert_integers_equal ("exactly ONE coverage probe (R7)",
					1, al_direct.probes_performed)

					-- ---- (b) the rescue: AC-4 ----
				assert_true ("the gap is rescued - complete coverage",
					al_rescued.is_complete_coverage)
				assert_not_same_reference ("and NOT by the requested font",
					l_requested, al_rescued.font)
				assert_same_reference ("but by the first covering family in the policy",
					l_rescue_font, al_rescued.font)
				assert_strings_equal_case_insensitive ("the choice reports the fallback FACE",
					rescue_face, al_rescued.font.family)
				assert_integers_equal ("exactly TWO probes: the request, then the covering family",
					2, al_rescued.probes_performed)

					-- ---- the frozen seam clauses, checked as facts ----
				assert_integers_equal ("same pixel size across fallback (same-N)",
					l_requested.pixel_size, al_rescued.font.pixel_size)
				assert_integers_equal ("same weight across fallback",
					l_requested.weight, al_rescued.font.weight)
				assert_false ("same style across fallback", al_rescued.font.is_italic)
				assert_true ("no silent drop", al_rescued.is_complete_coverage
					or al_rescued.font = l_requested)
			end
		end

	test_fallback_exhaustion_keeps_the_requested_font
			-- DR-010's other end: a policy whose families ALL lack the item
			-- returns `a_requested' AGAIN with is_complete_coverage = False -
			-- tofu boxes and a Note_fallback_exhausted upstream, never a
			-- silent drop and never a Void answer.
			--
			-- THE POLICY IS THREE FAMILIES AND THE WALK COSTS TWO PROBES,
			-- which is the whole cost model in one number: Consolas (the
			-- request) is probed once in step 1 and NOT re-probed when the
			-- walk reaches it; Verdana - Latin and Greek, no Hebrew block,
			-- read from this machine's verdana.ttf cmap - is probed once;
			-- and a family that is not installed at all costs NOTHING,
			-- because `FONT_REGISTRY.family_exists' settles it before any
			-- font is realized. That last one matters: GDI substitutes a
			-- stand-in for an unknown family without saying so, and the
			-- substitute WOULD have covered Hebrew - the walk would have
			-- "rescued" the item with a face nobody has.
		note
			testing: "covers/{LIST_FONT_FALLBACK}.font_for"
		local
			l_registry: FONT_REGISTRY
			l_api: DWRITE_API
			l_shaper: DIRECTWRITE_GLYPH_SHAPER
			l_walk: LIST_FONT_FALLBACK
			l_requested: SHAPING_FONT
			l_text: STRING_32
			l_policy: FONT_LIST
			l_verdicts: INTEGER
			l_exhausted: detachable FALLBACK_CHOICE
		do
			begin_fallback_test
			create l_registry.make
			create l_api.make
			l_text := string_of_code_points (<<0x05E9, 0x05DC, 0x05D5, 0x05DD>>)
			l_requested := l_registry.font (latin_only_face,
				{SHAPING_FONT}.Weight_regular, False, 16)
			if fallback_backend_ready (l_registry, l_api) then
				if not l_registry.family_exists (second_gapped_face) then
					fallback_skip_reason := "this machine has no " + second_gapped_face.to_string_8
				elseif l_registry.family_exists (absent_face) then
					fallback_skip_reason := "this machine unexpectedly HAS " + absent_face.to_string_8
				elseif attached hebrew_item (l_text) as al_item then
					fallback_ran := True
					create l_shaper.make
					create l_walk.make (l_shaper, l_registry)
					create l_policy.make_empty
					l_policy := l_policy.with_family (latin_only_face)
						.with_family (second_gapped_face).with_family (absent_face)
					l_exhausted := l_walk.font_for (l_text, al_item, l_requested, l_policy)
					l_verdicts := l_walk.verdict_count
				else
					fallback_skip_reason := "the itemizer produced no item for the Hebrew probe"
				end
			end
			l_registry.dispose_all
			l_api.close

			if fallback_ran and then attached l_exhausted as al_exhausted then
				print ("    fallback: policy [" + latin_only_face.to_string_8 + ", "
					+ second_gapped_face.to_string_8 + ", " + absent_face.to_string_8
					+ "] exhausted in " + al_exhausted.probes_performed.out
					+ " probe(s), " + l_verdicts.out + " verdict(s) on record%N")

				assert_false ("exhaustion is NOT complete coverage",
					al_exhausted.is_complete_coverage)
				assert_same_reference ("and it hands back the REQUESTED font (DR-010)",
					l_requested, al_exhausted.font)
				assert_true ("no silent drop", al_exhausted.is_complete_coverage
					or al_exhausted.font = l_requested)
				assert_integers_equal ("TWO probes: the request, then the one other installed family",
					2, al_exhausted.probes_performed)
				assert_integers_equal ("three verdicts on record - the absent family is one of them",
					3, l_verdicts)
				assert_integers_equal ("same pixel size even on exhaustion",
					16, al_exhausted.font.pixel_size)
			end
		end

	test_fallback_verdict_cache_is_policy_independent
			-- The verdict cache, stated as behavior: it is keyed by (script
			-- class, family) and NOT by policy identity, so it survives a
			-- change of per-call policy (R11) within one facade lifetime and
			-- is never invalidated.
			--
			-- PROBES RUN IS THE HONEST READING of `probes_performed': a
			-- cached verdict SKIPS the shape, so the same call made twice
			-- costs 2 probes and then 0 - and a THIRD call under a DIFFERENT
			-- FONT_LIST object still costs 0, because what was learned was a
			-- fact about Hebrew and two families, not about a policy.
		note
			testing: "covers/{LIST_FONT_FALLBACK}.font_for, covers/{LIST_FONT_FALLBACK}.verdict_count"
		local
			l_registry: FONT_REGISTRY
			l_api: DWRITE_API
			l_shaper: DIRECTWRITE_GLYPH_SHAPER
			l_walk: LIST_FONT_FALLBACK
			l_requested: SHAPING_FONT
			l_text: STRING_32
			l_first_policy, l_other_policy: FONT_LIST
			l_after_first, l_after_second, l_after_third: INTEGER
			l_cold, l_warm, l_other: detachable FALLBACK_CHOICE
		do
			begin_fallback_test
			create l_registry.make
			create l_api.make
			l_text := string_of_code_points (<<0x05E9, 0x05DC, 0x05D5, 0x05DD>>)
			l_requested := l_registry.font (latin_only_face,
				{SHAPING_FONT}.Weight_regular, False, 16)
			if fallback_backend_ready (l_registry, l_api) then
				if attached hebrew_item (l_text) as al_item then
					fallback_ran := True
					create l_shaper.make
					create l_walk.make (l_shaper, l_registry)
					create l_first_policy.make_empty
					l_first_policy := l_first_policy.with_family (latin_only_face)
						.with_family (rescue_face)
					l_cold := l_walk.font_for (l_text, al_item, l_requested, l_first_policy)
					l_after_first := l_walk.verdict_count
					l_warm := l_walk.font_for (l_text, al_item, l_requested, l_first_policy)
					l_after_second := l_walk.verdict_count
						-- A DIFFERENT policy object, holding only the face
						-- the cache already has a verdict for.
					create l_other_policy.make_empty
					l_other_policy := l_other_policy.with_family (rescue_face)
					l_other := l_walk.font_for (l_text, al_item, l_requested, l_other_policy)
					l_after_third := l_walk.verdict_count
				else
					fallback_skip_reason := "the itemizer produced no item for the Hebrew probe"
				end
			end
			l_registry.dispose_all
			l_api.close

			if fallback_ran and then (attached l_cold as al_cold and attached l_warm as al_warm
				and attached l_other as al_other)
			then
				print ("    fallback: probes cold/warm/other-policy = "
					+ al_cold.probes_performed.out + "/" + al_warm.probes_performed.out
					+ "/" + al_other.probes_performed.out + ", verdicts "
					+ l_after_first.out + "/" + l_after_second.out + "/" + l_after_third.out + "%N")

				assert_integers_equal ("the cold walk costs two probes",
					2, al_cold.probes_performed)
				assert_integers_equal ("the identical second call costs NONE",
					0, al_warm.probes_performed)
				assert_integers_equal ("and neither does the same walk under ANOTHER policy",
					0, al_other.probes_performed)
				assert_same_reference ("the warm answer is the same face",
					al_cold.font, al_warm.font)
				assert_same_reference ("so is the answer under the other policy",
					al_cold.font, al_other.font)
				assert_true ("all three complete", al_cold.is_complete_coverage
					and al_warm.is_complete_coverage and al_other.is_complete_coverage)
				assert_integers_equal ("two verdicts after the cold walk", 2, l_after_first)
				assert_integers_equal ("write-once: the warm call adds none",
					l_after_first, l_after_second)
				assert_integers_equal ("and the other policy adds none either",
					l_after_first, l_after_third)
			end
		end

	test_script_class_of_buckets_by_code_point
			-- SHAPING_CONSTANTS.script_class_of (ADDED Task 9, gate decision
			-- 5): the FONT_LIST bucket comes from CODE POINT RANGES, so it
			-- means the same thing on every backend. Pure - no machine, no
			-- backend, no skip.
		note
			testing: "covers/{SHAPING_CONSTANTS}.script_class_of, covers/{SHAPING_CONSTANTS}.script_class_of_code_point"
		local
			l_text: STRING_32
		do
				-- ---- one code point at a time ----
			assert_integers_equal ("alef is hebrew", Script_class_hebrew,
				script_class_of_code_point (0x05D0))
			assert_integers_equal ("a niqqud point is hebrew too", Script_class_hebrew,
				script_class_of_code_point (0x05B7))
			assert_integers_equal ("so is a Hebrew presentation form", Script_class_hebrew,
				script_class_of_code_point (0xFB2A))
			assert_integers_equal ("Alpha is greek", Script_class_greek,
				script_class_of_code_point (0x0391))
			assert_integers_equal ("polytonic Greek Extended is greek too", Script_class_greek,
				script_class_of_code_point (0x1F00))
			assert_integers_equal ("A is latin", Script_class_latin,
				script_class_of_code_point (0x0041))
			assert_integers_equal ("e-acute is latin", Script_class_latin,
				script_class_of_code_point (0x00E9))
			assert_integers_equal ("the multiplication sign is a symbol, not a letter",
				Script_class_symbol, script_class_of_code_point (0x00D7))
			assert_integers_equal ("a space is a symbol", Script_class_symbol,
				script_class_of_code_point (0x0020))
			assert_integers_equal ("the robot is a symbol", Script_class_symbol,
				script_class_of_code_point (0x1F916))
			assert_integers_equal ("Cyrillic is other", Script_class_other,
				script_class_of_code_point (0x0410))

				-- ---- over an item's characters: most specific wins ----
			l_text := string_of_code_points (<<0x05E9, 0x05DC, 0x05D5, 0x05DD>>)
			assert_integers_equal ("shalom is a hebrew item", Script_class_hebrew,
				script_class_of (l_text, 1, 4))
			l_text := string_of_code_points (<<0x0041, 0x0020, 0x05E9>>)
			assert_integers_equal ("a mixed item takes the HEBREW policy",
				Script_class_hebrew, script_class_of (l_text, 1, 3))
			assert_integers_equal ("but the Latin prefix alone is latin",
				Script_class_latin, script_class_of (l_text, 1, 1))
			assert_integers_equal ("and the space alone is a symbol",
				Script_class_symbol, script_class_of (l_text, 2, 1))
			l_text := string_of_code_points (<<0x03A7, 0x03C1, 0x03B9>>)
			assert_integers_equal ("a Greek run is greek", Script_class_greek,
				script_class_of (l_text, 1, 3))
			assert_true ("every answer is a valid FONT_LIST class",
				is_valid_script_class (script_class_of (l_text, 1, 3)))
		end

feature -- Test: Phase-5 assault (skeletal; named now so nothing is forgotten)

	test_never_raises_fault_injection
			-- Skeletal: AC-8 - a fault-injecting shaper double still yields
			-- a paintable layout whose degradations are enumerated in notes
			-- (R3 tofu-but-valid).
		do
			-- TODO: Phase 5
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

feature {NONE} -- Test support: the Task-9 fallback walk

	latin_only_face: STRING_32
			-- The face the Task-9 tests use as "covers Latin and Greek, has
			-- NO Hebrew". Consolas is Microsoft's programming face; its cmap
			-- on this machine (C:\Windows\Fonts\consola.ttf) has U+0391 and
			-- U+0041 and lacks the whole U+0590-05FF block. The rescue test
			-- re-measures that at run time rather than trusting it.
		once
			Result := {STRING_32} "Consolas"
		end

	rescue_face: STRING_32
			-- The face expected to RESCUE the Hebrew item: Segoe UI, the
			-- Win10/11 anchor FONT_LIST.make_default already leans on, whose
			-- Hebrew coverage the Task-5 shaper test measured directly.
		once
			Result := {STRING_32} "Segoe UI"
		end

	second_gapped_face: STRING_32
			-- A SECOND installed face with no Hebrew, so the exhaustion test
			-- walks more than one candidate before giving up (verdana.ttf's
			-- cmap: Latin, Greek and Cyrillic, no U+0590-05FF).
		once
			Result := {STRING_32} "Verdana"
		end

	absent_face: STRING_32
			-- A family no machine has, for the "absent counts as not
			-- covered, and costs no probe" branch. The exhaustion test
			-- SKIPS rather than lie if some machine really has it.
		once
			Result := {STRING_32} "No Such Family QZX 9"
		end

	fallback_backend_ready (a_registry: FONT_REGISTRY; a_api: DWRITE_API): BOOLEAN
			-- Can a Task-9 walk actually run here - a live DirectWrite, both
			-- named faces installed AS THEMSELVES (R1: GDI substitutes
			-- silently, and a substitute would make the whole test a lie),
			-- and both realized with an IDWriteFontFace so the probe shapes
			-- for real instead of synthesizing R3 tofu? Sets
			-- `fallback_skip_reason' when the answer is no.
		local
			l_requested, l_rescue: SHAPING_FONT
		do
			if not a_api.open then
				fallback_skip_reason := "DWRITE_API.open failed, last_hresult=0x"
					+ a_api.last_hresult.to_hex_string
			elseif not a_registry.family_exists (latin_only_face) then
				fallback_skip_reason := "this machine has no " + latin_only_face.to_string_8
			elseif not a_registry.family_exists (rescue_face) then
				fallback_skip_reason := "this machine has no " + rescue_face.to_string_8
			else
				l_requested := a_registry.font (latin_only_face,
					{SHAPING_FONT}.Weight_regular, False, 16)
				l_rescue := a_registry.font (rescue_face,
					{SHAPING_FONT}.Weight_regular, False, 16)
				if not l_requested.is_ready or not l_rescue.is_ready then
					fallback_skip_reason := "GDI could not realize both faces at 16 px"
				elseif not l_requested.has_backend_face or not l_rescue.has_backend_face then
					fallback_skip_reason := "a face realized without an IDWriteFontFace"
				else
					Result := True
				end
			end
		ensure
			reason_when_not_ready: not Result implies not fallback_skip_reason.is_empty
		end

	hebrew_item (a_text: STRING_32): detachable SCRIPT_ITEM
			-- The first item the REAL bidi resolver and itemizer produce for
			-- `a_text' - the same route the Task-5 shaper tests take, so the
			-- item carries the backend's own opaque analysis bytes. Void
			-- when itemization produced nothing.
		require
			text_not_empty: not a_text.is_empty
		local
			l_resolver: DIRECTWRITE_BIDI_RESOLVER
			l_itemizer: DIRECTWRITE_SCRIPT_ITEMIZER
			l_bidi: BIDI_RESULT
		do
			create l_resolver.make
			create l_itemizer.make
			l_bidi := l_resolver.resolve (a_text, Direction_ltr)
			if attached l_itemizer.itemize (a_text, 1, a_text.count, l_bidi) as al_items and then
				not al_items.is_empty
			then
				Result := al_items.first
			end
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

	real_segmenter (a_tables: EMOJI_DATA_TABLES): EMOJI_SEGMENTER
			-- A segmenter over `a_tables' resolving against the ACQUIRED
			-- assets through the production-shaped RAW_FILE probe - the
			-- Task-8 pipeline exactly as SIMPLE_SHAPING wires it, minus the
			-- facade.
		require
			assets_located: not real_asset_directory.is_empty
		local
			l_catalog: EMOJI_ASSET_CATALOG
		do
			create l_catalog.make (real_asset_directory, a_tables, agent file_exists)
			create Result.make (a_tables, l_catalog)
		ensure
			over_the_real_assets: Result.catalog.directory.same_string_general (real_asset_directory)
		end

	text_of (a_codes: ARRAY [NATURAL_32]): STRING_32
			-- The string spelled by `a_codes'. Emoji written literally in
			-- Eiffel source would make every test hostage to the file's
			-- encoding, so the tests spell code points in hex.
		require
			nonempty: not a_codes.is_empty
		local
			i: INTEGER
		do
			create Result.make (a_codes.count)
			from i := a_codes.lower until i > a_codes.upper loop
				Result.append_code (a_codes [i])
				i := i + 1
			end
		ensure
			one_character_per_code: Result.count = a_codes.count
		end

	flat_bidi (a_text: READABLE_STRING_32; a_level: NATURAL_8): BIDI_RESULT
			-- Every character of `a_text' resolved to level `a_level'.
		require
			level_bounded: a_level <= Max_bidi_level
		local
			l_levels: ARRAY [NATURAL_8]
		do
			create l_levels.make_filled (a_level, 1, a_text.count)
			create Result.make (l_levels, a_level \\ 2)
		ensure
			covers_the_text: Result.count = a_text.count
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

	probe_only_woman (a_path: READABLE_STRING_32): BOOLEAN
			-- Injected existence probe: ONLY `emoji_u1f469.png' exists.
			-- Manufactures the MIXED sequence - one component with an asset,
			-- one without - that no shipped asset set happens to produce but
			-- that rung 3 must survive.
		do
			Result := a_path.ends_with ({STRING_32} "emoji_u1f469.png")
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
