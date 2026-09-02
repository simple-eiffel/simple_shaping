note
	description: "[
		Seam 3 of four (C-006/D-014): the characters of one SCRIPT_ITEM plus
		one realized font -> a SHAPED_ITEM (glyphs, advances, offsets,
		cluster map, missing-glyph count).

		NEVER RAISES: coverage gaps are COUNTED, not thrown - the count is the
		probe verdict FONT_FALLBACK leans on (G2 probes by shaping). Hard
		native failures degrade to R3's tofu-but-valid synthesis: glyph id 0
		per character, advance pixel_size/2, identity clusters, plus
		Note_backend_error_recovered upstream - never an empty item for a
		non-empty range, never a dropped range.

		NO glyph-count upper bound is promised: 1.5n+16 is first-allocation
		guidance with a grow-and-retry loop, not an invariant (A-C02).

		Shaping runs at `a_font.pixel_size' (same-N, D-S03/DR-009): positions
		are authoritative at that size and the paint side must not re-measure.

		Backends: DIRECTWRITE_GLYPH_SHAPER (MVP, G1 final: GetGlyphs +
		GetGlyphPlacements through the spikes/dwrite C-vtable shim);
		UNISCRIBE_GLYPH_SHAPER (ScriptShape + ScriptPlace) named alternate -
		does not exist yet; NULL_ double (metric-predictable, headless).
	]"
	author: "Larry Rix"
	never_raises: "No exception propagates from any seam feature; failures degrade per NFR-011."

deferred class
	GLYPH_SHAPER

inherit
	SHAPING_CONSTANTS

feature -- Operations

	shape (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM; a_font: SHAPING_FONT): SHAPED_ITEM
			-- Shape and place `a_item''s characters under `a_font' at the
			-- font's pixel size.
		require
			item_in_text: a_item.start_index + a_item.count - 1 <= a_text.count
			font_ready: a_font.is_ready
		deferred
		ensure
			never_void: Result /= Void
			cluster_per_character: Result.clusters_model.count = a_item.count
			clusters_valid: Result.clusters_in_range
			clusters_monotone_ltr: not a_item.is_rtl implies is_non_decreasing (Result.clusters_model)
			clusters_monotone_rtl: a_item.is_rtl implies is_non_increasing (Result.clusters_model)
			advances_match: Result.advances_model.count = Result.glyphs_model.count
			advances_non_negative: Result.advances_model.for_all (agent non_negative)
			complete_meaning: Result.is_complete = (Result.missing_glyph_count = 0)
			font_recorded: Result.font = a_font
		end

end
