note
	description: "[
		MVP effecting of seam 3 (G1 FINAL). Phase 4 effects `shape' with
		IDWriteTextAnalyzer.GetGlyphs (vtable slot 7) + GetGlyphPlacements
		(slot 8) over the IDWriteFontFace from GdiInterop.CreateFontFaceFromHdc
		(slot 6) on the SHAPING_FONT's memory HDC - the exact chain the spike
		PROVED: Segoe UI at em 16 px shaped shalom to 4 glyphs (ids
		2945/2932/2925/2933) with positive advances (12.55/8.81/4.29/11.10)
		and identity cluster map; .notdef came back as glyph id 0
		(spikes/dwrite/run_output.txt, check A3 PASS). Em size = pixel_size
		(same-N, D-S03); isRightToLeft = item level parity; the item's
		DWRITE_SCRIPT_ANALYSIS bytes are passed back verbatim from
		SCRIPT_ITEM.analysis.

		Missing-glyph counting (the G2 probe verdict): count characters whose
		cluster's glyphs are all id 0. On a hard HRESULT failure: R3's
		tofu-but-valid synthesis (id 0 per character, advance pixel_size/2,
		identity clusters) - never an empty item, never a raise.

		UNISCRIBE_GLYPH_SHAPER (ScriptShape + ScriptPlace + SCRIPT_CACHE) is
		the named alternate slot - it does not exist yet.

		The Phase-1 body IS the R3 tofu synthesis (satisfies every seam
		contract; visibly boxes until Phase 4 lands real shaping).
	]"
	author: "Larry Rix"

class
	DIRECTWRITE_GLYPH_SHAPER

inherit
	GLYPH_SHAPER

create
	make

feature {NONE} -- Initialization

	make
			-- Wire the native surface.
		do
			create api.make
		end

feature -- Operations

	shape (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM; a_font: SHAPING_FONT): SHAPED_ITEM
			-- <Precursor>
		local
			i, n: INTEGER
			l_glyphs: ARRAY [NATURAL_32]
			l_advances, l_x, l_y: ARRAY [REAL_64]
			l_clusters: ARRAY [INTEGER]
		do
			-- Phase 4: GetGlyphs + GetGlyphPlacements through `api' (grow
			-- buffers on E_OUTOFMEMORY per A-C02 guidance, 3 attempts, then
			-- the synthesis below as the R3 last resort).
			n := a_item.count
			create l_glyphs.make_filled (0, 1, n)
			create l_advances.make_filled (a_font.pixel_size / 2, 1, n)
			create l_x.make_filled (0.0, 1, n)
			create l_y.make_filled (0.0, 1, n)
			create l_clusters.make_filled (0, 1, n)
			from i := 1 until i > n loop
				if a_item.is_rtl then
					l_clusters [i] := n - i + 1
				else
					l_clusters [i] := i
				end
				i := i + 1
			end
			create Result.make (a_font, n, l_glyphs, l_advances, l_x, l_y, l_clusters, n)
		end

feature {NONE} -- Implementation

	api: DWRITE_API
			-- The one native surface (single-translation-unit rule).

end
