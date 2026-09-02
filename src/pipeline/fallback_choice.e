note
	description: "[
		Seam-4 result pair: the chosen rendering font plus the
		coverage-completeness verdict. Keeps FONT_FALLBACK CQS-clean (a value
		instead of an out-parameter, 05).

		DR-010 reading: is_complete_coverage = False is only ever paired with
		the REQUESTED font (tofu boxes + a note upstream) - something ALWAYS
		renders, nothing is silently dropped.

		Immutable value.
	]"
	author: "Larry Rix"

class
	FALLBACK_CHOICE

create
	make

feature {NONE} -- Initialization

	make (a_font: SHAPING_FONT; a_complete: BOOLEAN)
			-- Choice of `a_font' with completeness `a_complete'.
		do
			font := a_font
			is_complete_coverage := a_complete
		ensure
			font_kept: font = a_font
			verdict_kept: is_complete_coverage = a_complete
		end

feature -- Access

	font: SHAPING_FONT
			-- The font the item should render with.

	is_complete_coverage: BOOLEAN
			-- Does `font' cover every character of the item?

end
