note
	description: "[
		Creates and caches SHAPING_FONTs, on macOS and Linux. Same interface as the
		Windows class of this name (src/fonts). fontconfig finds a family's file; a
		family can also be a file the application loaded. Adapted from simple_eif_phone's
		android_shaping.
	]"
	author: "Larry Rix"

class
	FONT_REGISTRY

inherit
	SHAPING_CONSTANTS

create
	make

feature {NONE} -- Initialization

	make
		do
			create fonts.make (8)
			create family_verdicts.make (8)
			create found_files.make (8)
		ensure
			registry_empty: count = 0
		end

feature -- Access

	count: INTEGER
		do
			Result := fonts.count
		ensure
			non_negative: Result >= 0
		end

	font (a_family: READABLE_STRING_32; a_weight: INTEGER; a_italic: BOOLEAN;
			a_pixel_size: INTEGER): SHAPING_FONT
		require
			family_not_empty: not a_family.is_empty
			weight_range: a_weight >= 1 and a_weight <= 1000
			size_positive: a_pixel_size > 0
		local
			l_key: STRING_32
		do
			l_key := registry_key (a_family, a_weight, a_italic, a_pixel_size)
			if attached fonts.item (l_key) as al_font then
				Result := al_font
			else
				create Result.make (a_family, a_weight, a_italic, a_pixel_size, Current)
				fonts.put (Result, l_key)
			end
			if not Result.is_realization_attempted then
				Result.realize (file_for (a_family, a_weight, a_italic), last_face_index)
			end
		ensure
			owned: Result.registry = Current
			realized_on_first_use: Result.is_realization_attempted
		end

	registry_key (a_family: READABLE_STRING_32; a_weight: INTEGER; a_italic: BOOLEAN;
			a_pixel_size: INTEGER): STRING_32
		require
			family_not_empty: not a_family.is_empty
		do
			create Result.make (a_family.count + 12)
			Result.append_string_general (a_family.as_lower)
			Result.append_character ('|')
			Result.append_string_general (a_weight.out)
			Result.append_character ('|')
			if a_italic then
				Result.append_character ('1')
			else
				Result.append_character ('0')
			end
			Result.append_character ('|')
			Result.append_string_general (a_pixel_size.out)
		ensure
			never_empty: not Result.is_empty
		end

	family_exists (a_family: READABLE_STRING_32): BOOLEAN
		require
			family_not_empty: not a_family.is_empty
		local
			l_key: STRING_32
		do
			l_key := a_family.as_string_32.as_lower
			if family_verdicts.has (l_key) then
				Result := family_verdicts.item (l_key)
			else
				Result := not file_for (a_family, 400, False).is_empty
				family_verdicts.put (Result, l_key)
			end
		end

	verdict_count: INTEGER
		do
			Result := family_verdicts.count
		ensure
			non_negative: Result >= 0
		end

