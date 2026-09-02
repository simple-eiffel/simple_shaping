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

		PHASE 4 TASK 10 - THE WRAP IS REAL.

		THE BREAK-GRANULARITY CONTRACT (Larry's gate decision 1, 2026-09-02).
		`build_lines' has NO soft-break parameter and never gains one. The
		FACADE pre-splits runs at the soft-break positions the itemizer
		reported (which are cluster boundaries by construction) BEFORE
		calling here, so a break opportunity arrives as RUN GRANULARITY: a
		line may break BETWEEN runs and never INSIDE one. Everything DR-007
		forbids therefore becomes structurally impossible rather than
		re-checked - a base+niqqud cluster shares one run, and an emoji
		segment is one atomic IMAGE_RUN. The engine's only job is deciding
		WHICH runs go on WHICH line.

		THE IMAGE-BOX CONTRACT (FR-007). An IMAGE_RUN is immutable and its
		box is fixed at construction, so the engine cannot size it: the
		FACADE builds emoji runs square at the line height it is laying out
		at (the primary font's ascent+descent at `pixel_size', or
		`pixel_size' itself when that font never realized), and IMAGE_RUN's
		own `box_is_advance' makes the advance follow. This engine holds up
		the other half: an image box contributes its FULL height to the
		line's extent (`Default_ascent_ratio' of it above the baseline), so
		a box built at the line height leaves the line exactly that tall
		instead of growing it.

		WHOSE METRICS. A glyph run whose font is realized measures from that
		font (`ascent'/`descent' at `pixel_size' - TEXTMETRIC, D-S03). A run
		whose font never realized has no metrics at all
		(`unrealized_has_no_metrics'), and headless runs under NULL_* are
		exactly that case, so the run's own positive `height' is split
		`Default_ascent_ratio' / the rest. Either way `metrics_sane' holds by
		construction, and a line with NO runs (FR-N01) takes `pixel_size'.
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
			l_groups: ARRAYED_LIST [ARRAYED_LIST [SHAPED_RUN]]
			l_overflows: ARRAYED_LIST [BOOLEAN]
			l_current: ARRAYED_LIST [SHAPED_RUN]
			l_run: SHAPED_RUN
			i, l_start, l_count, l_covered: INTEGER
			l_sum, l_trail, l_next_sum, l_next_trail: REAL_64
			l_solo_fits: BOOLEAN
		do
				-- ---- Pass 1: which runs go on which line (logical order) ----
			create l_groups.make (4)
			create l_overflows.make (4)
			create l_current.make (4)
			if a_width_pixels = No_wrap then
					-- One unbounded line: there is no width to fit, so no
					-- break opportunity is ever taken and nothing overflows.
				from i := 1 until i > a_runs.count loop
					l_current.extend (a_runs [i])
					i := i + 1
				end
				l_groups.extend (l_current)
				l_overflows.extend (False)
			else
				from i := 1 until i > a_runs.count loop
					l_run := a_runs [i]
					l_next_sum := l_sum + l_run.advance_width
					if is_breaking_space_run (a_text, l_run) then
							-- The candidate's trailing-whitespace suffix grows
							-- by this run (R2).
						l_next_trail := l_trail + l_run.advance_width
					else
							-- Ink at the end: no hanging suffix any more.
						l_next_trail := 0.0
					end
					if l_current.is_empty then
							-- DR-007: a run is NEVER split, so the first run of
							-- a line takes it whether it fits or not.
						l_solo_fits := fits_within (l_next_sum,
							l_next_trail.min (l_next_sum), a_width_pixels)
						l_current.extend (l_run)
						l_sum := l_next_sum
						l_trail := l_next_trail
						if not l_solo_fits then
								-- One unbreakable run wider than the width: its
								-- own line, flagged (SHAPED_LINE's
								-- `overflow_shape'), never split.
							l_groups.extend (l_current)
							l_overflows.extend (True)
							create l_current.make (4)
							l_sum := 0.0
							l_trail := 0.0
						end
					elseif fits_within (l_next_sum, l_next_trail.min (l_next_sum), a_width_pixels) then
						l_current.extend (l_run)
						l_sum := l_next_sum
						l_trail := l_next_trail
					else
							-- Break BETWEEN runs and re-offer this run to the
							-- fresh line (it is consumed there: the fresh line
							-- is empty, so the branch above always takes it).
						l_groups.extend (l_current)
						l_overflows.extend (False)
						create l_current.make (4)
						l_sum := 0.0
						l_trail := 0.0
						i := i - 1
					end
					i := i + 1
				end
				if not l_current.is_empty or else l_groups.is_empty then
						-- The open line, or - with no runs at all - the single
						-- empty line FR-N01 demands.
					l_groups.extend (l_current)
					l_overflows.extend (False)
				end
			end
				-- ---- Pass 2: source ranges, metrics, visual order ----
			create Result.make (l_groups.count)
			from i := 1 until i > l_groups.count loop
				l_start := l_covered + 1
				l_count := group_source_count (l_groups [i])
				if i = l_groups.count or else l_covered + l_count > a_text.count then
						-- The last line absorbs the remainder, and no line may
						-- run past the text: together these make `partition'
						-- hold even for runs that do not tile `a_text'.
					l_count := a_text.count - l_covered
				end
				l_covered := l_covered + l_count
				Result.extend (finished_line (l_groups [i], l_start, l_count,
					a_pixel_size, l_overflows [i], a_reorderer))
				i := i + 1
			end
		ensure
			never_void: Result /= Void
			at_least_one_line: not Result.is_empty
			partition: lines_partition_text (Result, a_text.count)
		end

feature {NONE} -- Implementation: line assembly (ADDED Phase 4 Task 10)

	Default_ascent_ratio: REAL_64 = 0.8
			-- Share of a metric-less extent that sits ABOVE the baseline.
			-- Used for a run whose font never realized (headless NULL_*
			-- runs) and for an image box, which has no baseline of its own.
			-- The Phase-1 placeholder line used the same 0.8, so an empty
			-- line keeps exactly the metrics FR-N01 already shipped.

	finished_line (a_runs: ARRAYED_LIST [SHAPED_RUN]; a_source_start, a_source_count,
			a_pixel_size: INTEGER; a_overflowing: BOOLEAN;
			a_reorderer: BIDI_RESOLVER): SHAPED_LINE
			-- One finished line: `a_runs' reordered into visual paint order
			-- (DR-002) over logical characters `a_source_start' ..
			-- `a_source_start' + `a_source_count' - 1, with ascent taken as
			-- the max over the runs' fonts and boxes, and height at least
			-- the tallest run's own extent.
		require
			range_valid: a_source_start >= 1 and a_source_count >= 0
			size_positive: a_pixel_size > 0
			overflow_only_when_unbreakable: a_overflowing implies a_runs.count = 1
		local
			l_ascent, l_descent, l_extent, l_height: REAL_64
			i: INTEGER
		do
			from i := 1 until i > a_runs.count loop
				l_ascent := l_ascent.max (run_ascent (a_runs [i]))
				l_descent := l_descent.max (run_descent (a_runs [i]))
				l_extent := l_extent.max (a_runs [i].height)
				i := i + 1
			end
			if a_runs.is_empty then
					-- FR-N01/AC-6: an empty line still measures, from the
					-- layout's own size (the primary font's realized metrics
					-- are the facade's `line_height', not the engine's).
				l_ascent := Default_ascent_ratio * a_pixel_size.to_double
				l_descent := 0.0
				l_extent := a_pixel_size.to_double
			end
			l_height := (l_ascent + l_descent).max (l_extent)
			create Result.make (visually_ordered (a_runs, a_reorderer),
				a_source_start, a_source_count, l_height, l_ascent, a_overflowing)
		ensure
			metrics_sane: Result.height > 0.0 and Result.ascent > 0.0
				and Result.ascent <= Result.height
			range_kept: Result.source_start = a_source_start
				and Result.source_count = a_source_count
			same_run_count: Result.runs.count = a_runs.count
			overflow_kept: Result.is_overflowing = a_overflowing
		end

	visually_ordered (a_runs: ARRAYED_LIST [SHAPED_RUN];
			a_reorderer: BIDI_RESOLVER): ARRAYED_LIST [SHAPED_RUN]
			-- `a_runs' (LOGICAL order) permuted into VISUAL paint order by
			-- `a_reorderer.reorder' over their embedding levels (UAX #9 L2,
			-- DR-002): Result [v] = a_runs [permutation [v]].
		local
			l_levels: ARRAY [NATURAL_8]
			l_permutation: ARRAY [INTEGER]
			i: INTEGER
		do
			create Result.make (a_runs.count)
			if not a_runs.is_empty then
				create l_levels.make_filled ({NATURAL_8} 0, 1, a_runs.count)
				from i := 1 until i > a_runs.count loop
					l_levels [i] := a_runs [i].embedding_level
					i := i + 1
				end
				l_permutation := a_reorderer.reorder (l_levels)
				from i := l_permutation.lower until i > l_permutation.upper loop
					Result.extend (a_runs [l_permutation [i]])
					i := i + 1
				end
			end
		ensure
			same_count: Result.count = a_runs.count
		end

	group_source_count (a_runs: ARRAYED_LIST [SHAPED_RUN]): INTEGER
			-- Characters covered by `a_runs' together.
		local
			i: INTEGER
		do
			from i := 1 until i > a_runs.count loop
				Result := Result + a_runs [i].source_count
				i := i + 1
			end
		ensure
			non_negative: Result >= 0
		end

feature {NONE} -- Implementation: metrics (ADDED Phase 4 Task 10)

	run_ascent (a_run: SHAPED_RUN): REAL_64
			-- How far above the baseline `a_run' reaches: its font's
			-- TEXTMETRIC ascent when that font realized, else
			-- `Default_ascent_ratio' of the run's own extent (an image box
			-- and a headless glyph run both land here).
		do
			if attached {GLYPH_RUN} a_run as al_glyphs and then al_glyphs.font.is_ready then
				Result := al_glyphs.font.ascent
			else
				Result := Default_ascent_ratio * a_run.height
			end
		ensure
			positive: Result > 0.0
		end

	run_descent (a_run: SHAPED_RUN): REAL_64
			-- How far below the baseline `a_run' reaches; the dual of
			-- `run_ascent', so ascent + descent never exceeds the run's own
			-- extent for a metric-less run.
		do
			if attached {GLYPH_RUN} a_run as al_glyphs and then al_glyphs.font.is_ready then
				Result := al_glyphs.font.descent
			else
				Result := (1.0 - Default_ascent_ratio) * a_run.height
			end
		ensure
			non_negative: Result >= 0.0
		end

feature {NONE} -- Implementation: the R2 whitespace question (ADDED Phase 4 Task 10)

	is_breaking_space_run (a_text: READABLE_STRING_32; a_run: SHAPED_RUN): BOOLEAN
			-- Is EVERY character `a_run' covers a breaking space, making the
			-- run part of a line's hanging-whitespace suffix (R2)? An
			-- IMAGE_RUN never is, and a run whose range falls outside
			-- `a_text' is treated as ink rather than trusted.
		local
			i, l_last: INTEGER
		do
			l_last := a_run.source_start + a_run.source_count - 1
			if attached {IMAGE_RUN} a_run then
				Result := False
			elseif a_run.source_start >= 1 and l_last <= a_text.count then
				Result := True
				from i := a_run.source_start until i > l_last or not Result loop
					Result := is_breaking_space_code (a_text.code (i))
					i := i + 1
				end
			end
		end

	is_breaking_space_code (a_code: NATURAL_32): BOOLEAN
			-- Is `a_code' a space at which a line MAY break? The
			-- non-breaking spaces are deliberately absent: NBSP (00A0),
			-- FIGURE SPACE (2007) and NARROW NO-BREAK SPACE (202F) exist
			-- precisely to forbid the break this predicate authorizes.
		local
			l_code: INTEGER
		do
			l_code := a_code.to_integer_32
			Result := l_code = 32 or (l_code >= 9 and l_code <= 13)
				or l_code = 5760 or l_code = 8232 or l_code = 8233
				or l_code = 8287 or l_code = 12288
				or (l_code >= 8192 and l_code <= 8202 and l_code /= 8199)
		ensure
			plain_space_breaks: a_code.to_integer_32 = 32 implies Result
			no_break_space_does_not: a_code.to_integer_32 = 160 implies not Result
		end

end
