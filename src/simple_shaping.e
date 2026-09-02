note
	description: "[
		Facade: mixed-script paragraph text to cached, paintable
		SHAPED_LAYOUTs. One entry point (Single Choice): seam wiring, font
		realization, and caching are decided here and nowhere else.
	]"
	author: "Larry Rix"
	design: "[
		One instance per SCOOP processor. This facade, its FONT_REGISTRY,
		all SHAPING_FONTs, every native handle, and the LAYOUT_CACHE are
		confined to the creating processor; no feature accepts or returns
		separate types (OQ-1 resolved by confinement - backend per-font
		cache concurrency is UNVERIFIED upstream, so the design never
		depends on it). A background shaper creates its OWN facade.
	]"
	never_raises: "[
		`layout' is a total function: native failures degrade to fallback
		runs, missing-glyph boxes (R3 tofu-but-valid), or SHAPING_NOTEs
		(NFR-011). No exception escapes.
	]"
	backends: "[
		G1 FINAL (2026-09-01, Larry's ruling + the spikes/dwrite verdict):
		`make' wires DIRECTWRITE_* effectings for bidi/itemization/shaping
		plus LIST_FONT_FALLBACK (G2) - DirectWrite-first supersedes 07's
		UNISCRIBE_* make postcondition; UNISCRIBE_* are now the named-only
		alternate slots and do not exist yet. `make_with_backends' injects
		(tests, alternate-backend experiments).
	]"
	style_freeze: "[
		R9 (Q12): MVP shapes everything regular-weight upright
		({SHAPING_FONT}.Weight_regular, not italic). SHAPING_FONT and seam 4
		keep weight/italic, so a future styled-runs extension changes this
		facade only - never the seams or the run model.
	]"
	assets: "[
		AC-9 RUNNABLE FOLDER - where the emoji PNGs are expected to be.
		THE DEFAULT IS `assets\noto-emoji\png\128' RESOLVED AGAINST THE
		DIRECTORY OF THE RUNNING EXECUTABLE, never against the working
		directory: a consumer's cwd is not a contract (a shortcut, a
		service, an Explorer double-click and a debugger all differ), while
		the folder the exe was copied into is exactly what AC-9 promises to
		be self-contained. `default_asset_directory' computes that path;
		`set_asset_directory' is the override for a consumer that lays its
		payload out differently.

		`make' takes the directory from its caller (a frozen precondition),
		so the default is a RULE THE CONSUMER APPLIES, in one of two ways:

			create shaping.make (application_asset_directory)
				-- the same expression `default_asset_directory' uses, or

			create shaping.make (some_seed_directory)
			shaping := shaping.set_asset_directory (shaping.default_asset_directory)

		Missing assets are NOT an error at any level: EMOJI_SEGMENTER's
		FR-007 ladder degrades every unresolvable sequence to plain text
		with a Note_emoji_degraded, so a folder without `assets\' still
		lays out and paints - only without color emoji.
	]"
	consumer_guidance: "[
		R10: (1) Size bubbles from layout.total_height ALWAYS (cached, free);
		`line_height' is only for the empty-message minimum (FR-N01) and
		pane pre-allocation. (2) Re-layout on resize-END (debounced), not
		per resize tick - live-resize thrash evicts the cache's useful
		generation (Q2).
	]"

class
	SIMPLE_SHAPING

inherit
	SHAPING_CONSTANTS

create
	make, make_with_backends

