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
					-- AC-3 (Phase 4 Task 11): a VERIFIED hit shapes nothing,
					-- probes nothing and emits no note - `record_cache_hit' is
					-- the only counter this branch is allowed to move (R7), and
					-- that is what makes a 200-message repaint free (FR-012).
				statistics.record_cache_hit
				Result := al_hit
			else
				statistics.record_cache_miss
					-- The A-C03/DR-005 pipeline, whole, in `piped_layout':
					-- bidi over the FULL text -> emoji segmentation (spans
					-- inherit resolved levels) -> itemization of PLAIN spans
					-- only -> seam 4 with the PER-CALL policy (R11) then seam 3
					-- -> pre-split at the soft breaks that are cluster
					-- boundaries (gate decision 1) -> cluster-safe greedy wrap
					-- -> per-line visual reorder -> SHAPED_LAYOUT + notes.
				Result := piped_layout (a_text, a_width_pixels, a_pixel_size, a_fonts)
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
				-- Q8: the FIRST REALIZED family of the GENERAL list, measured
				-- at `a_pixel_size' (TEXTMETRIC ascent + descent), falling back
				-- to the size itself when this machine realizes none of them.
				-- `primary_line_height' touches no counter and no cache entry,
				-- which is what keeps the two frame clauses below true.
			Result := primary_line_height (a_pixel_size, a_fonts)
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

