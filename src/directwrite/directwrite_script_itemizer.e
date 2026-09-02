note
	description: "[
		MVP effecting of seam 2 (G1 FINAL). Phase 4 effects `itemize' as the
		INTERSECTION of IDWriteTextAnalyzer.AnalyzeScript (vtable slot 3) and
		the bidi levels the caller hands in - the spike measured the
		necessity: AnalyzeScript alone merged Common-script characters
		(spaces, the emoji's surrogate pair) into neighboring runs, giving
		only 3 script runs for the D-015 probe; intersecting with the 2 bidi
		runs produced the 4 items the seam must emit, each with one script id
		and one level (spikes/dwrite/run_output.txt, checks A1/A2 PASS).
		`soft_breaks' effects over AnalyzeLineBreakpoints (slot 6).

		WHERE EACH HALF OF THE INTERSECTION COMES FROM (Phase 4 Task 4). The
		SCRIPT half is asked of DirectWrite here, per call, over the span. The
		BIDI half is NOT re-asked: it is read out of the `a_bidi' the facade
		already resolved through seam 1. That is not a shortcut, it is the
		oracle - `one_level_per_item' is checked against THAT BIDI_RESULT, so
		splitting on any other level table could satisfy DirectWrite and still
		violate the seam. `DWRITE_API.analyze' does refill the shim's bidi run
		table as a side effect; this class ignores it.

		SPLIT RULE: a new item starts wherever the SCRIPT ID changes or the
		LEVEL changes. Splitting on the run INDEX instead would be wrong -
		DirectWrite may deliver two adjacent runs carrying the same script id,
		and a boundary with neither a script-id change nor a level change
		violates `boundaries_are_script_or_bidi'. An item's `analysis' bytes
		come from the run covering its FIRST code point.

		UTF-16 BOUNDARY: owned HERE, exactly as Task 3 owns it in
		DIRECTWRITE_BIDI_RESOLVER, and through the same three steps - now
		factored into DIRECTWRITE_UTF16_MAPPING and inherited. Positions and
		counts emitted by this class are CODE POINTS; the shim's are units. A
		surrogate pair is ONE code point of ONE item; the D-015 probe is 18
		code points over 19 units, and the item table below is the code-point
		reading of the spike's unit table:

		    units  [0,4) s36 l1  ->  code points  1..4   start 1  count 4
		    units  [4,8) s36 l0  ->  code points  5..7   start 5  count 3
		    units [8,16) s30 l0  ->  code points  8..15  start 8  count 8
		    units [16,19) s49 l0 ->  code points 16..18  start 16 count 3

		Script ids emitted here are DirectWrite-internal opaque ints
		(spike: Hebrew=36, Greek=30, Latin=49) - never comparable across
		backends, never persisted, never mapped to `Script_class_*' (seam
		rule). The tests assert that the three are pairwise DISTINCT and
		stable, never that they equal 36/30/49.

		The shim's per-run DWRITE_SCRIPT_ANALYSIS travels to
		DIRECTWRITE_GLYPH_SHAPER verbatim inside SCRIPT_ITEM.analysis
		(`copy_script_run_analysis', byte for byte, never re-derived).

		EMOJI FREEDOM IS A CALLER DUTY, NOT A PRECONDITION (ISSUE 1). The
		facade normally hands this seam only EMOJI_SEGMENTER's PLAIN spans,
		but FR-007 rung 3 lawfully leaves an unresolvable pictograph PLAIN and
		sends it down the glyph path. A pictograph arriving here is therefore
		NOT a caller bug: it itemizes like any other character - it takes the
		script id of whatever run DirectWrite folded it into and the level its
		code point carries in `a_bidi' - and nothing in this class inspects,
		rejects or asserts about it. The measured consequence is .notdef at
		shaping time, which IS the degradation rung 3 promises.

		NEVER-RAISES / NFR-011. The documented degradation, both when
		DirectWrite cannot be opened and when `analyze' fails, is the
		LEVEL-SPLIT answer: items split at bidi level changes alone, one
		opaque script id 0, empty analysis bytes - the Phase-1 body, which is
		a lawful intersection (adjacent items always differ in level) and the
		same shape NULL_SCRIPT_ITEMIZER produces, so a headless machine
		degrades to headless behavior. `soft_breaks' degrades the same way to
		"a break after an ASCII space". Both features additionally carry a
		rescue that falls back once and only once, so no exception crosses the
		seam.
	]"
	author: "Larry Rix"
	never_raises: "itemize degrades to the level-split items and soft_breaks to breaks-after-spaces; no exception crosses the seam (NFR-011)."

class
	DIRECTWRITE_SCRIPT_ITEMIZER

inherit
	SCRIPT_ITEMIZER

	DIRECTWRITE_UTF16_MAPPING

create
	make

feature {NONE} -- Initialization

	make
			-- Wire the native surface.
		do
			create api.make
		end