feature {NONE} -- Initialization

	make (a_asset_directory: READABLE_STRING_32)
			-- Production wiring: DirectWrite seams (G1 final), own fallback
			-- (G2), default fonts, empty cache.
		require
			directory_not_empty: not a_asset_directory.is_empty
		do
			initialize_core (a_asset_directory)
			create {DIRECTWRITE_BIDI_RESOLVER} bidi_resolver.make
			create {DIRECTWRITE_SCRIPT_ITEMIZER} script_itemizer.make
			create {DIRECTWRITE_GLYPH_SHAPER} glyph_shaper.make
			create {LIST_FONT_FALLBACK} font_fallback.make (glyph_shaper, registry)
			create catalog.make (a_asset_directory, tables, agent file_probe.exists)
			create segmenter.make (tables, catalog)
		ensure
			directwrite_wired: attached {DIRECTWRITE_BIDI_RESOLVER} bidi_resolver
				and attached {DIRECTWRITE_SCRIPT_ITEMIZER} script_itemizer
				and attached {DIRECTWRITE_GLYPH_SHAPER} glyph_shaper
			own_fallback: attached {LIST_FONT_FALLBACK} font_fallback
			asset_directory_set: asset_directory.same_string_general (a_asset_directory)
			cache_empty: cache_count = 0
			cache_model_empty: cache_model.is_empty
			defaults_present: not default_fonts.is_empty
			statistics_zero: statistics.shape_calls = 0
			statistics_model_zero: statistics.counters_model.is_constant (0)
		end

	make_with_backends (a_bidi: BIDI_RESOLVER; a_itemizer: SCRIPT_ITEMIZER;
			a_shaper: GLYPH_SHAPER; a_fallback: FONT_FALLBACK;
			a_asset_directory: READABLE_STRING_32)
			-- Injected seams (headless tests, alternate-backend swaps).
		require
			directory_not_empty: not a_asset_directory.is_empty
		do
			initialize_core (a_asset_directory)
			bidi_resolver := a_bidi
			script_itemizer := a_itemizer
			glyph_shaper := a_shaper
			font_fallback := a_fallback
			create catalog.make (a_asset_directory, tables, agent file_probe.exists)
			create segmenter.make (tables, catalog)
		ensure
			wired: bidi_resolver = a_bidi and script_itemizer = a_itemizer
				and glyph_shaper = a_shaper and font_fallback = a_fallback
			asset_directory_set: asset_directory.same_string_general (a_asset_directory)
			cache_empty: cache_count = 0
			cache_model_empty: cache_model.is_empty
			statistics_zero: statistics.shape_calls = 0
			statistics_model_zero: statistics.counters_model.is_constant (0)
		end

