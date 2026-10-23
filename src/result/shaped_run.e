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

	joins_next: BOOLEAN
			-- Must the run after this one (logical order) stay on the same
			-- line? True where a style change (SHAPING_STYLES) cut a word
			-- that the text itself could not break: "beginning" and its
			-- raised Strong's number, the "L" and "ORD" of a small-caps
			-- LORD. LINE_LAYOUT_ENGINE wraps a glued chain as one unit.

	is_rtl: BOOLEAN
			-- Does this run read right-to-left?
		do
			Result := embedding_level \\ 2 = 1
		ensure
			direction_parity: Result = (embedding_level \\ 2 = 1)
		end

feature -- Construction (GW-08)

	glue_to_next
			-- Keep the next run on this run's line. Construction-time
			-- only: the facade calls it before the run reaches any line,
			-- and nothing ever un-glues a run.
		do
			joins_next := True
		ensure
			glued: joins_next
		end

invariant
	range_valid: source_start >= 1 and source_count > 0
	advance_non_negative: advance_width >= 0.0
	height_positive: height > 0.0
	level_bounded: embedding_level <= Max_bidi_level

end
