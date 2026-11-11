note
	description: "[
		The family names a font file carries, read from its `name' table
		without loading the font: TrueType and OpenType files (.ttf, .otf)
		and collections of them (.ttc, .otc).

		WHY IT EXISTS. `SIMPLE_SHAPING.load_font_file' makes a file's faces
		available but answers only how many; an application that ships a
		face must also learn what to call it. The names are in the file, so
		this reads them there, the same way on every platform.

		WHICH NAMES. Per face, the typographic family (name 16) where the
		file has one, then the legacy family (name 1): the first is what
		DirectWrite, Pango and Core Text call the family, the second is
		what GDI calls it. They are the same string in most files. Each
		distinct name is listed once.

		NEVER RAISES: a missing, unreadable, truncated or foreign file gives
		an empty list and `is_font' False. Every offset is checked against
		the file before it is read, and only the tables asked for are read,
		never the whole file.
	]"
	author: "Larry Rix"

class
	FONT_FILE_NAMES

create
	make

feature {NONE} -- Initialization

	make (a_path: READABLE_STRING_GENERAL)
			-- Read the family names of the font file at `a_path'.
		require
			path_not_empty: not a_path.is_empty
		do
			create families.make (2)
			families.compare_objects
			read (a_path)
		ensure
			names_only_from_a_font: not is_font implies families.is_empty
		end

feature -- Access

	families: ARRAYED_LIST [STRING_32]
			-- The distinct family names, in the file's order of faces; per face the
			-- typographic family before the legacy one. Empty when the file is not a
			-- font this reads.

feature -- Status

	is_font: BOOLEAN
			-- Did the file hold at least one TrueType or OpenType face?