feature -- Core Operations

	layout (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER;
			a_fonts: FONT_LIST): SHAPED_LAYOUT
			-- Layout of paragraph `a_text' wrapped to `a_width_pixels'
			-- (No_wrap = 0: one unbounded line) at `a_pixel_size' under
			-- policy `a_fonts'. Pipeline (A-C03/DR-005): bidi over the FULL
			-- text -> emoji segmentation (spans inherit resolved levels) ->
			-- itemization of plain spans only -> fallback + shape per item
			-- -> cluster-safe greedy wrap -> per-line visual reorder.
			-- Cached by (text, width, size, fonts.digest, asset_directory);
			-- a repeat call performs ZERO shaping (FR-012). Benign memo
			-- effect only (cache/statistics are not abstract state -
			-- declared CQS exception, 05).
		require
			width_non_negative: a_width_pixels >= 0
			size_positive: a_pixel_size > 0
			fonts_usable: not a_fonts.is_empty
		local
			l_key, l_digest: STRING_8
			l_lines: ARRAYED_LIST [SHAPED_LINE]
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
		do
				-- R5/decision 3: prime the effective-digest memo BEFORE
				-- anything else, so every later evaluation - here, in
				-- `cache_key', and inside this routine's own postconditions -
				-- is a table lookup and never a GDI probe.
			l_digest := effective_digest (a_fonts)
			l_key := cache_key (a_text, a_width_pixels, a_pixel_size, a_fonts)
			if attached cache.item_verified (l_key, a_text, a_width_pixels, a_pixel_size,
				l_digest) as al_hit
			then
				statistics.record_cache_hit
				Result := al_hit
			else
				statistics.record_cache_miss
				-- Phase 4: the real pipeline through the seams, with
				-- base direction from bidi's first-strong resolution and
				-- statistics.record_shape_call per run-producing shape (R7);
				-- `segmenter.segment (a_text, bidi, l_notes)' feeds the
				-- Note_emoji_degraded accumulator (ISSUE 6); every seam-4
				-- answer is charged with
				-- `statistics.record_fallback_probes (choice.probes_performed)'
				-- (R7 amended, ISSUE 7); and seam 4 is called as
				-- `font_fallback.font_for (a_text, item, requested, a_fonts)' -
				-- the PER-CALL policy, R11/ISSUE 4.
				-- Phase 1 degenerate total-function result: one line covering
				-- every character, zero runs, placeholder metrics.
				l_lines := layout_engine.build_lines (a_text, a_width_pixels, a_pixel_size,
					create {ARRAYED_LIST [SHAPED_RUN]}.make (0), bidi_resolver)
				create l_notes.make (0)
				create Result.make (a_text, a_width_pixels, a_pixel_size, Direction_ltr, l_lines, l_notes)
				cache.put (l_key, Result, l_digest)
			end
		ensure
			total_function: Result /= Void
			source_kept: Result.source_text.same_string_general (a_text)
			parameters_kept: Result.width_pixels = a_width_pixels and Result.pixel_size = a_pixel_size
			at_least_one_line: not Result.lines_model.is_empty
			coverage: Result.covers_all_characters
			width_respected: a_width_pixels > 0 implies Result.respects_width
			cached_now: is_cached (a_text, a_width_pixels, a_pixel_size, a_fonts)
			result_stored: cache_model.domain [cache_key (a_text, a_width_pixels, a_pixel_size, a_fonts)]
				and then cache_model [cache_key (a_text, a_width_pixels, a_pixel_size, a_fonts)] = Result
			cache_bounded_growth: cache_count <= old cache_count + 1
			cache_exact_when_room: (old cache_count < cache_capacity) implies
				cache_model |=| (old cache_model).updated (
					cache_key (a_text, a_width_pixels, a_pixel_size, a_fonts), Result)
			hit_cache_frame: (old is_cached (a_text, a_width_pixels, a_pixel_size, a_fonts))
				implies cache_model |=| old cache_model
			hit_shapes_nothing: (old is_cached (a_text, a_width_pixels, a_pixel_size, a_fonts))
				implies statistics.shape_calls = old statistics.shape_calls
			hit_counted: (old is_cached (a_text, a_width_pixels, a_pixel_size, a_fonts)) implies
				(statistics.cache_hits = old statistics.cache_hits + 1
				and statistics.cache_misses = old statistics.cache_misses)
			miss_counted: (not old is_cached (a_text, a_width_pixels, a_pixel_size, a_fonts)) implies
				(statistics.cache_misses = old statistics.cache_misses + 1
				and statistics.cache_hits = old statistics.cache_hits)
		end

	layout_default (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER): SHAPED_LAYOUT
			-- `layout' under `default_fonts' - the chat pane's per-message
			-- call. R6: a convenience wrapper restates the wrapped
			-- operation's observable postconditions.
		require
			width_non_negative: a_width_pixels >= 0
			size_positive: a_pixel_size > 0
		do
			Result := layout (a_text, a_width_pixels, a_pixel_size, default_fonts)
		ensure
			total_function: Result /= Void
			source_kept: Result.source_text.same_string_general (a_text)
			parameters_kept: Result.width_pixels = a_width_pixels and Result.pixel_size = a_pixel_size
			at_least_one_line: not Result.lines_model.is_empty
			coverage: Result.covers_all_characters
			width_respected: a_width_pixels > 0 implies Result.respects_width
			cached_under_defaults: is_cached (a_text, a_width_pixels, a_pixel_size, default_fonts)
			result_stored: cache_model.domain [cache_key (a_text, a_width_pixels, a_pixel_size, default_fonts)]
				and then cache_model [cache_key (a_text, a_width_pixels, a_pixel_size, default_fonts)] = Result
			cache_bounded_growth: cache_count <= old cache_count + 1
			counted_once: statistics.cache_hits + statistics.cache_misses
				= old statistics.cache_hits + old statistics.cache_misses + 1
		end

