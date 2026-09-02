note
	description: "[
		UAX #9 output for one paragraph: one embedding level per character
		(even = LTR, odd = RTL) plus the paragraph level. Levels are indexed
		1-based in CHARACTER (code point) space - READABLE_STRING_32 space,
		never UTF-16 units (backends translate at their own boundary; the
		dwrite spike's probe measured 18 code points = 19 UTF-16 units).

		Immutable value produced by seam BIDI_RESOLVER.
	]"
	author: "Larry Rix"

class
	BIDI_RESULT

inherit
	SHAPING_CONSTANTS

create
	make

feature {NONE} -- Initialization

	make (a_levels: ARRAY [NATURAL_8]; a_paragraph_level: NATURAL_8)
			-- Levels `a_levels' (one per character) under paragraph level
			-- `a_paragraph_level'.
		require
			paragraph_level_binary: a_paragraph_level <= 1
			levels_bounded: across a_levels as l all l <= Max_bidi_level end
		do
			levels := a_levels.twin
			levels.rebase (1)
			paragraph_level := a_paragraph_level
		ensure
			count_kept: count = a_levels.count
			paragraph_set: paragraph_level = a_paragraph_level
		end

feature -- Access

	paragraph_level: NATURAL_8
			-- Resolved paragraph embedding level (0 = LTR, 1 = RTL).

	count: INTEGER
			-- Number of characters covered.
		do
			Result := levels.count
		ensure
			non_negative: Result >= 0
		end

	level (a_index: INTEGER): NATURAL_8
			-- Level of character `a_index' (1-based, code-point space).
		require
			in_range: a_index >= 1 and a_index <= count
		do
			Result := levels [a_index]
		ensure
			bounded: Result <= Max_bidi_level
		end

	resolved_direction: INTEGER
			-- The paragraph direction this result implies.
		do
			if paragraph_level \\ 2 = 1 then
				Result := Direction_rtl
			else
				Result := Direction_ltr
			end
		ensure
			resolved: Result = Direction_ltr or Result = Direction_rtl
		end

feature -- Model queries (simple_mml)

	levels_model: MML_SEQUENCE [NATURAL_8]
			-- Levels as a mathematical sequence.
		local
			i: INTEGER
		do
			create Result
			from i := 1 until i > levels.count loop
				Result := Result & levels [i]
				i := i + 1
			end
		ensure
			same_count: Result.count = count
		end

feature {NONE} -- Implementation

	levels: ARRAY [NATURAL_8]
			-- One level per character, 1-based.

invariant
	paragraph_level_binary: paragraph_level <= 1
	levels_one_based: levels.lower = 1

end
