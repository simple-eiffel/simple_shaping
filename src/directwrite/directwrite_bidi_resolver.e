note
	description: "[
		MVP effecting of seam 1 (G1 FINAL, 2026-09-01: Larry's ruling + the
		spikes/dwrite verdict PASS). `resolve' runs
		IDWriteTextAnalyzer.AnalyzeBidi (vtable slot 4) through DWRITE_API and
		maps its UTF-16 run table back to code points; `reorder' is the UAX #9
		L2 level-run reversal, computed in Eiffel over the levels it is handed
		(no native call - a line's visual order is arithmetic, not analysis).

		The plain-C COM shim pattern was PROVEN in spikes/dwrite/Clib/
		dwrite_spike.h and is now Clib/simple_shaping_dwrite.h: hand-declared C
		vtables (slot order transcribed verbatim from SDK dwrite.h, unused
		slots void*), static Source/Sink singletons, LoadLibraryW
		("dwrite.dll") + GetProcAddress ("DWriteCreateFactory"), shared factory
		-> CreateTextAnalyzer (slot 21). The spike measured every sink callback
		SYNCHRONOUS and ON THE CALLING THREAD - confinement-compatible
		(DR-012); and the D-015 probe produced levels resolved=1 over the
		Hebrew span, 0 elsewhere (run_output.txt).

		UTF-16 BOUNDARY (Phase 4 Task 3). The shim speaks UTF-16 code units;
		the seam speaks code points. THIS class owns the mapping, and it is the
		single most likely silent-wrong-answer site in the backend, so it is
		spelled out: `resolved_levels' walks the text once to record, per code
		point, the 0-based index of its FIRST UTF-16 unit (a code point above
		U+FFFF occupies two units), fills the buffer in a second pass, spreads
		AnalyzeBidi's per-run levels over a per-UNIT array, and then reads ONE
		level per code point at that first unit. A surrogate pair therefore
		lands as ONE code point carrying its run's level - never two, never a
		half. Measured on the D-015 string: 18 code points, 19 UTF-16 units.

		FIRST-STRONG (UAX #9 P2/P3) IS OURS, NOT DIRECTWRITE'S. There is no
		DWrite facility for it: DWRITE_READING_DIRECTION has exactly two
		members (LEFT_TO_RIGHT, RIGHT_TO_LEFT), IDWriteTextAnalysisSource.
		GetParagraphReadingDirection must answer one of them, and AnalyzeBidi
		takes the paragraph level as an INPUT - it never reports a level it
		worked out itself. So `Direction_auto' is resolved HERE, and only then
		installed through `DWRITE_API.set_paragraph_reading_direction' (the
		Task-3 shim growth) for the real analysis. The method
		(`first_strong_paragraph_level' + `strong_class_of'):

		  * P2's scan, verbatim: walk code points left to right, skipping
		    everything between an isolate initiator (U+2066 LRI, U+2067 RLI,
		    U+2068 FSI) and its matching U+2069 PDI - four code points that can
		    be recognized by value, so no character-class table is needed for
		    the skip;
		  * the strong/weak decision for each remaining code point is asked of
		    DIRECTWRITE ITSELF rather than of a hand-written range table, by
		    analyzing that ONE code point in isolation and reading the level
		    back. In isolation the resolved level is a signature of the bidi
		    class: with an LTR paragraph, strong L -> 0, R/AL -> 1, EN -> 0
		    (rule W7 turns it into L behind sos = L), AN -> 2, neutrals and
		    NSM -> 0; with an RTL paragraph, L -> 2, R/AL -> 1, EN -> 2,
		    AN -> 2, neutrals -> 1. That separates R/AL (level 1 under an LTR
		    paragraph) at once, and leaves exactly one ambiguity: strong L and
		    EN both read (0, 2). A third probe of U+200F RLM + the code point
		    under an LTR paragraph breaks it - the RLM blocks W7, so EN stays a
		    number and lands at level 2 while strong L stays at 0.
		  * So: level 1 on the first probe => strong RTL, paragraph level 1;
		    (0, 2, 0) => strong LTR, paragraph level 0; anything else is not
		    strong and the scan moves on. P3 - no strong character at all -
		    leaves paragraph level 0, which is what `empty_auto_ltr' demands.
		  * Cost: one native AnalyzeBidi per skipped code point (two for
		    numbers, three when the first strong character is L), and the scan
		    stops at the first strong character - for real chat text that is
		    the first character. The probes run BEFORE the paragraph's own
		    analysis, so they never disturb it (the shim's tables are rebuilt
		    per call).

		NEVER-RAISES / NFR-011. The documented degradation, both when
		DirectWrite cannot be opened and when `analyze' fails, is an
		ALL-PARAGRAPH-LEVEL result: every code point carries the paragraph
		level, which is 1 for `Direction_rtl' and 0 for `Direction_ltr' and for
		`Direction_auto' (P3's answer when nothing can be detected). That is a
		lawful BIDI_RESULT - it discharges every seam ensure - and it is the
		same shape NULL_BIDI_RESOLVER produces, so a headless machine degrades
		to headless behavior instead of raising. `resolve' and `reorder' each
		also carry a rescue that falls back to that answer once and only once,
		so no exception can cross the seam.

		ALTERNATE SLOTS (named, not existing): UNISCRIBE_BIDI_RESOLVER
		(ScriptItemize levels + ScriptLayout reorder); EIFFEL_BIDI_RESOLVER
		(future; promotion gate = FULL BidiTest.txt + BidiCharacterTest.txt
		through BIDI_CONFORMANCE_HARNESS, D-S06).
	]"
	author: "Larry Rix"
	never_raises: "resolve and reorder degrade to the all-paragraph-level answer and the L2-lawful permutation; no exception crosses the seam (NFR-011)."

