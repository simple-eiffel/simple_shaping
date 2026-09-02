note
	description: "[
		One visual line: runs stored in VISUAL (left-to-right paint) order
		after UAX #9 L2 reordering; the logical source range is contiguous.
		`width` is the sum of run advances BY CONSTRUCTION (computed here,
		once, from the runs handed in).

		Baseline placement: draw at y_top + ascent.
		Immutable value; the invariant is the frame.
	]"
	author: "Larry Rix"

class
	SHAPED_LINE

inherit
	SHAPING_CONSTANTS

create
	make

feature {NONE} -- Initialization

	make (a_runs: ARRAYED_LIST [SHAPED_RUN]; a_source_start, a_source_count: INTEGER;
			a_height, a_ascent: REAL_64; a_overflowing: BOOLEAN)
			-- One line whose runs (VISUAL order) are `a_runs`, covering logical
			-- characters `a_source_start` .. `a_source_start + a_source_count - 1`.
			-- Empty `a_runs` with `a_source_count` >= 0 is the FR-N01 empty line.
		require
			range_valid: a_source_start >= 1 and a_source_count >= 0
			metrics_sane: a_height > 0.0 and a_ascent > 0.0 and a_ascent <= a_height
			overflow_only_when_unbreakable: a_overflowing implies a_runs.count = 1
		do
			runs := a_runs
			source_start := a_source_start
			source_count := a_source_count
			height := a_height
			ascent := a_ascent
			is_overflowing := a_overflowing
			width := sum_of_run_advances
		ensure
			runs_kept: runs = a_runs
			range_set: source_start = a_source_start and source_count = a_source_count
			metrics_set: height = a_height and ascent = a_ascent
			overflow_kept: is_overflowing = a_overflowing
			width_computed: width = sum_of_run_advances
		end

feature -- Access

	runs: ARRAYED_LIST [SHAPED_RUN]
			-- Runs in VISUAL order (post-reorder; paint left to right).

	source_start: INTEGER
			-- First logical character of this line (1-based).

	source_count: INTEGER
			-- Number of logical characters (0 only for the empty-text line, FR-N01).

	width: REAL_64
			-- Sum of run advance widths.

	height: REAL_64
			-- Line height (>= ascent + descent of the tallest run's font).

	ascent: REAL_64
			-- Baseline offset from the line top.

	is_overflowing: BOOLEAN
			-- Single unbreakable cluster/image wider than the wrap width?

	sum_of_run_advances: REAL_64
			-- Fold of `runs` advance widths, in order.
		do
			across runs as r loop
				Result := Result + r.advance_width
			end
		ensure
			non_negative: Result >= 0.0
		end

feature -- Model queries (simple_mml)

	runs_model: MML_SEQUENCE [SHAPED_RUN]
			-- Runs as a mathematical sequence (visual order).
		do
			create Result
			across runs as r loop
				Result := Result & r
			end
		ensure
			same_count: Result.count = runs.count
		end

feature -- Future (FR-013; names reserved, NOT compiled this cycle)

	-- character_index_at_x (a_x: REAL_64): INTEGER
	--     Hit-testing for SW_TEXT_BOX (ScriptXtoCP-class). Reserved.
	-- x_at_character_index (a_index: INTEGER): REAL_64
	--     Caret placement (ScriptCPtoX-class). Reserved.

invariant
	runs_visual_order_by_construction: True
		-- Runs are stored post-reorder; the permutation itself is checked at
		-- build time against BIDI_RESOLVER.reorder's contract (DR-002).
	metrics_sane: height > 0.0 and ascent > 0.0 and ascent <= height
	width_is_run_sum: width = sum_of_run_advances
	source_range_valid: source_start >= 1 and source_count >= 0
	overflow_only_when_unbreakable: is_overflowing implies runs.count = 1

end
