note
	description: "[
		THE CODE-POINT <-> UTF-16 BOUNDARY, factored (Phase 4 Task 4).

		The DirectWrite shim speaks UTF-16 code units; every simple_shaping
		seam speaks CODE POINTS (READABLE_STRING_32 positions, 1-based). The
		translation between them is the single most likely silent-wrong-answer
		site in the backend - Task 3 said so in DIRECTWRITE_BIDI_RESOLVER's
		note and proved it with a dedicated test - so it is written ONCE here
		and inherited by the backend classes that need it.

		The rule, in three steps, is always the same:

		  1. `first_units' walks the span's code points and records, per code
		     point, the 0-BASED index of its FIRST UTF-16 unit. A code point
		     above U+FFFF occupies TWO units, so the map is strictly
		     increasing but not contiguous.
		  2. `utf16_span' fills the buffer the shim analyzes, hand-building
		     the surrogate halves at exactly the offsets step 1 recorded.
		  3. The caller spreads whatever the shim reports over a per-UNIT
		     array and then reads ONE answer per CODE POINT at that code
		     point's FIRST unit.

		A surrogate pair therefore lands as ONE code point - never two, never
		a half, and never an off-by-one that shifts everything after it. The
		dwrite spike measured the D-015 probe at 18 code points = 19 units;
		that one extra unit is the whole hazard.

		EXPORT STATUS: every feature is {NONE}. This class is a set of
		implementation helpers for its heirs, never a client surface, and it
		makes no native call of its own - it holds no DWRITE_API and touches
		no shim state, so it stays safe to inherit anywhere.

		HISTORY: DIRECTWRITE_BIDI_RESOLVER (Task 3, merged) still carries its
		own private copy of steps 1 and 2 inside `resolved_levels' and
		`probe_level'. It is deliberately NOT rewritten here: Task 4 does not
		touch a merged, contract-frozen file to refactor it. Rebasing it onto
		this class is a mechanical, behavior-free change for a later pass.
	]"
	author: "Larry Rix"
	never_raises: "Pure Eiffel arithmetic over the caller's text; no native call, no failure channel."

class
	DIRECTWRITE_UTF16_MAPPING

feature {NONE} -- The UTF-16 boundary

	unit_count (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): INTEGER
			-- UTF-16 code units taken by `a_text' [`a_start' ..
			-- `a_start' + `a_count' - 1] - one per code point, TWO for a
			-- code point above U+FFFF.
		require
			span_valid: a_start >= 1 and a_count >= 0 and a_start + a_count - 1 <= a_text.count
		local
			i: INTEGER
		do
			from i := 1 until i > a_count loop
				if a_text.code (a_start + i - 1).to_integer_32 > 0xFFFF then
					Result := Result + 2
				else
					Result := Result + 1
				end
				i := i + 1
			end
		ensure
			at_least_one_unit_per_code_point: Result >= a_count
			at_most_two_units_per_code_point: Result <= 2 * a_count
			empty_span_no_units: a_count = 0 implies Result = 0
		end

	first_units (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): ARRAY [INTEGER]
			-- Per code point of the span (entry `i' = code point
			-- `a_start' + `i' - 1), the 0-BASED index of its FIRST UTF-16
			-- unit WITHIN THE SPAN. This map IS the boundary; every read-back
			-- goes through it.
		require
			span_valid: a_start >= 1 and a_count >= 0 and a_start + a_count - 1 <= a_text.count
		local
			i, n: INTEGER
		do
			create Result.make_filled (0, 1, a_count)
			from i := 1 until i > a_count loop
				Result [i] := n
				if a_text.code (a_start + i - 1).to_integer_32 > 0xFFFF then
					n := n + 2
				else
					n := n + 1
				end
				i := i + 1
			end
		ensure
			one_per_code_point: Result.count = a_count
			one_based: Result.lower = 1
			span_starts_at_zero: a_count > 0 implies Result [1] = 0
			strictly_ordered: across 1 |..| (Result.count - 1) as k all
				Result [k + 1] > Result [k] end
			inside_the_buffer: a_count > 0 implies
				Result [Result.count] < unit_count (a_text, a_start, a_count)
		end

	utf16_span (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): MANAGED_POINTER
			-- The span `a_text' [`a_start' .. `a_start' + `a_count' - 1]
			-- marshalled as UTF-16 for the shim, surrogate halves hand-built
			-- at the offsets `first_units' recorded.
		require
			span_valid: a_start >= 1 and a_count >= 0 and a_start + a_count - 1 <= a_text.count
			span_present: a_count > 0
		local
			l_first: ARRAY [INTEGER]
			i, l_code, l_offset: INTEGER
		do
			l_first := first_units (a_text, a_start, a_count)
			create Result.make (unit_count (a_text, a_start, a_count) * 2)
			from i := 1 until i > a_count loop
				l_code := a_text.code (a_start + i - 1).to_integer_32
				if l_code > 0xFFFF then
					l_offset := l_code - 0x10000
					Result.put_natural_16 ((0xD800 + l_offset.bit_shift_right (10)).to_natural_16,
						l_first [i] * 2)
					Result.put_natural_16 ((0xDC00 + l_offset.bit_and (0x3FF)).to_natural_16,
						(l_first [i] + 1) * 2)
				else
					Result.put_natural_16 (l_code.to_natural_16, l_first [i] * 2)
				end
				i := i + 1
			end
		ensure
			sized: Result.count >= unit_count (a_text, a_start, a_count) * 2
			buffer_present: Result.item /= default_pointer
		end

end
