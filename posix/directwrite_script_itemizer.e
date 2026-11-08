note
	description: "[
		Script runs on Android, from HarfBuzz's Unicode data. Keeps simple_shaping's
		DirectWrite name: see DIRECTWRITE_BIDI_RESOLVER. Lines may break after a
		space, a hyphen or a maqaf; languages that need a dictionary to find their
		breaks do not get them.
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
		do
			create no_analysis.make_empty
		end

feature -- Operations

	itemize (a_text: READABLE_STRING_32; a_start, a_count: INTEGER;
			a_bidi: BIDI_RESULT): ARRAYED_LIST [SCRIPT_ITEM]
			-- <Precursor>
		local
			i, l_from, l_script, l_next: INTEGER
			l_level, l_next_level: NATURAL_8
		do
			create Result.make (2)
			if a_count > 0 then
				l_from := a_start
				l_script := first_script (a_text, a_start, a_start + a_count - 1)
				l_level := a_bidi.level (a_start)
				from i := a_start + 1 until i > a_start + a_count - 1 loop
					l_next := script_at (a_text, i, l_script)
					l_next_level := a_bidi.level (i)
					if l_next /= l_script or l_next_level /= l_level then
						Result.extend (create {SCRIPT_ITEM}.make (l_from, i - l_from, l_script, l_level, no_analysis))
						l_from := i
						l_script := l_next
						l_level := l_next_level
					end
					i := i + 1
				end
				Result.extend (create {SCRIPT_ITEM}.make (l_from, a_start + a_count - l_from, l_script, l_level, no_analysis))
			end
		end

	soft_breaks (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM): ARRAY [BOOLEAN]
			-- <Precursor>
		local
			i: INTEGER
			l_before, l_here: NATURAL_32
		do
			create Result.make_filled (False, 1, a_item.count)
			from i := 2 until i > a_item.count loop
				l_before := a_text.code (a_item.start_index + i - 2)
				l_here := a_text.code (a_item.start_index + i - 1)
				Result [i] := (l_before = 32 or l_before = 9 or l_before = 45 or l_before = 0x05BE or l_before = 0x2010)
					and l_here /= 32
				i := i + 1
			end
		end

feature {NONE} -- Implementation

	no_analysis: ARRAY [NATURAL_8]

	script_at (a_text: READABLE_STRING_32; a_index, a_previous: INTEGER): INTEGER
			-- The script at `a_index'. Spaces and marks belong to the run they sit in.
		do
			Result := c_script (a_text.code (a_index))
			if Result = c_common or Result = c_inherited then
				Result := a_previous
			end
		end

	first_script (a_text: READABLE_STRING_32; a_first, a_last: INTEGER): INTEGER
			-- The first real script from `a_first' to `a_last'; Latin if there is none.
		local
			i, l_script: INTEGER
		do
			Result := c_latin
			from i := a_first until i > a_last loop
				l_script := c_script (a_text.code (i))
				if l_script /= c_common and l_script /= c_inherited then
					Result := l_script
					i := a_last
				end
				i := i + 1
			end
		end

feature {NONE} -- C

	c_script (a_code: NATURAL_32): INTEGER
		external "C inline use %"simple_shaping_posix.h%"" alias "return (EIF_INTEGER) st_script((uint32_t)$a_code);" end

	c_common: INTEGER
		external "C inline use %"simple_shaping_posix.h%"" alias "return (EIF_INTEGER) st_script_common();" end

	c_inherited: INTEGER
		external "C inline use %"simple_shaping_posix.h%"" alias "return (EIF_INTEGER) st_script_inherited();" end

	c_latin: INTEGER
		external "C inline use %"simple_shaping_posix.h%"" alias "return (EIF_INTEGER) st_script_latin();" end

end