feature -- Measurement

	measured_width (a_text: READABLE_STRING_32; a_pixel_size: INTEGER; a_fonts: FONT_LIST): REAL_64
			-- Unwrapped advance width of `a_text' (the first line of a
			-- No_wrap layout - a real definition, cached like any layout).
			-- R2 (Q3): whitespace measures as shaped - a run of spaces has
			-- real width; nothing is trimmed here.
			--
			-- R2's MEASUREMENT half is NOT contracted (Phase 2 / ISSUE 9).
			-- The clause that claimed it - `a_text.count > 0 implies
			-- Result >= 0.0' - was implied by `non_negative' and constrained
			-- nothing; it is deleted rather than left to read as a promise.
			-- The real obligation lands on the Phase-5 test
			-- `test_whitespace_measures_positive_under_realized_font'
			-- (whitespace-only text under a REALIZED font measures > 0),
			-- which needs Phase-4 realization to mean anything. R2's WRAP
			-- half is already real and contracted, in
			-- LINE_LAYOUT_ENGINE.fits_within.
		require
			size_positive: a_pixel_size > 0
			fonts_usable: not a_fonts.is_empty
		do
			Result := layout (a_text, No_wrap, a_pixel_size, a_fonts).lines.first.width
		ensure
			non_negative: Result >= 0.0
			empty_is_zero: a_text.is_empty implies Result = 0.0
			cache_bounded_growth: cache_count <= old cache_count + 1
			counted_once: statistics.cache_hits + statistics.cache_misses
				= old statistics.cache_hits + old statistics.cache_misses + 1
		end

	line_height (a_pixel_size: INTEGER; a_fonts: FONT_LIST): REAL_64
			-- Height of one line of `a_fonts''s primary face at
			-- `a_pixel_size' (FR-N01 empty-message sizing; Q8: primary =
			-- first REALIZED family of the general list; consumers size
			-- bubbles from layout.total_height, not from this).
		require
			size_positive: a_pixel_size > 0
			fonts_usable: not a_fonts.is_empty
		do
			-- Phase 4: ascent + descent of the first realized general-list
			-- family via `registry'.
			Result := a_pixel_size.to_double
		ensure
			positive: Result > 0.0
			cache_untouched: cache_model |=| old cache_model
			statistics_untouched: statistics.counters_model |=| old statistics.counters_model
		end

