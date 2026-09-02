note
	description: "[
		MVP effecting of seam 2 (G1 FINAL). Phase 4 effects `itemize' as the
		INTERSECTION of IDWriteTextAnalyzer.AnalyzeScript (vtable slot 3) and
		AnalyzeBidi (slot 4) run boundaries - the spike measured the
		necessity: AnalyzeScript alone merged Common-script characters
		(spaces, the emoji's surrogate pair) into neighboring runs, giving
		only 3 script runs for the D-015 probe; intersecting with the 2 bidi
		runs produced the 4 items the seam must emit, each with one script id
		and one level (spikes/dwrite/run_output.txt, checks A1/A2 PASS).
		`soft_breaks' effects over AnalyzeLineBreakpoints (slot 6) in
		Phase 4.

		Script ids emitted here are DirectWrite-internal opaque ints
		(spike: Hebrew=36, Greek=30, Latin=49) - never comparable across
		backends, never persisted (seam rule).

		The shim's per-run DWRITE_SCRIPT_ANALYSIS travels to
		DIRECTWRITE_GLYPH_SHAPER verbatim inside SCRIPT_ITEM.analysis.

		Phase-1 bodies are degenerate placeholders that satisfy the seam
		contracts: items split exactly at bidi level changes (one script id
		0), soft breaks after ASCII spaces. Replaced in Phase 4.
	]"
	author: "Larry Rix"

class
	DIRECTWRITE_SCRIPT_ITEMIZER

inherit
	SCRIPT_ITEMIZER

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
			i, l_run_start: INTEGER
			l_level: NATURAL_8
		do
			-- Phase 4: AnalyzeScript x AnalyzeBidi intersection over the
			-- span, positions mapped UTF-16 <-> code points, analysis bytes
			-- carried per item.
			create Result.make (4)
			if a_count > 0 then
				l_run_start := a_start
				l_level := a_bidi.level (a_start)
				from i := a_start + 1 until i > a_start + a_count - 1 loop
					if a_bidi.level (i) /= l_level then
						Result.extend (create {SCRIPT_ITEM}.make (l_run_start, i - l_run_start,
							0, l_level, create {ARRAY [NATURAL_8]}.make_empty))
						l_run_start := i
						l_level := a_bidi.level (i)
					end
					i := i + 1
				end
				Result.extend (create {SCRIPT_ITEM}.make (l_run_start, a_start + a_count - l_run_start,
					0, l_level, create {ARRAY [NATURAL_8]}.make_empty))
			end
		end

	soft_breaks (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM): ARRAY [BOOLEAN]
			-- <Precursor>
		local
			i: INTEGER
		do
			-- Phase 4: AnalyzeLineBreakpoints over the item's range.
			create Result.make_filled (False, 1, a_item.count)
			from i := 2 until i > a_item.count loop
				if a_text.code (a_item.start_index + i - 2) = 32 then
					Result [i] := True
				end
				i := i + 1
			end
		end

feature {NONE} -- Implementation

	api: DWRITE_API
			-- The one native surface (single-translation-unit rule).

end