feature {NONE} -- Reading

	read (a_path: READABLE_STRING_GENERAL)
			-- Fill `families' from the file at `a_path'; leave it empty on any failure.
		local
			l_file: detachable RAW_FILE
			l_head: detachable MANAGED_POINTER
			l_offsets: detachable MANAGED_POINTER
			l_faces: INTEGER_64
			i: INTEGER
			l_failed: BOOLEAN
		do
			if l_failed then
				families.wipe_out
				is_font := False
			else
				create l_file.make_with_name (a_path)
				if l_file.exists and then l_file.is_readable then
					l_file.open_read
					l_head := block (l_file, 0, 12)
					if l_head /= Void then
						if l_head.read_natural_32_be (0) = Tag_collection then
							l_faces := l_head.read_natural_32_be (8).to_integer_64
							if l_faces >= 1 and l_faces <= Max_faces then
								l_offsets := block (l_file, 12, l_faces.to_integer_32 * 4)
							end
							if l_offsets /= Void then
								from i := 0 until i = l_faces.to_integer_32 loop
									read_face (l_file, l_offsets.read_natural_32_be (i * 4).to_integer_64)
									i := i + 1
								end
							end
						else
							read_face (l_file, 0)
						end
					end
				end
			end
			if l_file /= Void and then not l_file.is_closed then
				l_file.close
			end
		rescue
			if not l_failed then
				l_failed := True
				retry
			end
		end

	read_face (a_file: RAW_FILE; a_offset: INTEGER_64)
			-- Add the family names of the face whose table directory starts at `a_offset'.
		require
			open: a_file.is_open_read
		local
			l_head, l_directory: detachable MANAGED_POINTER
			l_tag: NATURAL_32
			l_tables, i: INTEGER
		do
			l_head := block (a_file, a_offset, 12)
			if l_head /= Void then
				l_tag := l_head.read_natural_32_be (0)
				if l_tag = Tag_truetype or l_tag = Tag_opentype or l_tag = Tag_apple then
					is_font := True
					l_tables := l_head.read_natural_16_be (4).to_integer_32
					l_directory := block (a_file, a_offset + 12, l_tables * 16)
					if l_directory /= Void then
						from i := 0 until i = l_tables loop
							if l_directory.read_natural_32_be (i * 16) = Tag_name then
								read_names (a_file, l_directory.read_natural_32_be (i * 16 + 8).to_integer_64,
									l_directory.read_natural_32_be (i * 16 + 12).to_integer_64)
							end
							i := i + 1
						end
					end
				end
			end
		end

	read_names (a_file: RAW_FILE; a_offset, a_length: INTEGER_64)
			-- Add the family names of the `name' table of `a_length' bytes at `a_offset'.
		require
			open: a_file.is_open_read
		local
			l_table: detachable MANAGED_POINTER
			l_count, l_strings, l_id, l_wanted, i: INTEGER
		do
			if a_length >= 6 and a_length <= Max_name_table then
				l_table := block (a_file, a_offset, a_length.to_integer_32)
			end
			if l_table /= Void then
				l_count := l_table.read_natural_16_be (2).to_integer_32
				l_strings := l_table.read_natural_16_be (4).to_integer_32
				if 6 + l_count * 12 <= l_table.count then
					from l_wanted := Name_typographic_family until l_wanted = 0 loop
						from i := 0 until i = l_count loop
							l_id := l_table.read_natural_16_be (6 + i * 12 + 6).to_integer_32
							if l_id = l_wanted and then attached name_at (l_table, 6 + i * 12, l_strings) as al_name
								and then not al_name.is_empty and then not families.has (al_name)
							then
								families.extend (al_name)
							end
							i := i + 1
						end
						if l_wanted = Name_typographic_family then
							l_wanted := Name_family
						else
							l_wanted := 0
						end
					end
				end
			end
		end

	name_at (a_table: MANAGED_POINTER; a_record, a_strings: INTEGER): detachable STRING_32
			-- The string of the name record at `a_record' in `a_table', whose strings start
			-- at `a_strings'; Void when it lies outside the table or is in an encoding this
			-- does not read (anything but UTF-16 and plain ASCII in Mac Roman).
		require
			record_in_table: a_record >= 0 and a_record + 12 <= a_table.count
		local
			l_platform, l_encoding, l_length, l_from, i: INTEGER
			l_plain: BOOLEAN
		do
			l_platform := a_table.read_natural_16_be (a_record).to_integer_32
			l_encoding := a_table.read_natural_16_be (a_record + 2).to_integer_32
			l_length := a_table.read_natural_16_be (a_record + 8).to_integer_32
			l_from := a_strings + a_table.read_natural_16_be (a_record + 10).to_integer_32
			if l_length > 0 and l_from + l_length <= a_table.count then
				if l_platform = Platform_unicode or l_platform = Platform_windows then
					if l_length \\ 2 = 0 then
						Result := utf_16_be (a_table, l_from, l_length)
					end
				elseif l_platform = Platform_mac and l_encoding = 0 then
					from
						l_plain := True
						i := 0
					until
						i = l_length or not l_plain
					loop
						l_plain := a_table.read_natural_8 (l_from + i) < 0x80
						i := i + 1
					end
					if l_plain then
						create Result.make (l_length)
						from i := 0 until i = l_length loop
							Result.append_code (a_table.read_natural_8 (l_from + i))
							i := i + 1
						end
					end
				end
			end
		end

	utf_16_be (a_table: MANAGED_POINTER; a_from, a_length: INTEGER): STRING_32
			-- The `a_length' bytes at `a_from' as big-endian UTF-16. A surrogate with no
			-- partner becomes the replacement character.
		require
			in_table: a_from >= 0 and a_length >= 0 and a_from + a_length <= a_table.count
			whole_units: a_length \\ 2 = 0
		local
			i: INTEGER
			l_unit, l_low: NATURAL_32
		do
			create Result.make (a_length // 2)
			from i := 0 until i >= a_length loop
				l_unit := a_table.read_natural_16_be (a_from + i)
				i := i + 2
				if l_unit >= 0xD800 and l_unit <= 0xDFFF then
					l_low := 0
					if l_unit <= 0xDBFF and i < a_length then
						l_low := a_table.read_natural_16_be (a_from + i)
					end
					if l_low >= 0xDC00 and l_low <= 0xDFFF then
						l_unit := 0x10000 + ((l_unit - 0xD800) |<< 10) + (l_low - 0xDC00)
						i := i + 2
					else
						l_unit := 0xFFFD
					end
				end
				Result.append_code (l_unit)
			end
		ensure
			no_longer_than_its_units: Result.count <= a_length // 2
		end

	block (a_file: RAW_FILE; a_offset: INTEGER_64; a_count: INTEGER): detachable MANAGED_POINTER
			-- The `a_count' bytes at `a_offset' of `a_file'; Void when they are not all there.
		require
			open: a_file.is_open_read
		do
			if a_offset >= 0 and a_count > 0 and then a_offset + a_count <= a_file.count then
				a_file.go (a_offset.to_integer_32)
				create Result.make (a_count)
				a_file.read_to_managed_pointer (Result, 0, a_count)
				if a_file.bytes_read /= a_count then
					Result := Void
				end
			end
		ensure
			whole: Result /= Void implies Result.count = a_count
		end

feature {NONE} -- Constants

	Tag_collection: NATURAL_32 = 0x74746366
			-- "ttcf": a collection of faces.

	Tag_truetype: NATURAL_32 = 0x00010000
			-- A face with TrueType outlines.

	Tag_opentype: NATURAL_32 = 0x4F54544F
			-- "OTTO": a face with CFF outlines.

	Tag_apple: NATURAL_32 = 0x74727565
			-- "true": a TrueType face as older Apple tools wrote it.

	Tag_name: NATURAL_32 = 0x6E616D65
			-- "name": the naming table.

	Name_family: INTEGER = 1
			-- The legacy family (what GDI calls the family).

	Name_typographic_family: INTEGER = 16
			-- The typographic family, where it differs from the legacy one.

	Platform_unicode: INTEGER = 0
	Platform_mac: INTEGER = 1
	Platform_windows: INTEGER = 3
			-- The name records' platforms. Unicode and Windows strings are UTF-16.

	Max_faces: INTEGER_64 = 1024
			-- The most faces read from one collection.

	Max_name_table: INTEGER_64 = 4194304
			-- The longest `name' table read, in bytes (4 megabytes).

invariant
	names_compared_by_content: families.object_comparison

end