feature -- Commands

	load_private_font_file (a_path: READABLE_STRING_GENERAL): INTEGER
			-- Make the font's own family name, as Windows registers it, and the file's
			-- name without its extension, families of this process.
		require
			path_not_empty: not a_path.is_empty
		local
			l_path: PATH
			l_name: STRING_32
			l_c_path, l_family: C_STRING
		do
			create l_path.make_from_string (a_path)
			if (create {RAW_FILE}.make_with_path (l_path)).exists and then attached l_path.entry as al_entry then
				l_name := al_entry.name.to_string_32
				if l_name.has ('.') then
					l_name.keep_head (l_name.last_index_of ('.', l_name.count) - 1)
				end
				private_files.force (a_path.to_string_8, l_name.as_lower)
				create l_c_path.make (a_path.to_string_8)
				create l_family.make_empty (Path_capacity)
				if c_file_family (l_c_path.item, l_family.item, Path_capacity) /= 0 then
					private_files.force (a_path.to_string_8, l_family.string.as_lower)
				end
				found_files.wipe_out
				private_loads.force (private_loads.item (a_path.to_string_8) + 1, a_path.to_string_8)
				Result := 1
			end
			forget_family_verdicts
		ensure
			non_negative: Result >= 0
			verdicts_forgotten: verdict_count = 0
		end

	unload_private_font_file (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Give back one load of `a_path', as Windows's RemoveFontResourceEx does; True
			-- if it was loaded. Its families go when the last load is given back.
		require
			path_not_empty: not a_path.is_empty
		local
			l_gone: ARRAYED_LIST [STRING_32]
			l_loads: INTEGER
		do
			create l_gone.make (2)
			l_loads := private_loads.item (a_path.to_string_8)
			Result := l_loads > 0
			if l_loads > 1 then
				private_loads.force (l_loads - 1, a_path.to_string_8)
			else
				private_loads.remove (a_path.to_string_8)
			across private_files as ic loop
				if ic.same_string_general (a_path) then
					l_gone.extend (@ic.key)
				end
			end
			across l_gone as ic loop
				private_files.remove (ic)
			end
			end
			found_files.wipe_out
			forget_family_verdicts
		ensure
			verdicts_forgotten: verdict_count = 0
		end

	forget_family_verdicts
		do
			family_verdicts.wipe_out
		ensure
			forgotten: verdict_count = 0
		end

	dispose_all
		do
			across fonts as f loop
				f.dispose
			end
			fonts.wipe_out
		ensure
			count_zero: count = 0
		end

feature -- Model queries (simple_mml)

	fonts_model: MML_MAP [STRING_32, SHAPING_FONT]
		do
			create Result
			across fonts as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		end

feature {NONE} -- Implementation

	fonts: HASH_TABLE [SHAPING_FONT, STRING_32]

	family_verdicts: HASH_TABLE [BOOLEAN, STRING_32]

	private_files: HASH_TABLE [STRING_8, STRING_32]
			-- Fonts the app loaded, by family. Shared by every registry on this processor,
			-- as Windows's FR_PRIVATE fonts are.
		once
			create Result.make (2)
		end

	private_loads: HASH_TABLE [INTEGER, STRING_8]
			-- How many loads of each private file are held, shared the same way.
		once
			create Result.make (2)
		end

	file_for (a_family: READABLE_STRING_32; a_weight: INTEGER; a_italic: BOOLEAN): STRING_8
			-- The font file for `a_family' (its face index in `last_face_index'); empty
			-- if there is none. A family the system has is used as it is. The Windows
			-- family names simple_shaping asks for by default map to fontconfig's
			-- generic families, so they draw with the system's own sans, serif or
			-- monospace font; the Hebrew ones also ask for a font that draws Hebrew.
		local
			l_family: STRING_32
			l_key: STRING_8
		do
			l_family := a_family.as_string_32.as_lower
			l_key := l_family.to_string_8 + "|" + a_weight.out + "|" + a_italic.out
			last_face_index := 0
			if attached private_files.item (l_family) as al_file then
				Result := al_file
			elseif attached found_files.item (l_key) as al_found then
				Result := al_found.path
				last_face_index := al_found.index
			else
				Result := fontconfig_file (a_family.to_string_8, a_weight, a_italic, 0, True)
				if Result.is_empty then
					if l_family.same_string_general ("segoe ui") then
							-- Segoe UI covers Hebrew, Greek and Cyrillic as well as Latin:
							-- macOS's Arial does too, and fontconfig finds a sans that does elsewhere.
						Result := fontconfig_file ("Arial", a_weight, a_italic, Hebrew_sample, False)
						if Result.is_empty then
							Result := fontconfig_file ("sans-serif", a_weight, a_italic, Latin_sample, False)
						end
					elseif l_family.same_string_general ("arial") or l_family.same_string_general ("roboto") then
						Result := fontconfig_file ("sans-serif", a_weight, a_italic, Latin_sample, False)
					elseif l_family.same_string_general ("noto sans hebrew") then
						Result := fontconfig_file ("sans-serif", a_weight, a_italic, Hebrew_sample, False)
					elseif l_family.same_string_general ("noto serif hebrew") then
						Result := fontconfig_file ("serif", a_weight, a_italic, Hebrew_sample, False)
					elseif l_family.same_string_general ("times new roman") or l_family.same_string_general ("palatino linotype") then
						Result := fontconfig_file ("serif", a_weight, a_italic, Latin_sample, False)
					elseif l_family.same_string_general ("consolas") or l_family.same_string_general ("courier new") then
						Result := fontconfig_file ("monospace", a_weight, a_italic, Latin_sample, False)
					end
				end
				found_files.put ([Result, last_face_index], l_key)
			end
		end

	last_face_index: INTEGER
			-- Face index within the file `file_for' last answered (a .ttc holds several).

	fontconfig_file (a_family: STRING_8; a_weight: INTEGER; a_italic: BOOLEAN; a_code: NATURAL_32;
			a_exact_only: BOOLEAN): STRING_8
			-- fontconfig's file for `a_family' that draws `a_code' (0: any), setting
			-- `last_face_index'; empty if there is none, or if `a_exact_only' and the
			-- match is a substitute rather than `a_family' itself.
		local
			l_family, l_out: C_STRING
			l_index, l_exact: INTEGER
		do
			create Result.make_empty
			create l_family.make (a_family)
			create l_out.make_empty (Path_capacity)
			if c_find_font (l_family.item, a_weight.max (1).min (1000), a_italic.to_integer, a_code,
				l_out.item, Path_capacity, $l_index, $l_exact) /= 0
				and then (l_exact /= 0 or not a_exact_only)
			then
				Result := l_out.string
				last_face_index := l_index
			end
		end

	found_files: HASH_TABLE [TUPLE [path: STRING_8; index: INTEGER], STRING_8]
			-- Answers of `file_for', by family, weight and slant.

	Path_capacity: INTEGER = 4096

	Latin_sample: NATURAL_32 = 0x41

	Hebrew_sample: NATURAL_32 = 0x5D0

feature {NONE} -- C

	c_file_family (a_path, a_out: POINTER; a_out_size: INTEGER): INTEGER
		external "C inline use %"simple_shaping_posix.h%""
		alias "return (EIF_INTEGER) st_file_family((const char *)$a_path, (char *)$a_out, (int)$a_out_size);"
		end

	c_find_font (a_family: POINTER; a_weight, a_italic: INTEGER; a_code: NATURAL_32;
			a_out: POINTER; a_out_size: INTEGER; a_index, a_exact: TYPED_POINTER [INTEGER]): INTEGER
		external "C inline use %"simple_shaping_posix.h%""
		alias "return (EIF_INTEGER) st_find_font((const char *)$a_family, (int)$a_weight, (int)$a_italic, (uint32_t)$a_code, (char *)$a_out, (int)$a_out_size, (int *)$a_index, (int *)$a_exact);"
		end

end