class
	DIRECTWRITE_BIDI_RESOLVER

inherit
	BIDI_RESOLVER

create
	make

feature {NONE} -- Initialization

	make
			-- Wire the native surface.
		do
			create api.make
		end

feature -- Operations

	resolve (a_text: READABLE_STRING_32; a_base_direction: INTEGER): BIDI_RESULT
			-- <Precursor>
		local
			l_levels: ARRAY [NATURAL_8]
			l_paragraph: NATURAL_8
			l_degraded: BOOLEAN
		do
				-- The forced bases first, so `forced_ltr' / `forced_rtl' hold
				-- on every path INCLUDING the degraded one, and so a retry
				-- starts from a clean paragraph level.
			if a_base_direction = Direction_rtl then
				l_paragraph := 1
			else
				l_paragraph := 0
			end
			if l_degraded then
				create l_levels.make_filled (l_paragraph, 1, a_text.count)
			else
				if a_base_direction = Direction_auto and then not a_text.is_empty then
					l_paragraph := first_strong_paragraph_level (a_text)
				end
				l_levels := resolved_levels (a_text, l_paragraph)
			end
			create Result.make (l_levels, l_paragraph)
		rescue
			if not l_degraded then
				l_degraded := True
				retry
			end
		end

	reorder (a_levels: ARRAY [NATURAL_8]): ARRAY [INTEGER]
			-- <Precursor>
		local
			i, n, l_max, l_min_odd, l_level, l_start: INTEGER
			l_has_odd, l_degraded: BOOLEAN
		do
			n := a_levels.count
			create Result.make_filled (0, 1, n)
			from i := 1 until i > n loop
				Result [i] := i
				i := i + 1
			end
			if l_degraded then
					-- The lawful last resort: the two cases the seam names
					-- (ISSUE 13) - all-even is the identity already in place,
					-- all-odd is the full reversal.
				if n > 0 and then is_all_odd (a_levels) then
					from i := 1 until i > n loop
						Result [i] := n - i + 1
						i := i + 1
					end
				end
			elseif n > 0 then
					-- UAX #9 L2, verbatim: "from the highest level found in
					-- the text to the lowest odd level on each line,
					-- including intermediate levels not actually present in
					-- the text, reverse any contiguous sequence of characters
					-- that are at that level or higher."
				from i := 1 until i > n loop
					l_level := level_at (a_levels, i)
					if l_level > l_max then
						l_max := l_level
					end
					if l_level \\ 2 = 1 and then (not l_has_odd or else l_level < l_min_odd) then
						l_min_odd := l_level
						l_has_odd := True
					end
					i := i + 1
				end
				if l_has_odd then
					from l_level := l_max until l_level < l_min_odd loop
						from i := 1 until i > n loop
							if level_at (a_levels, i) >= l_level then
								l_start := i
								from until i > n or else level_at (a_levels, i) < l_level loop
									i := i + 1
								end
								reverse_slice (Result, l_start, i - 1)
							else
								i := i + 1
							end
						end
						l_level := l_level - 1
					end
				end
			end
		rescue
			if not l_degraded then
				l_degraded := True
				retry
			end
		end

