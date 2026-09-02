note
	description: "[
		One maximal same-kind stretch of a visual line.

		CLOSED over exactly two heirs by design intent (I-002/G3): GLYPH_RUN
		(text through the shaper) and IMAGE_RUN (emoji through the asset
		path). Color emoji CANNOT travel the glyph path on this renderer
		(research-proven through cairo 1.17.2 win32); the split is therefore
		STRUCTURAL, not stylistic (RISK-003). Do not add heirs.

		Consumers dispatch via object test (attached {GLYPH_RUN} / attached
		{IMAGE_RUN}) or use the paint bridge, which owns that loop.
		Immutable value; the invariant is the frame.
	]"
	author: "Larry Rix"

deferred class
	SHAPED_RUN

inherit
	SHAPING_CONSTANTS

feature -- Access

	source_start: INTEGER
			-- First logical character of this run in the paragraph (1-based).
		deferred
		end

	source_count: INTEGER
			-- Number of logical characters this run covers.
		deferred
		end

	embedding_level: NATURAL_8
			-- Resolved bidi embedding level (UAX #9; even = LTR, odd = RTL).
		deferred
		end

	advance_width: REAL_64
			-- Total advance of this run in pixels at its size.
		deferred
		end

	height: REAL_64
			-- Vertical extent this run demands of its line.
		deferred
		end

	is_rtl: BOOLEAN
			-- Does this run read right-to-left?
		do
			Result := embedding_level \\ 2 = 1
		ensure
			direction_parity: Result = (embedding_level \\ 2 = 1)
		end

invariant
	range_valid: source_start >= 1 and source_count > 0
	advance_non_negative: advance_width >= 0.0
	height_positive: height > 0.0
	level_bounded: embedding_level <= Max_bidi_level

end
