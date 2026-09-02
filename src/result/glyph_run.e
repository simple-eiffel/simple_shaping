note
	description: "[
		Positioned glyphs of ONE font at ONE pixel size in ONE direction,
		paint-ready: `glyph_ids' are the physical glyph indices of `font''s
		HFONT - exactly cairo_glyph_t.index space for the face from
		cairo_win32_font_face_create_for_logfontw_hfont (verified bridge,
		D-S03). Positions are run-relative, baseline origin, and
		SHAPER-AUTHORITATIVE at `font.pixel_size' (same-N rule, DR-009):
		the paint side must set_font_size (font.pixel_size) on the same face
		and must not re-measure.

		Immutable value. Arrays are handed over frozen at construction and
		must never be mutated afterwards (Phase 4 ingests via twins).
	]"
	author: "Larry Rix"

class
	GLYPH_RUN

inherit
	SHAPED_RUN

create
	make

feature {NONE} -- Initialization

	make (a_source_start, a_source_count: INTEGER; a_level: NATURAL_8;
			a_font: SHAPING_FONT; a_glyph_ids: ARRAY [NATURAL_32];
			a_x_positions, a_y_positions: ARRAY [REAL_64];
			a_cluster_map: ARRAY [INTEGER]; a_script_code: INTEGER;
			a_advance_width, a_height: REAL_64)
			-- One shaped run over paragraph characters
			-- `a_source_start' .. `a_source_start' + `a_source_count' - 1.
		require
			range_valid: a_source_start >= 1 and a_source_count > 0
			level_bounded: a_level <= Max_bidi_level
			arrays_aligned: a_glyph_ids.count = a_x_positions.count
				and a_x_positions.count = a_y_positions.count
			cluster_per_source_char: a_cluster_map.count = a_source_count
			advance_non_negative: a_advance_width >= 0.0
			height_positive: a_height > 0.0
		do
			source_start := a_source_start
			source_count := a_source_count
			embedding_level := a_level
			font := a_font
			glyph_ids := a_glyph_ids
			x_positions := a_x_positions
			y_positions := a_y_positions
			cluster_map := a_cluster_map
			script_code := a_script_code
			advance_width := a_advance_width
			height := a_height
		ensure
			font_kept: font = a_font
			glyphs_kept: glyph_ids = a_glyph_ids
			range_set: source_start = a_source_start and source_count = a_source_count
			level_set: embedding_level = a_level
		end

feature -- Access

	source_start: INTEGER
			-- <Precursor>

	source_count: INTEGER
			-- <Precursor>

	embedding_level: NATURAL_8
			-- <Precursor>

	advance_width: REAL_64
			-- <Precursor>

	height: REAL_64
			-- <Precursor>

	font: SHAPING_FONT
			-- The realized font that shaped this run (possibly a fallback
			-- face; the run reports the TRUE renderer - AC-4).

	glyph_ids: ARRAY [NATURAL_32]
			-- Physical glyph indices (cairo_glyph_t.index space).

	x_positions: ARRAY [REAL_64]
			-- Per-glyph x, run-relative, baseline origin.

	y_positions: ARRAY [REAL_64]
			-- Per-glyph y, run-relative, baseline origin.

	cluster_map: ARRAY [INTEGER]
			-- Source character -> first glyph of its cluster (1-based glyph
			-- indices; monotone: non-decreasing LTR, non-increasing RTL, DR-004).

	script_code: INTEGER
			-- ENGINE-INTERNAL OPAQUE script id, carried verbatim from the
			-- itemizer that produced this run's item. NEVER compare across
			-- backends and never persist: DirectWrite numbered the spike's
			-- Hebrew/Greek/Latin runs 36/30/49; Uniscribe numbers differently;
			-- neither is ISO 15924.

	pixel_size: INTEGER
			-- The size this run was shaped at - BY DEFINITION the font's
			-- (same-N rule, DR-009: positions are valid only at this size).
		do
			Result := font.pixel_size
		ensure
			same_n_rule: Result = font.pixel_size
		end

feature -- Model queries (simple_mml)

	glyphs_model: MML_SEQUENCE [NATURAL_32]
			-- Glyph ids as a mathematical sequence.
		local
			i: INTEGER
		do
			create Result
			from i := glyph_ids.lower until i > glyph_ids.upper loop
				Result := Result & glyph_ids [i]
				i := i + 1
			end
		ensure
			same_count: Result.count = glyph_ids.count
		end

	clusters_model: MML_SEQUENCE [INTEGER]
			-- Cluster map as a mathematical sequence.
		local
			i: INTEGER
		do
			create Result
			from i := cluster_map.lower until i > cluster_map.upper loop
				Result := Result & cluster_map [i]
				i := i + 1
			end
		ensure
			same_count: Result.count = cluster_map.count
		end

invariant
	arrays_aligned: glyph_ids.count = x_positions.count
		and x_positions.count = y_positions.count
	cluster_per_source_char: cluster_map.count = source_count
	clusters_monotone: (is_rtl implies is_non_increasing (clusters_model))
		and (not is_rtl implies is_non_decreasing (clusters_model))

end