feature {NONE} -- Implementation: levels (AnalyzeBidi + the UTF-16 boundary)

	resolved_levels (a_text: READABLE_STRING_32; a_paragraph_level: NATURAL_8): ARRAY [NATURAL_8]
			-- One level per CODE POINT of `a_text' under paragraph level
			-- `a_paragraph_level', from AnalyzeBidi's UTF-16 run table.
			-- Degrades (NFR-011) to all-paragraph-level when the backend is
			-- unavailable or the analysis fails.
		require
			paragraph_binary: a_paragraph_level <= 1
		local
			l_first_unit: ARRAY [INTEGER]
			l_unit_levels: ARRAY [NATURAL_8]
			l_buffer: MANAGED_POINTER
			i, j, n, r, l_code, l_offset, l_pos, l_len, l_level: INTEGER
		do
			create Result.make_filled (a_paragraph_level, 1, a_text.count)
			if not a_text.is_empty and then backend_open then
					-- Pass 1: the code-point -> first-UTF-16-unit map. This
					-- IS the boundary; everything below reads it.
				create l_first_unit.make_filled (0, 1, a_text.count)
				from i := 1 until i > a_text.count loop
					l_first_unit [i] := n
					if a_text.code (i).to_integer_32 > 0xFFFF then
						n := n + 2
					else
						n := n + 1
					end
					i := i + 1
				end
					-- Pass 2: the UTF-16 buffer the shim analyzes.
				create l_buffer.make (n * 2)
				from i := 1 until i > a_text.count loop
					l_code := a_text.code (i).to_integer_32
					if l_code > 0xFFFF then
						l_offset := l_code - 0x10000
						l_buffer.put_natural_16 ((0xD800 + l_offset.bit_shift_right (10)).to_natural_16,
							l_first_unit [i] * 2)
						l_buffer.put_natural_16 ((0xDC00 + l_offset.bit_and (0x3FF)).to_natural_16,
							(l_first_unit [i] + 1) * 2)
					else
						l_buffer.put_natural_16 (l_code.to_natural_16, l_first_unit [i] * 2)
					end
					i := i + 1
				end
				api.set_paragraph_reading_direction (a_paragraph_level.to_integer_32)
				if api.analyze (l_buffer.item, n) then
						-- Spread the run levels over UNITS, then read one
						-- level per CODE POINT at its first unit.
					create l_unit_levels.make_filled (a_paragraph_level, 1, n)
					from r := 0 until r >= api.bidi_run_count loop
						l_pos := api.bidi_run_position (r)
						l_len := api.bidi_run_length (r)
						l_level := api.bidi_run_level (r)
						if l_level > Max_bidi_level.to_integer_32 then
								-- Defensive: the seam promises `levels_bounded'
								-- and UAX #9 caps max_depth at 125, so a level
								-- above it is a native anomaly, not data.
							l_level := Max_bidi_level.to_integer_32
						end
						if l_pos >= 0 and l_len > 0 then
							from j := l_pos + 1 until j > l_pos + l_len or j > n loop
								l_unit_levels [j] := l_level.to_natural_8
								j := j + 1
							end
						end
						r := r + 1
					end
					from i := 1 until i > a_text.count loop
						Result [i] := l_unit_levels [l_first_unit [i] + 1]
						i := i + 1
					end
				end
			end
		ensure
			one_level_per_code_point: Result.count = a_text.count
			one_based: Result.lower = 1
			bounded: across Result as l all l <= Max_bidi_level end
		end

feature {NONE} -- Implementation: first-strong detection (UAX #9 P2/P3)

	first_strong_paragraph_level (a_text: READABLE_STRING_32): NATURAL_8
			-- UAX #9 P2/P3 over `a_text': the level implied by the first
			-- strong character outside any isolate - 1 when it is R or AL,
			-- 0 when it is L, and 0 when there is none (P3).
		require
			text_present: not a_text.is_empty
		local
			i, l_code, l_depth: INTEGER
			l_settled: BOOLEAN
		do
			if backend_open then
				from i := 1 until i > a_text.count or l_settled loop
					l_code := a_text.code (i).to_integer_32
					if l_depth > 0 then
							-- Inside an isolate: P2 skips to the matching PDI.
						if l_code = Pdi_code then
							l_depth := l_depth - 1
						elseif is_isolate_initiator (l_code) then
							l_depth := l_depth + 1
						end
					elseif is_isolate_initiator (l_code) then
						l_depth := 1
					elseif l_code /= Pdi_code then
						inspect strong_class_of (l_code)
						when Strong_rtl then
							Result := 1
							l_settled := True
						when Strong_ltr then
							l_settled := True
						else
								-- Not strong: P2 keeps looking.
						end
					end
					i := i + 1
				end
			end
		ensure
			binary: Result <= 1
		end

	strong_class_of (a_code: INTEGER): INTEGER
			-- Is `a_code' strong L, strong R/AL, or neither - asked of
			-- DirectWrite itself by analyzing the single code point in
			-- isolation and reading the level signature back (see the class
			-- note). `Strong_none' whenever a probe could not be run.
		local
			l_ltr, l_rtl, l_marked: INTEGER
		do
			l_ltr := probe_level (a_code, api.Reading_direction_ltr, False)
			if l_ltr = 1 then
					-- Only R and AL reach an odd level under an LTR paragraph.
				Result := Strong_rtl
			elseif l_ltr = 0 then
				l_rtl := probe_level (a_code, api.Reading_direction_rtl, False)
				if l_rtl = 2 then
						-- Strong L or EN; W7 made them look alike. An RLM in
						-- front blocks W7, and only EN moves.
					l_marked := probe_level (a_code, api.Reading_direction_ltr, True)
					if l_marked = 0 then
						Result := Strong_ltr
					end
				end
			end
		ensure
			in_enumeration: Result = Strong_none or Result = Strong_ltr or Result = Strong_rtl
		end

	probe_level (a_code, a_direction: INTEGER; a_rlm_prefix: BOOLEAN): INTEGER
			-- The level AnalyzeBidi resolves for the single code point
			-- `a_code' analyzed alone under paragraph reading direction
			-- `a_direction', optionally preceded by U+200F RIGHT-TO-LEFT MARK.
			-- -1 when the probe could not run.
		require
			direction_binary: a_direction = api.Reading_direction_ltr or a_direction = api.Reading_direction_rtl
		local
			l_buffer: MANAGED_POINTER
			l_at, l_units, l_offset, r, l_pos, l_len: INTEGER
			l_found: BOOLEAN
		do
			Result := -1
			if a_rlm_prefix then
				l_at := 1
			end
			if a_code > 0xFFFF then
				l_units := l_at + 2
			else
				l_units := l_at + 1
			end
			create l_buffer.make (l_units * 2)
			if a_rlm_prefix then
				l_buffer.put_natural_16 ((0x200F).to_natural_16, 0)
			end
			if a_code > 0xFFFF then
				l_offset := a_code - 0x10000
				l_buffer.put_natural_16 ((0xD800 + l_offset.bit_shift_right (10)).to_natural_16, l_at * 2)
				l_buffer.put_natural_16 ((0xDC00 + l_offset.bit_and (0x3FF)).to_natural_16, (l_at + 1) * 2)
			else
				l_buffer.put_natural_16 (a_code.to_natural_16, l_at * 2)
			end
			api.set_paragraph_reading_direction (a_direction)
			if api.is_open and then api.analyze (l_buffer.item, l_units) then
				from r := 0 until r >= api.bidi_run_count or l_found loop
					l_pos := api.bidi_run_position (r)
					l_len := api.bidi_run_length (r)
					if l_pos <= l_at and then l_at < l_pos + l_len then
						Result := api.bidi_run_level (r)
						l_found := True
					end
					r := r + 1
				end
			end
		ensure
			sane: Result >= -1
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

	level_at (a_levels: ARRAY [NATURAL_8]; a_position: INTEGER): INTEGER
			-- Level of the `a_position'-th entry of `a_levels' (1-based,
			-- whatever `a_levels.lower' happens to be).
		require
			in_range: a_position >= 1 and a_position <= a_levels.count
		do
			Result := a_levels [a_levels.lower + a_position - 1].to_integer_32
		ensure
			non_negative: Result >= 0
		end

	reverse_slice (a_permutation: ARRAY [INTEGER]; a_from, a_to: INTEGER)
			-- Reverse entries `a_from' .. `a_to' of `a_permutation' in place -
			-- one L2 run reversal.
		require
			one_based: a_permutation.lower = 1
			ordered: a_from >= 1 and a_to >= a_from
			within_bounds: a_to <= a_permutation.count
		local
			i, j, l_swap: INTEGER
		do
			from
				i := a_from
				j := a_to
			until
				i >= j
			loop
				l_swap := a_permutation [i]
				a_permutation [i] := a_permutation [j]
				a_permutation [j] := l_swap
				i := i + 1
				j := j - 1
			end
		end

	is_isolate_initiator (a_code: INTEGER): BOOLEAN
			-- Is `a_code' LRI, RLI or FSI - a UAX #9 isolate initiator?
		do
			Result := a_code = Lri_code or a_code = Rli_code or a_code = Fsi_code
		ensure
			definition: Result = (a_code = Lri_code or a_code = Rli_code or a_code = Fsi_code)
		end

feature {NONE} -- Implementation: constants

	Lri_code: INTEGER = 0x2066
			-- U+2066 LEFT-TO-RIGHT ISOLATE.

	Rli_code: INTEGER = 0x2067
			-- U+2067 RIGHT-TO-LEFT ISOLATE.

	Fsi_code: INTEGER = 0x2068
			-- U+2068 FIRST STRONG ISOLATE.

	Pdi_code: INTEGER = 0x2069
			-- U+2069 POP DIRECTIONAL ISOLATE.

	Strong_none: INTEGER = 0
			-- `strong_class_of': not a strong character (P2 keeps looking).

	Strong_ltr: INTEGER = 1
			-- `strong_class_of': bidi class L.

	Strong_rtl: INTEGER = 2
			-- `strong_class_of': bidi class R or AL.

feature {NONE} -- Implementation

	api: DWRITE_API
			-- The one native surface (single-translation-unit rule).

end