feature -- Configuration

	default_fonts: FONT_LIST
			-- Policy used by `layout_default'.

	asset_directory: IMMUTABLE_STRING_32
			-- Where the Noto png/128 assets live (G3).

	default_asset_directory: STRING_32
			-- AC-9's asset location: `assets\noto-emoji\png\128' under the
			-- directory of the RUNNING EXECUTABLE - see the `assets' note at
			-- the top of this class for why the exe's folder and not the
			-- working directory. A pure derivation: it probes nothing and
			-- promises nothing about what is actually on disk (the FR-007
			-- ladder answers that, per sequence, at segmentation time).
		local
			l_environment: EXECUTION_ENVIRONMENT
			l_executable, l_assets: PATH
		do
			create l_environment
			create l_executable.make_from_string (l_environment.arguments.command_name)
			l_assets := l_executable.parent.extended ("assets")
			l_assets := l_assets.extended ("noto-emoji").extended ("png").extended ("128")
			Result := l_assets.name.to_string_32
		ensure
			never_empty: not Result.is_empty
			png_128_layout: Result.ends_with ({STRING_32} "128")
		end

	set_default_fonts (a_fonts: FONT_LIST): like Current
			-- Use `a_fonts' for `layout_default'. A DEFENSIVE DEEP COPY is
			-- taken (Phase 2 / ISSUE 14): A-C05's "immutable after
			-- configuration" was discipline only - the caller kept a live
			-- reference and `with_family' stayed callable, so a later
			-- mutation would silently change this facade's policy and every
			-- future cache key mid-life. FONT_LIST.copy is deep (ISSUE 3),
			-- so `twin' really severs it; value equality is unaffected,
			-- which is why `set' below still reads `~'.
		require
			fonts_usable: not a_fonts.is_empty
		do
			default_fonts := a_fonts.twin
			Result := Current
		ensure
			set: default_fonts ~ a_fonts
			not_aliased: default_fonts /= a_fonts
			chaining: Result = Current
			cache_untouched_when_equal: (old default_fonts ~ a_fonts) implies cache_count = old cache_count
			cache_preserved: cache_model |=| old cache_model
			statistics_untouched: statistics.counters_model |=| old statistics.counters_model
		end

	set_asset_directory (a_path: READABLE_STRING_32): like Current
			-- Point emoji resolution at `a_path'. Clears the cache: assets
			-- are part of layout identity.
		require
			path_not_empty: not a_path.is_empty
		do
			create asset_directory.make_from_string_general (a_path)
			create catalog.make (a_path, tables, agent file_probe.exists)
			create segmenter.make (tables, catalog)
			cache.wipe
			Result := Current
		ensure
			set: asset_directory.same_string_general (a_path)
			chaining: Result = Current
			cache_cleared: cache_count = 0
			cache_model_empty: cache_model.is_empty
			capacity_kept: cache_capacity = old cache_capacity
			statistics_untouched: statistics.counters_model |=| old statistics.counters_model
			defaults_kept: default_fonts = old default_fonts
		end

	set_cache_capacity (a_capacity: INTEGER): like Current
			-- Bound the layout cache (default {SHAPING_CONSTANTS}.Default_cache_capacity).
		require
			positive: a_capacity > 0
		do
			cache.set_capacity (a_capacity)
			Result := Current
		ensure
			set: cache_capacity = a_capacity
			chaining: Result = Current
			bounded_now: cache_count <= a_capacity
			survivors_kept: cache_model |=| ((old cache_model) | cache_model.domain)
			statistics_untouched: statistics.counters_model |=| old statistics.counters_model
			defaults_kept: default_fonts = old default_fonts
		end

feature -- Backend access (read-only; wiring happens only at creation)

	bidi_resolver: BIDI_RESOLVER
			-- Seam 1.

	script_itemizer: SCRIPT_ITEMIZER
			-- Seam 2.

	glyph_shaper: GLYPH_SHAPER
			-- Seam 3.

	font_fallback: FONT_FALLBACK
			-- Seam 4.

feature -- Status

	statistics: SHAPING_STATISTICS
			-- Observability counters (FR-N02; R7 definitions on the class).

	cache_count: INTEGER
			-- Cached layouts now.
		do
			Result := cache.count
		ensure
			non_negative: Result >= 0
		end

	cache_capacity: INTEGER
			-- Layout-cache bound.
		do
			Result := cache.capacity
		ensure
			positive: Result > 0
		end

	is_cached (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER;
			a_fonts: FONT_LIST): BOOLEAN
			-- Would `layout' with these arguments hit the cache (verified,
			-- R8)? Pre-flight query; pure.
		require
			width_non_negative: a_width_pixels >= 0
			size_positive: a_pixel_size > 0
			fonts_usable: not a_fonts.is_empty
		do
			Result := cache.has_verified (cache_key (a_text, a_width_pixels, a_pixel_size, a_fonts),
				a_text, a_width_pixels, a_pixel_size, effective_digest (a_fonts))
		end

	effective_digest (a_fonts: FONT_LIST): STRING_8
			-- [ADDED Phase 4 Task 2] R5: the digest of `a_fonts' AFTER the
			-- R1 existence probe has dropped the families this machine does
			-- not have - the policy that will actually render, which is the
			-- only policy a cached layout was ever computed under.
			--
			-- MEMOIZED PER CONFIGURED DIGEST (gate decision 3, Open question
			-- 3). `cache_key' is evaluated inside `layout' and
			-- `layout_default' POSTCONDITIONS, so without a memo assertion
			-- evaluation would run GDI probes - expensive, and repeated. The
			-- memo makes the second and every later evaluation a hash lookup:
			-- cheap, deterministic and probe-free after the first call. It is
			-- a write-once benign side effect on a query (the declared CQS
			-- exception, 05), and it never invalidates because
			-- FONT_REGISTRY's own verdicts never do.
			--
			-- The R8 entry-side check uses THIS digest too, not the
			-- configured one: a cache key that claims effective identity
			-- while verification demanded configured identity would demote
			-- every hit R5 exists to create, and R5 would deliver nothing.
		local
			l_configured: STRING_8
		do
			l_configured := a_fonts.digest
			if attached effective_digests.item (l_configured) as al_digest then
				Result := al_digest
			else
				Result := effective_policy (a_fonts).digest
				effective_digests.put (Result, l_configured)
			end
		ensure
			never_empty: not Result.is_empty
			memoized: effective_digests.has (a_fonts.digest)
			stable: attached effective_digests.item (a_fonts.digest) as al_memo
				and then al_memo.same_string (Result)
		end

	missing_family_count: INTEGER
			-- [ADDED Phase 4 Task 2] Distinct configured families this
			-- machine turned out not to have (R1). Exactly one
			-- `Note_family_missing' has been built per family counted here,
			-- once per facade lifetime - never one per layout call.
		do
			Result := noted_missing_families.count
		ensure
			non_negative: Result >= 0
		end

