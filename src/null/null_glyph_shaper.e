note
	description: "[
		Headless test double for seam 3 (UC-005/AC-7): one glyph per
		character, glyph id = the character's code point, advance =
		pixel_size / 2, zero offsets, monotone clusters, complete coverage.
		Metric-predictable: a k-character item under size N measures exactly
		k * N / 2 - wrap and measurement tests assert against that.

		WEAKENED require (lawful for a double): the font need NOT be
		realized - headless tests run with unrealized SHAPING_FONTs and zero
		native calls. The range condition stays.
	]"
	author: "Larry Rix"

class
	NULL_GLYPH_SHAPER

inherit
	GLYPH_SHAPER

feature -- Operations

	shape (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM; a_font: SHAPING_FONT): SHAPED_ITEM
			-- <Precursor>
		require else
			headless_fonts_allowed: a_item.start_index + a_item.count - 1 <= a_text.count
		local
			i, n: INTEGER
			l_glyphs: ARRAY [NATURAL_32]
			l_advances, l_x, l_y: ARRAY [REAL_64]
			l_clusters: ARRAY [INTEGER]
		do
			n := a_item.count
			create l_glyphs.make_filled (0, 1, n)
			create l_advances.make_filled (a_font.pixel_size / 2, 1, n)
			create l_x.make_filled (0.0, 1, n)
			create l_y.make_filled (0.0, 1, n)
			create l_clusters.make_filled (0, 1, n)
			from i := 1 until i > n loop
				l_glyphs [i] := a_text.code (a_item.start_index + i - 1)
				if a_item.is_rtl then
					l_clusters [i] := n - i + 1
				else
					l_clusters [i] := i
				end
				i := i + 1
			end
			create Result.make (a_font, n, l_glyphs, l_advances, l_x, l_y, l_clusters, 0)
		ensure then
			one_glyph_per_character: Result.glyphs_model.count = a_item.count
			always_complete: Result.is_complete
		end

end
