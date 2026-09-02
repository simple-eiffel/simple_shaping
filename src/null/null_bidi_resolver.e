note
	description: "[
		Headless test double for seam 1 (UC-005/AC-7): every level equals the
		paragraph level (0 unless Direction_rtl is forced); reorder is the
		identity permutation for an LTR line and the full reversal for an
		all-RTL one. Zero native calls - CI-safe on any machine.

		Doubles may STRENGTHEN the seam's ensure and WEAKEN its require,
		never the reverse (I-001); this one strengthens: auto detection
		always answers LTR.

		Phase 2 (ISSUE 13) added `rtl_reversal' to the seam, so "reorder is
		ALWAYS the identity" became unlawful for a forced-RTL line (every
		level 1). The double now honors L2 for the two cases the seam
		names - all-even and all-odd - and stays identity for anything
		mixed, which no seam clause constrains.
	]"
	author: "Larry Rix"

class
	NULL_BIDI_RESOLVER

inherit
	BIDI_RESOLVER

feature -- Operations

	resolve (a_text: READABLE_STRING_32; a_base_direction: INTEGER): BIDI_RESULT
			-- <Precursor>
		local
			l_levels: ARRAY [NATURAL_8]
			l_paragraph: NATURAL_8
		do
			if a_base_direction = Direction_rtl then
				l_paragraph := 1
			else
				l_paragraph := 0
			end
			create l_levels.make_filled (l_paragraph, 1, a_text.count)
			create Result.make (l_levels, l_paragraph)
		ensure then
			auto_is_ltr: a_base_direction = Direction_auto implies Result.paragraph_level = 0
		end

	reorder (a_levels: ARRAY [NATURAL_8]): ARRAY [INTEGER]
			-- <Precursor>
		local
			i: INTEGER
		do
			create Result.make_filled (0, 1, a_levels.count)
			if a_levels.count > 0 and then is_all_odd (a_levels) then
				from i := 1 until i > a_levels.count loop
					Result [i] := a_levels.count - i + 1
					i := i + 1
				end
			else
				from i := 1 until i > a_levels.count loop
					Result [i] := i
					i := i + 1
				end
			end
		ensure then
			identity_when_ltr: is_all_even (a_levels) implies is_identity (Result)
			reversal_when_rtl: (a_levels.count > 0 and is_all_odd (a_levels))
				implies is_reversal (Result)
		end

end
