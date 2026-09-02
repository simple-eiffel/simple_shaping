note
	description: "[
		Greedy cluster-safe wrap + per-line visual reorder + line metrics.
		A class (not facade-private code) so the whole layout algorithm runs
		headless under NULL_* doubles (UC-005/AC-7).

		Phase-4 obligations bound here now:
		- Break only at soft-break positions that are ALSO cluster boundaries
		  and never inside an emoji segment (DR-007).
		- R2 (Q3): the breaking space belongs to the preceding line but its
		  advance is EXCLUDED from the fit comparison - `fits_within' IS that
		  rule, already real and contracted.
		- A single unbreakable cluster/image wider than the width overflows
		  its own line, flagged is_overflowing (never split).
		- Per finished line, call BIDI_RESOLVER.reorder on the line's run
		  levels to fix visual order (DR-002).
		- Line ascent/height = max over runs' fonts (glyph) and boxes (image).
	]"
	author: "Larry Rix"

class
	LINE_LAYOUT_ENGINE

inherit
	SHAPING_CONSTANTS

create
	make

feature {NONE} -- Initialization

	make
			-- Stateless engine.
		do
		end

feature -- Operations

	fits_within (a_run_advance_sum, a_trailing_whitespace_advance: REAL_64;
			a_width_pixels: INTEGER): BOOLEAN
			-- Does a candidate line fit `a_width_pixels' under the hanging-
			-- whitespace rule (R2): line-TRAILING whitespace advance is
			-- excluded from the comparison (else wrap points shift one word
			-- early)?
		require
			sums_sane: a_run_advance_sum >= 0.0 and a_trailing_whitespace_advance >= 0.0
			trailing_within: a_trailing_whitespace_advance <= a_run_advance_sum
			width_bounded: a_width_pixels > 0
		do
			Result := a_run_advance_sum - a_trailing_whitespace_advance <= a_width_pixels.to_double
		ensure
			definition: Result = (a_run_advance_sum - a_trailing_whitespace_advance
				<= a_width_pixels.to_double)
		end

	build_lines (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER;
			a_runs: ARRAYED_LIST [SHAPED_RUN]; a_reorderer: BIDI_RESOLVER): ARRAYED_LIST [SHAPED_LINE]
			-- Wrap `a_runs' (logical order) into visual lines at
			-- `a_width_pixels' (No_wrap = 0: one unbounded line).
		require
			width_non_negative: a_width_pixels >= 0
			size_positive: a_pixel_size > 0
		local
			l_line: SHAPED_LINE
		do
			-- Phase 4: greedy cluster-safe wrap (DR-007) + R2 hanging
			-- whitespace via `fits_within' + per-line `a_reorderer.reorder'
			-- (DR-002) + real metrics from run fonts/boxes.
			-- Phase 1 degenerate total-function body: one line covering every
			-- character, zero runs, placeholder metrics from `a_pixel_size'.
			create l_line.make (create {ARRAYED_LIST [SHAPED_RUN]}.make (0),
				1, a_text.count, a_pixel_size.to_double, 0.8 * a_pixel_size, False)
			create Result.make (1)
			Result.extend (l_line)
		ensure
			never_void: Result /= Void
			at_least_one_line: not Result.is_empty
			partition: lines_partition_text (Result, a_text.count)
		end

end
