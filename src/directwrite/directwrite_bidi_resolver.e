note
	description: "[
		MVP effecting of seam 1 (G1 FINAL, 2026-09-01: Larry's ruling + the
		spikes/dwrite verdict PASS). Phase 4 effects `resolve' with
		IDWriteTextAnalyzer.AnalyzeBidi (vtable slot 4) and `reorder' with
		the UAX #9 L2 level-run reversal over AnalyzeBidi's resolved levels,
		through DWRITE_API and the plain-C COM shim pattern PROVEN in
		spikes/dwrite/Clib/dwrite_spike.h: hand-declared C vtables (slot
		order transcribed verbatim from SDK dwrite.h, unused slots void*),
		static Source/Sink singletons, LoadLibraryW ("dwrite.dll") +
		GetProcAddress ("DWriteCreateFactory"), shared factory ->
		CreateTextAnalyzer (slot 21). The spike measured every sink callback
		SYNCHRONOUS and ON THE CALLING THREAD - confinement-compatible
		(DR-012); and the D-015 probe produced levels resolved=1 over the
		Hebrew span, 0 elsewhere (run_output.txt).

		UTF-16 BOUNDARY: the shim speaks UTF-16 code units (spike: 18 code
		points = 19 units); THIS class owns the code-point <-> UTF-16
		position mapping. Seam contracts stay in code-point space.

		ALTERNATE SLOTS (named, not existing): UNISCRIBE_BIDI_RESOLVER
		(ScriptItemize levels + ScriptLayout reorder); EIFFEL_BIDI_RESOLVER
		(future; promotion gate = FULL BidiTest.txt + BidiCharacterTest.txt
		through BIDI_CONFORMANCE_HARNESS, D-S06).

		Phase-1 bodies are degenerate placeholders that satisfy the seam
		contracts (all-paragraph-level levels; identity reorder) - marked,
		replaced in Phase 4, and distinguished from real bidi by the harness.
	]"
	author: "Larry Rix"

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
		do
			-- Phase 4: marshal to UTF-16, api.analyze, map SetBidiLevel runs
			-- back to code-point space, first-strong detection for
			-- Direction_auto (GetParagraphReadingDirection source callback).
			if a_base_direction = Direction_rtl then
				l_paragraph := 1
			else
				l_paragraph := 0
			end
			create l_levels.make_filled (l_paragraph, 1, a_text.count)
			create Result.make (l_levels, l_paragraph)
		end

	reorder (a_levels: ARRAY [NATURAL_8]): ARRAY [INTEGER]
			-- <Precursor>
		local
			i: INTEGER
		do
			-- Phase 4: UAX #9 L2 - reverse maximal runs from the highest
			-- level down to the lowest odd level.
			-- Phase 1 placeholder: the two cases the seam contracts
			-- (ISSUE 13) - all-even is the identity, all-odd is the full
			-- reversal; anything mixed stays identity until Phase 4.
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
		end

feature {NONE} -- Implementation

	api: DWRITE_API
			-- The one native surface (single-translation-unit rule).

end