feature -- Model queries (simple_mml)

	cache_model: MML_MAP [STRING_8, SHAPED_LAYOUT]
			-- Cache key -> cached layout as a mathematical map (delegates
			-- to LAYOUT_CACHE.cache_model; LRU recency is deliberately not
			-- model state - see LAYOUT_CACHE's model decision note).
		do
			Result := cache.cache_model
		ensure
			same_count: Result.count = cache_count
		end

feature -- Commands

	clear_cache
			-- Drop every cached layout (theme/font change).
		do
			cache.wipe
		ensure
			emptied: cache_count = 0
			cache_model_empty: cache_model.is_empty
			statistics_kept: statistics.shape_calls = old statistics.shape_calls
			statistics_untouched: statistics.counters_model |=| old statistics.counters_model
			defaults_kept: default_fonts = old default_fonts
			capacity_kept: cache_capacity = old cache_capacity
		end

	wipe_statistics
			-- Reset counters (test isolation).
		do
			statistics.wipe
		ensure
			zeroed: statistics.shape_calls = 0 and statistics.cache_hits = 0
				and statistics.cache_misses = 0 and statistics.fallback_probes = 0
			model_zeroed: statistics.counters_model.is_constant (0)
			cache_preserved: cache_model |=| old cache_model
			defaults_kept: default_fonts = old default_fonts
		end

feature {NONE} -- Implementation

	segmenter: EMOJI_SEGMENTER
			-- UTS #51 segmentation + the FR-007 ladder (G3).

	catalog: EMOJI_ASSET_CATALOG
			-- Noto asset resolution (G3).

	tables: EMOJI_DATA_TABLES
			-- Pinned emoji data (D-S08).

	file_probe: EMOJI_FILE_PROBE
			-- THE PRODUCTION EXISTENCE PROBE (Task 8) the catalog resolves
			-- through. An object rather than an `agent asset_file_exists'
			-- because an agent closed on Current is not creatable inside a
			-- creation procedure under void safety - see EMOJI_FILE_PROBE's
			-- own note.

	registry: FONT_REGISTRY
			-- This processor's font ownership (DR-012).

	cache: LAYOUT_CACHE
			-- The FR-012 layout cache.

	layout_engine: LINE_LAYOUT_ENGINE
			-- Wrap + reorder + metrics.

	effective_digests: HASH_TABLE [STRING_8, STRING_8]
			-- [ADDED Phase 4 Task 2] Configured policy digest -> effective
			-- policy digest (R5's memo; gate decision 3).

	noted_missing_families: ARRAYED_LIST [STRING_32]
			-- [ADDED Phase 4 Task 2] Case-folded families already reported
			-- absent. R1 says ONE note per family per facade lifetime, and
			-- this list is what makes "already" statable.

	pending_family_notes: ARRAYED_LIST [SHAPING_NOTE]
			-- [ADDED Phase 4 Task 2] The `Note_family_missing' records built
			-- at probe time, waiting for a layout to carry them. Task 11
			-- drains them into the next produced layout's notes and charges
			-- `statistics.record_note' there - which is why nothing here
			-- touches SHAPING_STATISTICS: `line_height' and
			-- `set_default_fonts' promise `statistics_untouched', and they
			-- reach the probe through `effective_digest'.

	effective_policy (a_fonts: FONT_LIST): FONT_LIST
			-- [ADDED Phase 4 Task 2] R1: `a_fonts' with every family this
			-- machine cannot realize DROPPED, order otherwise preserved -
			-- the general list in order, then each script class's prepends.
			--
			-- The prepends are rebuilt BACK TO FRONT because
			-- `with_family_for_script' prepends: walking the class list from
			-- its last entry forward is what reproduces the original
			-- priority order in the copy.
		local
			l_names: MML_SEQUENCE [IMMUTABLE_STRING_32]
			l_scripts: MML_MAP [INTEGER, MML_SEQUENCE [IMMUTABLE_STRING_32]]
			l_class, i: INTEGER
		do
			create Result.make_empty
			l_names := a_fonts.families_model
			from i := 1 until i > l_names.count loop
				if family_survives (l_names [i]) then
					Result := Result.with_family (l_names [i])
				end
				i := i + 1
			end
			l_scripts := a_fonts.script_families_model
			from l_class := Script_class_hebrew until l_class > Script_class_other loop
				if l_scripts.domain [l_class] then
					l_names := l_scripts [l_class]
					from i := l_names.count until i < 1 loop
						if family_survives (l_names [i]) then
							Result := Result.with_family_for_script (l_class, l_names [i])
						end
						i := i - 1
					end
				end
				l_class := l_class + 1
			end
		ensure
			never_void: Result /= Void
		end

	family_survives (a_family: IMMUTABLE_STRING_32): BOOLEAN
			-- [ADDED Phase 4 Task 2] Does `a_family' stay in the effective
			-- list - and, the first time it does not, build its note?
		require
			family_not_empty: not a_family.is_empty
		do
			Result := registry.family_exists (a_family)
			if not Result then
				note_missing_family (a_family)
			end
		ensure
			verdict_is_the_registry_s: Result = registry.family_exists (a_family)
		end

	note_missing_family (a_family: READABLE_STRING_32)
			-- [ADDED Phase 4 Task 2] Build the ONE `Note_family_missing'
			-- this facade will ever emit for `a_family' (R1). A second
			-- discovery of the same family adds nothing: the probe verdicts
			-- are memoized, so a repeat can only come from another policy
			-- naming the same absent face, and R1 says the reader is told
			-- once.
		require
			family_not_empty: not a_family.is_empty
		local
			l_key, l_message: STRING_32
		do
			l_key := a_family.as_string_32.as_lower
			if not across noted_missing_families as n some n.same_string (l_key) end then
				noted_missing_families.extend (l_key)
				create l_message.make_from_string_general (
					"Configured font family absent on this machine; dropped from the effective list: ")
				l_message.append_string_general (a_family)
				pending_family_notes.extend (
					create {SHAPING_NOTE}.make (Note_family_missing, l_message, 0, 0))
			end
		ensure
			recorded: across noted_missing_families as n some
				n.same_string (a_family.as_string_32.as_lower) end
			one_note_per_family: pending_family_notes.count <= noted_missing_families.count
		end

	initialize_core (a_asset_directory: READABLE_STRING_32)
			-- Everything except the four seams.
		require
			directory_not_empty: not a_asset_directory.is_empty
		do
			create statistics.make
			create registry.make
			create cache.make (Default_cache_capacity)
			create layout_engine.make
			create default_fonts.make_default
			create asset_directory.make_from_string_general (a_asset_directory)
			create tables
			create effective_digests.make (4)
			create noted_missing_families.make (4)
			create pending_family_notes.make (4)
			create file_probe
		ensure
			cache_empty: cache_count = 0
			statistics_zero: statistics.shape_calls = 0
			defaults_present: not default_fonts.is_empty
		end

	cache_key (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER;
			a_fonts: FONT_LIST): STRING_8
			-- Digest of the full layout identity.
			--
			-- R5 (Phase 4 Task 2): the fonts component is the POST-PROBE
			-- EFFECTIVE digest, not the configured one - two policies that
			-- differ only in a family this machine does not have render
			-- identically and now share one cache entry. `effective_digest'
			-- is memoized, which is what keeps this feature cheap enough to
			-- be evaluated inside `layout''s postconditions (decision 3).
			--
			-- INJECTIVE BY LENGTH PREFIX (Phase 2 / ISSUE 2): each STRING
			-- component is emitted as `byte count' + ':' + bytes, so no
			-- content can forge a separator. Bare '|' separators let two
			-- different (fonts, directory, text) triples produce the same
			-- key - and a colliding key that also matched on text, width and
			-- size would have been served as a verified hit under the WRONG
			-- font policy. Integers cannot contain '|' and keep their plain
			-- separator. R8's entry-side check (LAYOUT_CACHE now stores and
			-- compares the fonts digest) is the second, independent guard.
		local
			l_utf: UTF_CONVERTER
			l_bytes: STRING_8
		do
			create Result.make (a_text.count + 64)
			l_bytes := effective_digest (a_fonts)
			Result.append_integer (l_bytes.count)
			Result.append_character (':')
			Result.append (l_bytes)
			Result.append_character ('|')
			Result.append_integer (a_width_pixels)
			Result.append_character ('|')
			Result.append_integer (a_pixel_size)
			Result.append_character ('|')
			l_bytes := l_utf.utf_32_string_to_utf_8_string_8 (asset_directory)
			Result.append_integer (l_bytes.count)
			Result.append_character (':')
			Result.append (l_bytes)
			l_bytes := l_utf.utf_32_string_to_utf_8_string_8 (a_text)
			Result.append_integer (l_bytes.count)
			Result.append_character (':')
			Result.append (l_bytes)
		ensure
			never_empty: not Result.is_empty
		end

invariant
	seams_attached: bidi_resolver /= Void and script_itemizer /= Void
		and glyph_shaper /= Void and font_fallback /= Void
	cache_bounded: cache_count <= cache_capacity
	capacity_positive: cache_capacity > 0
	cache_model_consistent: cache_model.count = cache_count
	defaults_usable: not default_fonts.is_empty

end