feature -- Operations

	itemize (a_text: READABLE_STRING_32; a_start, a_count: INTEGER;
			a_bidi: BIDI_RESULT): ARRAYED_LIST [SCRIPT_ITEM]
			-- <Precursor>
		local
			l_runs, l_ids: ARRAY [INTEGER]
			i, l_item_start, l_item_run, l_id: INTEGER
			l_level: NATURAL_8
			l_degraded: BOOLEAN
		do
			create Result.make (4)
			if a_count > 0 then
					-- The SCRIPT half: one AnalyzeScript run index per code
					-- point, or all -1 on the NFR-011 fallback path.
				if l_degraded then
					create l_runs.make_filled (-1, 1, a_count)
				else
					l_runs := span_script_runs (a_text, a_start, a_count)
				end
					-- Read the opaque ids ONCE, while the shim's run table is
					-- still the one `span_script_runs' filled: nothing between
					-- here and the loop calls `analyze' again.
				create l_ids.make_filled (0, 1, a_count)
				from i := 1 until i > a_count loop
					l_ids [i] := script_id_at (l_runs [i])
					i := i + 1
				end
					-- The INTERSECTION: a new item wherever the script id or
					-- the level changes.
				l_item_start := a_start
				l_item_run := l_runs [1]
				l_id := l_ids [1]
				l_level := a_bidi.level (a_start)
				from i := 2 until i > a_count loop
					if l_ids [i] /= l_id or else a_bidi.level (a_start + i - 1) /= l_level then
						Result.extend (new_item (l_item_start, a_start + i - 1 - l_item_start,
							l_item_run, l_level))
						l_item_start := a_start + i - 1
						l_item_run := l_runs [i]
						l_id := l_ids [i]
						l_level := a_bidi.level (l_item_start)
					end
					i := i + 1
				end
				Result.extend (new_item (l_item_start, a_start + a_count - l_item_start,
					l_item_run, l_level))
			end
		rescue
			if not l_degraded then
				l_degraded := True
				retry
			end
		end

	soft_breaks (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM): ARRAY [BOOLEAN]
			-- <Precursor>
		local
			l_first: ARRAY [INTEGER]
			l_buffer: MANAGED_POINTER
			i, n, l_unit: INTEGER
			l_native, l_degraded: BOOLEAN
		do
			create Result.make_filled (False, 1, a_item.count)
			l_native := False
			if a_item.count > 0 and then not a_text.is_empty then
					-- AnalyzeLineBreakpoints over the WHOLE text, not the
					-- item alone: UAX #14 opportunities are decided from the
					-- characters on BOTH sides of a position, and an item is
					-- routinely a mid-sentence slice. The shim leaves the
					-- script and bidi run tables alone (Task 1's growth note),
					-- so this never disturbs an itemization in progress.
				if not l_degraded and then backend_open then
					n := unit_count (a_text, 1, a_text.count)
					l_first := first_units (a_text, 1, a_text.count)
					l_buffer := utf16_span (a_text, 1, a_text.count)
					if api.analyze_line_breakpoints (l_buffer.item, n) and then
						api.breakpoint_count = n
					then
						l_native := True
						from i := 1 until i > a_item.count loop
							l_unit := l_first [a_item.start_index + i - 1]
							if l_unit >= 0 and then l_unit < api.breakpoint_count then
								Result [i] := is_break_opportunity (api.break_condition_before (l_unit))
							end
							i := i + 1
						end
					end
				end
				if not l_native then
						-- NFR-011: the headless rule - a break after an ASCII
						-- space, which is what NULL_SCRIPT_ITEMIZER answers.
					from i := 2 until i > a_item.count loop
						if a_text.code (a_item.start_index + i - 2) = 32 then
							Result [i] := True
						end
						i := i + 1
					end
				end
					-- `no_break_before_first' on EVERY path: a line never
					-- begins with a break, whatever the analyzer says about
					-- the leading edge of the item's first unit.
				Result [1] := False
			end
		rescue
			if not l_degraded then
				l_degraded := True
				retry
			end
		end

feature {NONE} -- Implementation: the script half (AnalyzeScript + the UTF-16 boundary)

	span_script_runs (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): ARRAY [INTEGER]
			-- Per code point of the span (entry `i' = code point
			-- `a_start' + `i' - 1), the 0-based index of the AnalyzeScript
			-- run covering it - or -1 for every code point when the backend
			-- is unavailable, the analysis failed, or a unit fell outside
			-- every delivered run (NFR-011: no partial truth).
			-- On success the shim's script run table is LEFT LOADED, so the
			-- caller may read ids and analysis bytes straight afterwards.
		require
			span_valid: a_start >= 1 and a_count >= 0 and a_start + a_count - 1 <= a_text.count
			span_present: a_count > 0
		local
			l_units, l_first: ARRAY [INTEGER]
			l_buffer: MANAGED_POINTER
			i, j, n, r, l_pos, l_len: INTEGER
		do
			create Result.make_filled (-1, 1, a_count)
			if backend_open then
				n := unit_count (a_text, a_start, a_count)
				l_first := first_units (a_text, a_start, a_count)
				l_buffer := utf16_span (a_text, a_start, a_count)
				if api.analyze (l_buffer.item, n) then
						-- Spread the run indices over UNITS, then read ONE
						-- run per CODE POINT at its FIRST unit.
					create l_units.make_filled (-1, 1, n)
					from r := 0 until r >= api.script_run_count loop
						l_pos := api.script_run_position (r)
						l_len := api.script_run_length (r)
						if l_pos >= 0 and l_len > 0 then
							from j := l_pos + 1 until j > l_pos + l_len or j > n loop
								l_units [j] := r
								j := j + 1
							end
						end
						r := r + 1
					end
					from i := 1 until i > a_count loop
						Result [i] := l_units [l_first [i] + 1]
						i := i + 1
					end
				end
			end
		ensure
			one_per_code_point: Result.count = a_count
			one_based: Result.lower = 1
			run_index_or_unknown: across Result as x all x >= -1 end
		end

	script_id_at (a_run: INTEGER): INTEGER
			-- The engine's OPAQUE script id of script run `a_run'; 0 when
			-- `a_run' names no run (-1, the degraded answer). Opaque means
			-- opaque: this number is only ever compared with another id from
			-- the SAME pass and handed back to the SAME backend.
		do
			if a_run >= 0 and then a_run < api.script_run_count then
				Result := api.script_run_script (a_run)
			end
		end

	analysis_of_run (a_run: INTEGER): ARRAY [NATURAL_8]
			-- The DWRITE_SCRIPT_ANALYSIS bytes of script run `a_run',
			-- VERBATIM, for DIRECTWRITE_GLYPH_SHAPER (Task 5). Empty when
			-- `a_run' names no run - the shaper then gets the same empty
			-- currency NULL_SCRIPT_ITEMIZER hands it.
		local
			l_buffer: MANAGED_POINTER
			i, n: INTEGER
		do
			if a_run >= 0 and then a_run < api.script_run_count then
				n := api.script_analysis_size
				create l_buffer.make (n)
				api.copy_script_run_analysis (a_run, l_buffer.item)
				create Result.make_filled (0, 1, n)
				from i := 1 until i > n loop
					Result [i] := l_buffer.read_natural_8 (i - 1)
					i := i + 1
				end
			else
				create Result.make_empty
			end
		ensure
			never_void: Result /= Void
		end

	new_item (a_start, a_count, a_run: INTEGER; a_level: NATURAL_8): SCRIPT_ITEM
			-- One item of the intersection: characters `a_start' ..
			-- `a_start' + `a_count' - 1, the opaque script id and the
			-- analysis bytes of run `a_run', level `a_level'.
		require
			range_valid: a_start >= 1 and a_count > 0
			level_bounded: a_level <= Max_bidi_level
		do
			create Result.make (a_start, a_count, script_id_at (a_run), a_level,
				analysis_of_run (a_run))
		ensure
			placed: Result.start_index = a_start and Result.count = a_count
			level_kept: Result.embedding_level = a_level
			analysis_carried: Result.analysis /= Void
		end

feature {NONE} -- Implementation: helpers

	backend_open: BOOLEAN
			-- Is the native surface usable? Opens it if it is not.
			-- `DWRITE_API.open' is idempotent (the shim returns immediately
			-- when the analyzer already exists), so asking every time is the
			-- cheap way to stay correct even after another component closed
			-- the DLL. A False answer sends the caller down the NFR-011
			-- fallback; it never raises.
		do
			Result := api.open
		end

	is_break_opportunity (a_condition: INTEGER): BOOLEAN
			-- Does DWRITE_BREAK_CONDITION `a_condition' allow a line break?
			-- CAN_BREAK (1) and MUST_BREAK (3) do; NEUTRAL (0) and
			-- MAY_NOT_BREAK (2) do not. A-C07: this seam reports the
			-- OPPORTUNITY; DR-007 leaves layout free to refuse it inside a
			-- cluster or an emoji segment.
		do
			Result := a_condition = Break_can_break or a_condition = Break_must_break
		ensure
			definition: Result = (a_condition = Break_can_break or a_condition = Break_must_break)
		end

feature {NONE} -- Implementation: constants

	Break_can_break: INTEGER = 1
			-- DWRITE_BREAK_CONDITION_CAN_BREAK.

	Break_must_break: INTEGER = 3
			-- DWRITE_BREAK_CONDITION_MUST_BREAK.

feature {NONE} -- Implementation

	api: DWRITE_API
			-- The one native surface (single-translation-unit rule).

end
