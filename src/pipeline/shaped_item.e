note
	description: "[
		The shaper's raw output for one SCRIPT_ITEM under one font, before
		line placement: glyph ids, advances, offsets, cluster map, and the
		missing-glyph count that doubles as the fallback probe's verdict
		(seam 4 probes BY shaping, G2).

		.notdef is glyph id 0 (spike-measured: Segoe UI shaped the emoji's
		surrogates to id 0 between valid ids). `is_complete' means zero
		missing glyphs. NO glyph-count upper bound is promised: the 1.5n+16
		figure is buffer guidance, not an invariant (A-C02).

		Immutable value produced by seam GLYPH_SHAPER.
	]"
	author: "Larry Rix"

class
	SHAPED_ITEM

inherit
	SHAPING_CONSTANTS

create
	make

feature {NONE} -- Initialization

	make (a_font: SHAPING_FONT; a_source_count: INTEGER;
			a_glyphs: ARRAY [NATURAL_32]; a_advances: ARRAY [REAL_64];
			a_x_offsets, a_y_offsets: ARRAY [REAL_64];
			a_clusters: ARRAY [INTEGER]; a_missing_glyph_count: INTEGER)
			-- Shaper output for `a_source_count' characters under `a_font'.
		require
			source_positive: a_source_count > 0
			advances_match_glyphs: a_advances.count = a_glyphs.count
			offsets_match_glyphs: a_x_offsets.count = a_glyphs.count
				and a_y_offsets.count = a_glyphs.count
			cluster_per_character: a_clusters.count = a_source_count
			missing_sane: a_missing_glyph_count >= 0
		do
			font := a_font
			source_count := a_source_count
			glyphs := a_glyphs
			advances := a_advances
			x_offsets := a_x_offsets
			y_offsets := a_y_offsets
			clusters := a_clusters
			missing_glyph_count := a_missing_glyph_count
		ensure
			font_kept: font = a_font
			source_kept: source_count = a_source_count
			glyphs_kept: glyphs = a_glyphs
			missing_kept: missing_glyph_count = a_missing_glyph_count
		end

feature -- Access

	font: SHAPING_FONT
			-- The font this item was shaped under.

	source_count: INTEGER
			-- Characters covered.

	glyphs: ARRAY [NATURAL_32]
			-- Physical glyph indices (0 = .notdef).

	advances: ARRAY [REAL_64]
			-- Per-glyph advances at `font.pixel_size' (same-N, DR-009).

	x_offsets: ARRAY [REAL_64]
			-- Per-glyph x offsets (mark positioning).

	y_offsets: ARRAY [REAL_64]
			-- Per-glyph y offsets (mark positioning).

	clusters: ARRAY [INTEGER]
			-- Source character -> first glyph of its cluster (1-based).

	missing_glyph_count: INTEGER
			-- How many characters lacked coverage (the probe verdict).

	advance_sum: REAL_64
			-- Fold of `advances', in order.
		local
			i: INTEGER
		do
			from i := advances.lower until i > advances.upper loop
				Result := Result + advances [i]
				i := i + 1
			end
		end

feature -- Status

	is_complete: BOOLEAN
			-- Did every character find a glyph?
		do
			Result := missing_glyph_count = 0
		ensure
			complete_meaning: Result = (missing_glyph_count = 0)
		end

	clusters_in_range: BOOLEAN
			-- Does every cluster entry reference a real glyph position
			-- (guarded for glyph-less items)?
		local
			i: INTEGER
		do
			Result := True
			from i := clusters.lower until i > clusters.upper or not Result loop
				Result := clusters [i] >= 1 and clusters [i] <= glyphs.count.max (1)
				i := i + 1
			end
		end

feature -- Model queries (simple_mml)

	glyphs_model: MML_SEQUENCE [NATURAL_32]
			-- Glyphs as a mathematical sequence.
		local
			i: INTEGER
		do
			create Result
			from i := glyphs.lower until i > glyphs.upper loop
				Result := Result & glyphs [i]
				i := i + 1
			end
		ensure
			same_count: Result.count = glyphs.count
		end

	advances_model: MML_SEQUENCE [REAL_64]
			-- Advances as a mathematical sequence.
		local
			i: INTEGER
		do
			create Result
			from i := advances.lower until i > advances.upper loop
				Result := Result & advances [i]
				i := i + 1
			end
		ensure
			same_count: Result.count = advances.count
		end

	clusters_model: MML_SEQUENCE [INTEGER]
			-- Cluster map as a mathematical sequence.
		local
			i: INTEGER
		do
			create Result
			from i := clusters.lower until i > clusters.upper loop
				Result := Result & clusters [i]
				i := i + 1
			end
		ensure
			same_count: Result.count = clusters.count
		end

invariant
	source_positive: source_count > 0
	advances_match: advances.count = glyphs.count
	offsets_match: x_offsets.count = glyphs.count and y_offsets.count = glyphs.count
	cluster_per_character: clusters.count = source_count
	missing_non_negative: missing_glyph_count >= 0

end
