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
			create {LIST_FONT_FALLBACK} font_fallback.make (default_fonts, glyph_shaper, registry)
			create catalog.make_without_assets (a_asset_directory, tables)
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
			create catalog.make_without_assets (a_asset_directory, tables)
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
			l_key: STRING_8
			l_lines: ARRAYED_LIST [SHAPED_LINE]
			l_notes: ARRAYED_LIST [SHAPING_NOTE]
		do
			l_key := cache_key (a_text, a_width_pixels, a_pixel_size, a_fonts)
			if attached cache.item_verified (l_key, a_text, a_width_pixels, a_pixel_size) as al_hit then
				statistics.record_cache_hit
				Result := al_hit
			else
				statistics.record_cache_miss
				-- Phase 4: the real pipeline through the seams, with
				-- base direction from bidi's first-strong resolution and
				-- statistics.record_shape_call per run-producing shape (R7).
				-- Phase 1 degenerate total-function result: one line covering
				-- every character, zero runs, placeholder metrics.
				l_lines := layout_engine.build_lines (a_text, a_width_pixels, a_pixel_size,
					create {ARRAYED_LIST [SHAPED_RUN]}.make (0), bidi_resolver)
				create l_notes.make (0)
				create Result.make (a_text, a_width_pixels, a_pixel_size, Direction_ltr, l_lines, l_notes)
				cache.put (l_key, Result)
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
		require
			size_positive: a_pixel_size > 0
			fonts_usable: not a_fonts.is_empty
		do
			Result := layout (a_text, No_wrap, a_pixel_size, a_fonts).lines.first.width
		ensure
			non_negative: Result >= 0.0
			empty_is_zero: a_text.is_empty implies Result = 0.0
			whitespace_measures: a_text.count > 0 implies Result >= 0.0
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

	set_default_fonts (a_fonts: FONT_LIST): like Current
			-- Use `a_fonts' for `layout_default'.
		require
			fonts_usable: not a_fonts.is_empty
		do
			default_fonts := a_fonts
			Result := Current
		ensure
			set: default_fonts ~ a_fonts
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
			create catalog.make_without_assets (a_path, tables)
			create segmenter.make (tables, catalog)
			cache.wipe
			Result := Current
		ensure
			set: asset_directory.same_string_general (a_path)
			chaining: Result = Current
			cache_cleared: cache_count = 0
			cache_model_empty: cache_model.is_empty
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
				a_text, a_width_pixels, a_pixel_size)
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

	registry: FONT_REGISTRY
			-- This processor's font ownership (DR-012).

	cache: LAYOUT_CACHE
			-- The FR-012 layout cache.

	layout_engine: LINE_LAYOUT_ENGINE
			-- Wrap + reorder + metrics.

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
		ensure
			cache_empty: cache_count = 0
			statistics_zero: statistics.shape_calls = 0
			defaults_present: not default_fonts.is_empty
		end

	cache_key (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER;
			a_fonts: FONT_LIST): STRING_8
			-- Digest of the full layout identity (R5: fonts digest is over
			-- the effective list; R8 makes collisions harmless).
		local
			l_utf: UTF_CONVERTER
		do
			create Result.make (a_text.count + 48)
			Result.append (a_fonts.digest)
			Result.append_character ('|')
			Result.append_integer (a_width_pixels)
			Result.append_character ('|')
			Result.append_integer (a_pixel_size)
			Result.append_character ('|')
			Result.append (l_utf.utf_32_string_to_utf_8_string_8 (asset_directory))
			Result.append_character ('|')
			Result.append (l_utf.utf_32_string_to_utf_8_string_8 (a_text))
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
