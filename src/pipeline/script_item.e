note
	description: "[
		One maximal same-script, same-bidi-level stretch of a PLAIN segment -
		the unit one engine shapes with one font (the script x bidi
		intersection, DR-003; measured in the dwrite spike: 3 script runs x 2
		bidi runs -> 4 itemized runs for the D-015 probe text).

		script_code IS ENGINE-INTERNAL AND OPAQUE: DirectWrite numbered the
		spike's Hebrew/Greek/Latin 36/30/49; Uniscribe numbers differently;
		neither is ISO 15924. NEVER compare script codes across backends,
		never persist them, never map them to script names. The only lawful
		uses are (a) equality WITHIN one backend's pipeline pass and (b)
		passing them back to the same backend's shaper via `analysis'.

		`analysis' carries the backend's own per-item analysis bytes verbatim
		(DirectWrite: DWRITE_SCRIPT_ANALYSIS; Uniscribe alternate:
		SCRIPT_ANALYSIS) - opaque currency between itemizer and shaper of the
		SAME backend.

		Immutable value produced by seam SCRIPT_ITEMIZER.
	]"
	author: "Larry Rix"

class
	SCRIPT_ITEM

inherit
	SHAPING_CONSTANTS

create
	make

feature {NONE} -- Initialization

	make (a_start_index, a_count: INTEGER; a_script_code: INTEGER;
			a_embedding_level: NATURAL_8; a_analysis: ARRAY [NATURAL_8])
			-- Item over characters `a_start_index' .. `a_start_index' + `a_count' - 1.
		require
			range_valid: a_start_index >= 1 and a_count > 0
			level_bounded: a_embedding_level <= Max_bidi_level
		do
			start_index := a_start_index
			count := a_count
			script_code := a_script_code
			embedding_level := a_embedding_level
			analysis := a_analysis
		ensure
			range_set: start_index = a_start_index and count = a_count
			script_kept: script_code = a_script_code
			level_set: embedding_level = a_embedding_level
			analysis_kept: analysis = a_analysis
		end

feature -- Access

	start_index: INTEGER
			-- First character (1-based, code-point space).

	count: INTEGER
			-- Number of characters.

	script_code: INTEGER
			-- ENGINE-INTERNAL OPAQUE script id (see class note; never compare
			-- across backends).

	embedding_level: NATURAL_8
			-- Resolved bidi level of every character in this item.

	analysis: ARRAY [NATURAL_8]
			-- Backend-opaque analysis bytes, itemizer -> same backend's shaper.

feature -- Status

	is_rtl: BOOLEAN
			-- Does this item read right-to-left?
		do
			Result := embedding_level \\ 2 = 1
		ensure
			direction_from_level: Result = (embedding_level \\ 2 = 1)
		end

feature -- Model queries (simple_mml)

	analysis_model: MML_SEQUENCE [NATURAL_8]
			-- The opaque analysis bytes as a mathematical sequence (a
			-- definition of this immutable value; the bytes stay opaque -
			-- the model states identity, never meaning).
		local
			i: INTEGER
		do
			create Result
			from i := analysis.lower until i > analysis.upper loop
				Result := Result & analysis [i]
				i := i + 1
			end
		ensure
			same_count: Result.count = analysis.count
		end

invariant
	range_valid: start_index >= 1 and count > 0
	level_bounded: embedding_level <= Max_bidi_level

end