feature {NONE} -- Implementation: the A-C03/DR-005 pipeline (ADDED Phase 4 Task 11)

	piped_layout (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER;
			a_fonts: FONT_LIST): SHAPED_LAYOUT
			-- [ADDED Phase 4 Task 11] `layout''s MISS path, whole.
			--
			-- TOTAL (NFR-011). Every seam below degrades instead of raising:
			-- a dead bidi backend answers all-paragraph-level, a dead shaper
			-- answers R3 tofu, an exhausted fallback answers the requested
			-- face, and an item whose font this machine cannot realize at all
			-- simply produces NO runs plus one note. The LINES still partition
			-- the text in every one of those cases, so what comes back is
			-- always paintable and `coverage' always holds.
			--
			-- ORDER MATTERS TWICE. `effective_policy' runs FIRST because it is
			-- the R1 probe that BUILDS the pending family notes; draining them
			-- afterwards is what puts them on this layout instead of the next
			-- one. And `record_note' runs LAST, once per note the finished
			-- layout carries, so the counter and the list can never disagree.
		require
			width_non_negative: a_width_pixels >= 0
			size_positive: a_pixel_size > 0
			fonts_usable: not a_fonts.is_empty
		local
			l_effective: FONT_LIST
			l_bidi: BIDI_RESULT
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
			l_runs: ARRAYED_LIST [SHAPED_RUN]
			l_lines: ARRAYED_LIST [SHAPED_LINE]
			i: INTEGER
		do
			l_effective := effective_policy (a_fonts)
			create l_notes.make (4)
			drain_family_notes (l_notes)
			l_bidi := bidi_resolver.resolve (a_text, Direction_auto)
			l_runs := pipeline_runs (a_text, a_pixel_size, a_fonts, l_effective, l_bidi, l_notes)
			l_lines := wrapped_lines (a_text, a_width_pixels, a_pixel_size, l_runs)
			create Result.make (a_text, a_width_pixels, a_pixel_size,
				l_bidi.resolved_direction, l_lines, l_notes)
			from i := 1 until i > l_notes.count loop
				statistics.record_note
				i := i + 1
			end
		ensure
			never_void: Result /= Void
			parameters_kept: Result.width_pixels = a_width_pixels
				and Result.pixel_size = a_pixel_size
			source_kept: Result.source_text.same_string_general (a_text)
			notes_counted: statistics.notes_emitted
				= old statistics.notes_emitted + Result.notes.count
		end

	pipeline_runs (a_text: READABLE_STRING_32; a_pixel_size: INTEGER;
			a_fonts, a_effective: FONT_LIST; a_bidi: BIDI_RESULT;
			a_notes: ARRAYED_LIST [SHAPING_NOTE]): ARRAYED_LIST [SHAPED_RUN]
			-- [ADDED Phase 4 Task 11] Every run of the paragraph in LOGICAL
			-- order, covering it contiguously: an EMOJI segment becomes ONE
			-- IMAGE_RUN (FR-006: a ZWJ family is one image), a PLAIN span is
			-- itemized and shaped.
			--
			-- ONLY PLAIN SPANS REACH THE ITEMIZER (DR-005). SCRIPT_ITEMIZER
			-- states that as a CALLER DUTY rather than a precondition, and
			-- this loop is the caller that owes it.
		require
			size_positive: a_pixel_size > 0
			fonts_usable: not a_fonts.is_empty
			bidi_covers: a_bidi.count = a_text.count
		local
			l_segments: ARRAYED_LIST [TEXT_SEGMENT]
			l_items: ARRAYED_LIST [SCRIPT_ITEM]
			l_box: REAL_64
			i, k: INTEGER
		do
			create Result.make (8)
				-- FR-007: the emoji box is SQUARE at the line height, fixed
				-- here because IMAGE_RUN is immutable and the engine can only
				-- honor a box, never resize one.
			l_box := primary_line_height (a_pixel_size, a_fonts)
			l_segments := segmenter.segment (a_text, a_bidi, a_notes)
			from i := 1 until i > l_segments.count loop
				if l_segments [i].is_plain then
					l_items := script_itemizer.itemize (a_text, l_segments [i].start_index,
						l_segments [i].count, a_bidi)
					from k := 1 until k > l_items.count loop
						append_item_runs (a_text, l_items [k], a_pixel_size, a_fonts,
							a_effective, Result, a_notes)
						k := k + 1
					end
				else
					append_image_run (l_segments [i], l_box, Result, a_notes)
				end
				i := i + 1
			end
		ensure
			never_void: Result /= Void
		end

	append_item_runs (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
			a_pixel_size: INTEGER; a_fonts, a_effective: FONT_LIST;
			a_runs: ARRAYED_LIST [SHAPED_RUN]; a_notes: ARRAYED_LIST [SHAPING_NOTE])
			-- [ADDED Phase 4 Task 11] Seam 4 then seam 3 for ONE item, and the
			-- glyphs that come back pre-split into runs at the soft-break
			-- positions that are cluster boundaries.
			--
			-- GATE DECISION 1 (Larry, 2026-09-02): the FACADE pre-splits, so a
			-- break opportunity reaches LINE_LAYOUT_ENGINE as RUN GRANULARITY
			-- and `build_lines' never needs a soft-break parameter. Everything
			-- DR-007 forbids - a break inside a base+mark cluster, a break
			-- inside an emoji segment - is then structurally impossible rather
			-- than re-checked downstream.
			--
			-- R7, DISJOINT AND EXACT: `record_fallback_probes' takes the walk's
			-- own count off the choice (ISSUE 7 - only the walk knows it), and
			-- `record_shape_call' fires ONCE per RUN-PRODUCING shape, whatever
			-- number of runs the pre-split then carves out of it.
		require
			item_in_text: a_item.start_index + a_item.count - 1 <= a_text.count
			size_positive: a_pixel_size > 0
			fonts_usable: not a_fonts.is_empty
		local
			l_choice: FALLBACK_CHOICE
			l_shaped: SHAPED_ITEM
			l_splits: ARRAY [BOOLEAN]
			l_from, k: INTEGER
		do
			if attached requested_font (a_text, a_item, a_pixel_size, a_fonts, a_effective) as al_requested then
				l_choice := font_fallback.font_for (a_text, a_item, al_requested, a_fonts)
				statistics.record_fallback_probes (l_choice.probes_performed)
				if not l_choice.is_complete_coverage then
						-- DR-010: nothing was dropped - the requested face's
						-- missing-glyph boxes render, and the reader is told.
					a_notes.extend (create {SHAPING_NOTE}.make (Note_fallback_exhausted,
						note_message ("No configured family covered this stretch; it renders as missing-glyph boxes of ",
						al_requested.family), a_item.start_index, a_item.count))
				end
				if l_choice.font.is_ready then
					l_shaped := glyph_shaper.shape (a_text, a_item, l_choice.font)
					statistics.record_shape_call
					if attached {DIRECTWRITE_GLYPH_SHAPER} glyph_shaper as al_native and then
						al_native.last_shape_was_synthesized
					then
							-- R3: the native call failed and the range came
							-- back as tofu-but-valid. Data, not an exception.
						a_notes.extend (create {SHAPING_NOTE}.make (Note_backend_error_recovered,
							note_message ("A native shaping call failed; this range was synthesized as missing-glyph boxes under ",
							l_choice.font.family), a_item.start_index, a_item.count))
					end
					l_splits := split_flags (a_text, a_item, l_shaped)
					l_from := 1
					from k := 2 until k > a_item.count loop
						if l_splits [k] then
							a_runs.extend (glyph_run_slice (a_item, l_shaped, l_from, k - 1,
								l_choice.font))
							l_from := k
						end
						k := k + 1
					end
					a_runs.extend (glyph_run_slice (a_item, l_shaped, l_from, a_item.count,
						l_choice.font))
				end
			else
					-- No family in either policy realizes on this machine at
					-- this size. Seam 3 and seam 4 both REQUIRE a realized
					-- font, so the honest answer is no runs and one note -
					-- the lines still partition the text (NFR-011).
				a_notes.extend (create {SHAPING_NOTE}.make (Note_fallback_exhausted,
					{STRING_32} "No configured family could be realized on this machine at this size; the range is unrendered.",
					a_item.start_index, a_item.count))
			end
		ensure
			runs_only_grow: a_runs.count >= old a_runs.count
			notes_only_grow: a_notes.count >= old a_notes.count
		end

	requested_font (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
			a_pixel_size: INTEGER; a_fonts, a_effective: FONT_LIST): detachable SHAPING_FONT
			-- [ADDED Phase 4 Task 11] The face the POLICY asks for on `a_item':
			-- the first family of the EFFECTIVE policy for the item's script
			-- class that this machine actually realizes, at the LAYOUT's
			-- `a_pixel_size' in the MVP style (R9: regular weight, upright).
			-- The configured policy is walked after the effective one purely
			-- as a backstop, for the degenerate case where R1 dropped every
			-- family of the class.
			--
			-- THE SCRIPT CLASS COMES FROM THE CHARACTERS (`script_class_of'),
			-- never from `SCRIPT_ITEM.script_code' - the engine's ids are
			-- opaque and backend-specific, while a policy bucket must mean the
			-- same thing on every backend.
			--
			-- REALIZING AT `a_pixel_size' IS WHAT CLOSES ISSUE 8. Seam 4
			-- preserves the REQUESTED font's size, and GLYPH_RUN.pixel_size is
			-- defined as its font's - so nothing below this line forces the
			-- run to be at the layout's size. This does.
			--
			-- Void ONLY when nothing realizes at all.
		require
			item_in_text: a_item.start_index + a_item.count - 1 <= a_text.count
			size_positive: a_pixel_size > 0
			fonts_usable: not a_fonts.is_empty
		local
			l_class, i: INTEGER
			l_candidates: ARRAYED_LIST [IMMUTABLE_STRING_32]
			l_font: SHAPING_FONT
		do
			l_class := script_class_of (a_text, a_item.start_index, a_item.count)
			create l_candidates.make (8)
			across a_effective.families_for (l_class) as f loop
				l_candidates.extend (f)
			end
			across a_fonts.families_for (l_class) as f loop
				l_candidates.extend (f)
			end
			from i := 1 until i > l_candidates.count or Result /= Void loop
				l_font := registry.font (l_candidates [i], {SHAPING_FONT}.Weight_regular,
					False, a_pixel_size)
				if l_font.is_ready then
					Result := l_font
				end
				i := i + 1
			end
		ensure
			realized_at_the_layout_size: attached Result as al_font implies
				(al_font.is_ready and al_font.pixel_size = a_pixel_size)
			mvp_style: attached Result as al_font implies
				(al_font.weight = {SHAPING_FONT}.Weight_regular and not al_font.is_italic)
		end

	split_flags (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
			a_shaped: SHAPED_ITEM): ARRAY [BOOLEAN]
			-- [ADDED Phase 4 Task 11] True at k = START A NEW RUN before the
			-- item's k-th character. A position qualifies only if ALL of:
			--   * the itemizer reported a soft break there (A-C07); and
			--   * it is a CLUSTER boundary in `a_shaped' - DR-007 forbids a
			--     break inside a base+mark cluster, and run granularity is how
			--     that becomes structurally impossible; and
			--   * the character it would START is not itself a breaking space
			--     (UAX #14: the opportunity is AFTER a space, never before
			--     one - a line must not begin with the space it broke at); and
			--   * what it would CLOSE is not made only of breaking spaces.
			--
			-- THE LAST TWO RULES ARE ALSO A WIDTH RULE. LINE_LAYOUT_ENGINE
			-- excludes a line-trailing whitespace RUN's advance from its fit
			-- test (R2, hanging whitespace) while `layout''s `width_respected'
			-- measures the line's RAW width - so a whitespace-ONLY run can
			-- make a line measure wider than the wrap width. Keeping the
			-- spaces inside their neighbour's run removes that possibility
			-- everywhere it is the facade's to remove; `wrapped_lines' handles
			-- what is left.
		require
			item_in_text: a_item.start_index + a_item.count - 1 <= a_text.count
			clusters_cover_item: a_shaped.clusters.count = a_item.count
		local
			l_soft: ARRAY [BOOLEAN]
			l_from, k: INTEGER
		do
			l_soft := script_itemizer.soft_breaks (a_text, a_item)
			create Result.make_filled (False, 1, a_item.count)
			l_from := 1
			from k := 2 until k > a_item.count loop
				if l_soft [l_soft.lower + k - 1]
					and then cluster_at (a_shaped, k) /= cluster_at (a_shaped, k - 1)
					and then not is_breaking_space (a_text.code (a_item.start_index + k - 1))
					and then not all_breaking_spaces (a_text, a_item.start_index + l_from - 1,
						k - l_from)
				then
					Result [k] := True
					l_from := k
				end
				k := k + 1
			end
		ensure
			one_flag_per_character: Result.count = a_item.count
			one_based: Result.lower = 1
			never_before_the_first: a_item.count > 0 implies not Result [1]
		end

	glyph_run_slice (a_item: SCRIPT_ITEM; a_shaped: SHAPED_ITEM;
			a_from, a_to: INTEGER; a_font: SHAPING_FONT): GLYPH_RUN
			-- [ADDED Phase 4 Task 11] Characters `a_from' .. `a_to' of `a_item'
			-- (1-based WITHIN the item) as one paint-ready run.
			--
			-- POSITIONS ARE CUMULATIVE, NOT OFFSETS. SHAPED_ITEM reports
			-- per-glyph ADVANCES plus mark OFFSETS; GLYPH_RUN promises
			-- run-relative, baseline-origin POSITIONS - which is
			-- cairo_glyph_t's x/y. The pen walks the advances and the offsets
			-- ride on top, so the paint side never re-measures (DR-009).
			--
			-- THE GLYPH WINDOW. `clusters' maps a character to the FIRST GLYPH
			-- of its cluster: ascending for an LTR item, DESCENDING for an RTL
			-- one, because the shaper already mirrored RTL runs into visual
			-- order. The window is therefore taken from the other end for RTL,
			-- and the copied map is rebased to this run's own 1-based glyph
			-- positions - which keeps GLYPH_RUN's `clusters_monotone'
			-- invariant true by construction rather than by luck.
		require
			slice_valid: a_from >= 1 and a_to >= a_from and a_to <= a_item.count
			clusters_cover_item: a_shaped.clusters.count = a_item.count
			font_sized: a_font.pixel_size > 0
		local
			l_lo, l_hi, l_glyphs, l_chars, i, j: INTEGER
			l_ids: ARRAY [NATURAL_32]
			l_x, l_y: ARRAY [REAL_64]
			l_clusters: ARRAY [INTEGER]
			l_pen, l_height: REAL_64
		do
			if a_item.is_rtl then
				l_lo := cluster_at (a_shaped, a_to)
				if a_from > 1 then
					l_hi := cluster_at (a_shaped, a_from - 1) - 1
				else
					l_hi := a_shaped.glyphs.count
				end
			else
				l_lo := cluster_at (a_shaped, a_from)
				if a_to < a_item.count then
					l_hi := cluster_at (a_shaped, a_to + 1) - 1
				else
					l_hi := a_shaped.glyphs.count
				end
			end
			l_lo := l_lo.max (1)
			l_hi := l_hi.min (a_shaped.glyphs.count)
			l_glyphs := (l_hi - l_lo + 1).max (0)
			l_chars := a_to - a_from + 1
			create l_ids.make_filled ({NATURAL_32} 0, 1, l_glyphs)
			create l_x.make_filled (0.0, 1, l_glyphs)
			create l_y.make_filled (0.0, 1, l_glyphs)
			from i := 1 until i > l_glyphs loop
				j := l_lo + i - 1
				l_ids [i] := a_shaped.glyphs [a_shaped.glyphs.lower + j - 1]
				l_x [i] := l_pen + a_shaped.x_offsets [a_shaped.x_offsets.lower + j - 1]
					-- DirectWrite's ascenderOffset is positive UPWARD; cairo (and
					-- GLYPH_RUN.y_positions, which are cairo_glyph_t.y) are y-DOWN.
					-- Negate at this one boundary (reported by the simple_widgets
					-- adoption; the bridge test's reference builder does the same).
				l_y [i] := - a_shaped.y_offsets [a_shaped.y_offsets.lower + j - 1]
				l_pen := l_pen + a_shaped.advances [a_shaped.advances.lower + j - 1]
				i := i + 1
			end
			create l_clusters.make_filled (1, 1, l_chars)
			from i := 1 until i > l_chars loop
				l_clusters [i] := (cluster_at (a_shaped, a_from + i - 1) - l_lo + 1).max (1)
				i := i + 1
			end
			if a_font.is_ready then
				l_height := a_font.ascent + a_font.descent
			else
					-- `unrealized_has_no_metrics': there is nothing to ask, so
					-- the run takes its own size and LINE_LAYOUT_ENGINE splits
					-- it by `Default_ascent_ratio'. Headless runs land here.
				l_height := a_font.pixel_size.to_double
			end
			create Result.make (a_item.start_index + a_from - 1, l_chars,
				a_item.embedding_level, a_font, l_ids, l_x, l_y, l_clusters,
				a_item.script_code, l_pen, l_height)
		ensure
			range_kept: Result.source_start = a_item.start_index + a_from - 1
				and Result.source_count = a_to - a_from + 1
			level_kept: Result.embedding_level = a_item.embedding_level
			same_n_rule: Result.pixel_size = a_font.pixel_size
			script_carried: Result.script_code = a_item.script_code
		end

	cluster_at (a_shaped: SHAPED_ITEM; a_character: INTEGER): INTEGER
			-- [ADDED Phase 4 Task 11] `a_shaped''s cluster entry for the item's
			-- `a_character'-th character, read through the array's OWN lower
			-- bound: the cluster map crosses a seam, and no seam promises a
			-- particular array base.
		require
			in_range: a_character >= 1 and a_character <= a_shaped.clusters.count
		do
			Result := a_shaped.clusters [a_shaped.clusters.lower + a_character - 1]
		end

	append_image_run (a_segment: TEXT_SEGMENT; a_box: REAL_64;
			a_runs: ARRAYED_LIST [SHAPED_RUN]; a_notes: ARRAYED_LIST [SHAPING_NOTE])
			-- [ADDED Phase 4 Task 11] ONE IMAGE_RUN for one RESOLVED emoji
			-- segment, square at the line height `a_box' and inheriting the
			-- segment's resolved level so RTL placement works (DR-006: the
			-- ladder already answered, so the run's `resolved' invariant is
			-- dischargeable here and nowhere else).
		require
			emoji: a_segment.is_emoji
			box_positive: a_box > 0.0
		do
			if not asset_still_resolves (a_segment) then
				a_notes.extend (create {SHAPING_NOTE}.make (Note_asset_missing,
					note_message ("The asset directory no longer answers for the file this sequence resolved to: ",
					a_segment.asset_path), a_segment.start_index, a_segment.count))
			end
			a_runs.extend (create {IMAGE_RUN}.make (a_segment.start_index, a_segment.count,
				a_segment.embedding_level, a_segment.codepoints, a_segment.asset_key,
				a_segment.asset_path, a_box, a_box))
		ensure
			exactly_one_more_run: a_runs.count = old a_runs.count + 1
		end

	asset_still_resolves (a_segment: TEXT_SEGMENT): BOOLEAN
			-- [ADDED Phase 4 Task 11] Does the catalog still answer for
			-- `a_segment''s sequence?
			--
			-- WHAT THIS IS AND IS NOT. DR-006 makes it True on every normal
			-- path: EMOJI_SEGMENTER only emits an emoji segment AFTER the
			-- catalog resolved it, so `Note_asset_missing' is a DEFENSIVE
			-- channel, reachable only when a catalog answers differently
			-- within one call than it did at segmentation (an injected probe
			-- that changes its mind, or a file removed under a running
			-- process). It is wired rather than left dead because a silent
			-- divergence between the catalog and the asset store is exactly
			-- the thing NFR-011 says must become data.
			--
			-- `has_asset' is a memo query (the declared CQS exception), so
			-- asking it here costs a hash lookup after the segmenter's own
			-- call and never a second disk probe.
		require
			emoji: a_segment.is_emoji
		do
			Result := not catalog.has_non_vs16 (a_segment.codepoints)
				or else catalog.has_asset (a_segment.codepoints)
		end

	wrapped_lines (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER;
			a_runs: ARRAYED_LIST [SHAPED_RUN]): ARRAYED_LIST [SHAPED_LINE]
			-- [ADDED Phase 4 Task 11] LINE_LAYOUT_ENGINE's wrap, plus the one
			-- reconciliation two live contracts need from each other.
			--
			-- R2 AGAINST `width_respected'. The engine EXCLUDES a
			-- line-trailing whitespace RUN's advance from its fit test - that
			-- is what "hanging whitespace" means and `fits_within' is the
			-- clause - while `SHAPED_LAYOUT.respects_width', which `layout'
			-- must ensure, measures the line's RAW width, trailing space
			-- included. A line can therefore fit by the engine's rule and
			-- still measure wider than the wrap width. `split_flags' removes
			-- the common source (a whitespace-only run manufactured INSIDE an
			-- item); what remains is a whitespace-only ITEM or SEGMENT, and
			-- for that this feature re-wraps ONCE at a width reduced by the
			-- widest consecutive whitespace-run group - which bounds every
			-- line's raw width by the ORIGINAL width, because the engine
			-- resets its hanging accumulator at the first ink run.
			--
			-- RESIDUAL, STATED RATHER THAN HIDDEN: when a single whitespace
			-- group is itself as wide as the whole wrap width, no partition
			-- the engine can produce respects that width - a hang that large
			-- hangs past the margin by definition. The retry then leaves the
			-- first wrap standing. Reported in the Phase 4 Task 11 evidence;
			-- no contract was touched to make it go away.
		require
			width_non_negative: a_width_pixels >= 0
			size_positive: a_pixel_size > 0
		local
			l_narrower: INTEGER
		do
			Result := layout_engine.build_lines (a_text, a_width_pixels, a_pixel_size,
				a_runs, bidi_resolver)
			if a_width_pixels > 0 and then not lines_respect_width (Result, a_width_pixels) then
				l_narrower := a_width_pixels
					- (widest_whitespace_group (a_text, a_runs).truncated_to_integer + 1)
				if l_narrower >= 1 then
					Result := layout_engine.build_lines (a_text, l_narrower, a_pixel_size,
						a_runs, bidi_resolver)
				end
			end
		ensure
			never_void: Result /= Void
			at_least_one_line: not Result.is_empty
			partition: lines_partition_text (Result, a_text.count)
		end

	lines_respect_width (a_lines: ARRAYED_LIST [SHAPED_LINE]; a_width_pixels: INTEGER): BOOLEAN
			-- [ADDED Phase 4 Task 11] Does every line of `a_lines' fit
			-- `a_width_pixels' or carry the overflow flag? The very predicate
			-- `SHAPED_LAYOUT.respects_width' will apply to the finished
			-- layout, asked one step earlier - while the answer can still
			-- change the wrap.
		require
			width_positive: a_width_pixels > 0
		do
			Result := True
			across a_lines as l loop
				Result := Result and (l.width <= a_width_pixels.to_double or l.is_overflowing)
			end
		end

	widest_whitespace_group (a_text: READABLE_STRING_32;
			a_runs: ARRAYED_LIST [SHAPED_RUN]): REAL_64
			-- [ADDED Phase 4 Task 11] The largest total advance of any
			-- CONSECUTIVE stretch of whitespace-only runs in `a_runs' - an
			-- upper bound on a line's hanging suffix, because
			-- LINE_LAYOUT_ENGINE resets its accumulator at the first ink run.
		local
			l_current: REAL_64
			i: INTEGER
		do
			from i := 1 until i > a_runs.count loop
				if is_whitespace_run (a_text, a_runs [i]) then
					l_current := l_current + a_runs [i].advance_width
					Result := Result.max (l_current)
				else
					l_current := 0.0
				end
				i := i + 1
			end
		ensure
			non_negative: Result >= 0.0
		end

	is_whitespace_run (a_text: READABLE_STRING_32; a_run: SHAPED_RUN): BOOLEAN
			-- [ADDED Phase 4 Task 11] Would LINE_LAYOUT_ENGINE count `a_run' as
			-- hanging whitespace (R2)? The engine's own predicate is private to
			-- it, so the rule is restated here - including that an IMAGE_RUN
			-- never is, exactly as there. The two MUST agree; if one is ever
			-- changed the other is changed with it.
		do
			if attached {IMAGE_RUN} a_run then
				Result := False
			elseif a_run.source_start >= 1
				and then a_run.source_start + a_run.source_count - 1 <= a_text.count
			then
				Result := all_breaking_spaces (a_text, a_run.source_start, a_run.source_count)
			end
		end

	all_breaking_spaces (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): BOOLEAN
			-- [ADDED Phase 4 Task 11] Is EVERY character of
			-- `a_text' [`a_start' .. `a_start' + `a_count' - 1] a breaking
			-- space, so a run over it would hang rather than measure (R2)?
		require
			range_valid: a_start >= 1 and a_count >= 1
				and a_start + a_count - 1 <= a_text.count
		local
			i: INTEGER
		do
			Result := True
			from i := a_start until i > a_start + a_count - 1 or not Result loop
				Result := is_breaking_space (a_text.code (i))
				i := i + 1
			end
		end

	is_breaking_space (a_code: NATURAL_32): BOOLEAN
			-- [ADDED Phase 4 Task 11] Is `a_code' a space at which a line MAY
			-- break? The non-breaking spaces are deliberately absent: NBSP
			-- (00A0), FIGURE SPACE (2007) and NARROW NO-BREAK SPACE (202F)
			-- exist precisely to forbid the break this predicate authorizes.
			-- Spelled exactly as LINE_LAYOUT_ENGINE spells it, for the reason
			-- `is_whitespace_run' gives.
		local
			l_code: INTEGER
		do
			l_code := a_code.to_integer_32
			Result := l_code = 32 or (l_code >= 9 and l_code <= 13)
				or l_code = 5760 or l_code = 8232 or l_code = 8233
				or l_code = 8287 or l_code = 12288
				or (l_code >= 8192 and l_code <= 8202 and l_code /= 8199)
		ensure
			plain_space_breaks: a_code.to_integer_32 = 32 implies Result
			no_break_space_does_not: a_code.to_integer_32 = 160 implies not Result
		end

	drain_family_notes (a_notes: ARRAYED_LIST [SHAPING_NOTE])
			-- [ADDED Phase 4 Task 11] Move R1's pending `Note_family_missing'
			-- records onto this layout and empty the pending list.
			--
			-- Task 2 PARKED them rather than charging them at probe time
			-- because `line_height' and `set_default_fonts' both promise
			-- `statistics_untouched' and both reach the probe through
			-- `effective_digest'. A layout is where the reader is finally
			-- told - and told ONCE per family per facade lifetime (R1), which
			-- is why the list is wiped as it is drained rather than copied.
		do
			across pending_family_notes as n loop
				a_notes.extend (n)
			end
			pending_family_notes.wipe_out
		ensure
			drained: pending_family_notes.is_empty
			carried: a_notes.count = old a_notes.count + old pending_family_notes.count
		end

	primary_line_height (a_pixel_size: INTEGER; a_fonts: FONT_LIST): REAL_64
			-- [ADDED Phase 4 Task 11] Q8's answer, shared by `line_height' and
			-- by the emoji box: ascent + descent of the FIRST REALIZED family
			-- of `a_fonts''s GENERAL list at `a_pixel_size', or `a_pixel_size'
			-- itself when this machine realizes none of them.
			--
			-- The general list, not `families_for': `line_height' is the
			-- empty-message minimum (FR-N01), and an empty message has no
			-- script to bucket by. The script prepends exist to rescue
			-- CHARACTERS, and there are none here.
			--
			-- Touches no counter and no cache entry, which is exactly what
			-- lets `line_height' keep `statistics_untouched' and
			-- `cache_untouched' while still asking the machine.
		require
			size_positive: a_pixel_size > 0
		local
			l_names: MML_SEQUENCE [IMMUTABLE_STRING_32]
			l_font: SHAPING_FONT
			i: INTEGER
			l_found: BOOLEAN
		do
			Result := a_pixel_size.to_double
			l_names := a_fonts.families_model
			from i := 1 until i > l_names.count or l_found loop
				l_font := registry.font (l_names [i], {SHAPING_FONT}.Weight_regular,
					False, a_pixel_size)
				if l_font.is_ready then
					Result := l_font.ascent + l_font.descent
					l_found := True
				end
				i := i + 1
			end
		ensure
			positive: Result > 0.0
		end

	note_message (a_prefix: READABLE_STRING_8; a_detail: READABLE_STRING_GENERAL): STRING_32
			-- [ADDED Phase 4 Task 11] `a_prefix' followed by `a_detail', in the
			-- STRING_32 SHAPING_NOTE keeps.
		require
			prefix_not_empty: not a_prefix.is_empty
		do
			create Result.make (a_prefix.count + a_detail.count)
			Result.append_string_general (a_prefix)
			Result.append_string_general (a_detail)
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
