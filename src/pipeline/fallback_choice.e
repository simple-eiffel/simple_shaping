note
	description: "[
		Seam-4 result pair: the chosen rendering font plus the
		coverage-completeness verdict. Keeps FONT_FALLBACK CQS-clean (a value
		instead of an out-parameter, 05).

		DR-010 reading: is_complete_coverage = False is only ever paired with
		the REQUESTED font (tofu boxes + a note upstream) - something ALWAYS
		renders, nothing is silently dropped.

		R7 AMENDED (Phase 2 / ISSUE 7): the choice also carries
		`probes_performed' - how many coverage SHAPES the walk ran to reach
		this answer. R7 bound probe counting to "the calling engine", but the
		walk-and-probe loop lives inside LIST_FONT_FALLBACK and the caller
		sees only this value, so fallback_probes could never be incremented
		correctly. The count now rides home here: the facade adds it into
		statistics.fallback_probes, seam DOUBLES return 0 (they probe
		nothing), and no counting duty enters an effecting.

		Immutable value.
	]"
	author: "Larry Rix"

class
	FALLBACK_CHOICE

create
	make

feature {NONE} -- Initialization

	make (a_font: SHAPING_FONT; a_complete: BOOLEAN; a_probes: INTEGER)
			-- Choice of `a_font' with completeness `a_complete', reached at
			-- the cost of `a_probes' coverage shapes (R7).
		require
			probes_non_negative: a_probes >= 0
		do
			font := a_font
			is_complete_coverage := a_complete
			probes_performed := a_probes
		ensure
			font_kept: font = a_font
			verdict_kept: is_complete_coverage = a_complete
			probes_kept: probes_performed = a_probes
		end

feature -- Access

	font: SHAPING_FONT
			-- The font the item should render with.

	is_complete_coverage: BOOLEAN
			-- Does `font' cover every character of the item?

	probes_performed: INTEGER
			-- Coverage SHAPES this answer cost (R7 amended; 0 from every
			-- seam double - they probe nothing). The facade adds this into
			-- statistics.fallback_probes; nothing counts inside an effecting.

invariant
	probes_non_negative: probes_performed >= 0

end
