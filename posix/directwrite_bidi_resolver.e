note
	description: "[
		Bidi on Android, through FriBidi. simple_shaping creates its backends
		under the DirectWrite names, so this cluster keeps those names: an ECF
		selects this class in place of the Windows one, and simple_shaping
		stays unchanged.
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
		do
		end

feature -- Operations

	resolve (a_text: READABLE_STRING_32; a_base_direction: INTEGER): BIDI_RESULT
			-- <Precursor>
		local
			l_text: MANAGED_POINTER
			l_levels: MANAGED_POINTER
			l_result: ARRAY [NATURAL_8]
			l_paragraph, i, l_count: INTEGER
		do
			l_count := a_text.count
			create l_result.make_filled (0, 1, l_count)
			if l_count = 0 then
				if a_base_direction = Direction_rtl then
					l_paragraph := 1
				end
			else
				create l_text.make (l_count * 4)
				create l_levels.make (l_count)
				from i := 1 until i > l_count loop
					l_text.put_natural_32 (a_text.code (i), (i - 1) * 4)
					i := i + 1
				end
				l_paragraph := c_bidi (l_text.item, l_count, a_base_direction, l_levels.item)
				from i := 1 until i > l_count loop
					l_result [i] := l_levels.read_natural_8 (i - 1).min (Max_bidi_level)
					i := i + 1
				end
			end
			create Result.make (l_result, l_paragraph.to_natural_8)
		end

	reorder (a_levels: ARRAY [NATURAL_8]): ARRAY [INTEGER]
			-- <Precursor> The rule of UAX #9 L2.
		local
			i, j, l_lower, l_upper, l_swap: INTEGER
			l_highest, l_lowest_odd, l_level: NATURAL_8
		do
			create Result.make_filled (0, 1, a_levels.count)
			l_lowest_odd := 255
			from i := 1 until i > a_levels.count loop
				Result [i] := i
				l_level := a_levels [a_levels.lower + i - 1]
				l_highest := l_highest.max (l_level)
				if l_level \\ 2 = 1 then
					l_lowest_odd := l_lowest_odd.min (l_level)
				end
				i := i + 1
			end
			if l_lowest_odd /= 255 then
				from l_level := l_highest until l_level < l_lowest_odd loop
					from i := 1 until i > a_levels.count loop
						if a_levels [a_levels.lower + Result [i] - 1] >= l_level then
							l_lower := i
							from j := i until j > a_levels.count or else a_levels [a_levels.lower + Result [j] - 1] < l_level loop
								j := j + 1
							end
							l_upper := j - 1
							from until l_lower >= l_upper loop
								l_swap := Result [l_lower]
								Result [l_lower] := Result [l_upper]
								Result [l_upper] := l_swap
								l_lower := l_lower + 1
								l_upper := l_upper - 1
							end
							i := j
						else
							i := i + 1
						end
					end
					l_level := l_level - 1
				end
			end
		end

feature {NONE} -- C

	c_bidi (a_text: POINTER; a_count, a_direction: INTEGER; a_levels: POINTER): INTEGER
		external "C inline use %"simple_shaping_posix.h%"" alias "return (EIF_INTEGER) st_bidi((const uint32_t *)$a_text, (int)$a_count, (int)$a_direction, (uint8_t *)$a_levels);" end

end
