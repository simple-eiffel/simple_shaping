note
	description: "[
		GDI font realization surface (Phase 4 externals; implementation
		layer). SHAPING_FONT realization runs through here: build a LOGFONTW
		(lfHeight = -pixel_size for character-height sizing), CreateFontIndirectW,
		select into a private memory HDC (CreateCompatibleDC (NULL)), read
		TEXTMETRIC ascent/descent - then DWRITE_API.create_font_face_from_hdc
		turns the selection into the IDWriteFontFace the shaper consumes
		(the spike drove this exact chain with CreateFontW; production
		prefers CreateFontIndirectW because the SAME LOGFONTW must later
		feed cairo_win32_font_face_create_for_logfontw_hfont, D-S03).

		Linking: gdi32.lib via #pragma comment in the shim header - zero new
		DLLs (NFR-004; gdi32 is OS-provided).

		NEVER-RAISES BOUNDARY (NFR-011): every call site checks handles/BOOL
		results; failures surface as default_pointer/False plus notes
		upstream, never exceptions.

		PHASE 4 TASK 1 - THE BODIES ARE REAL. These externals bind
		<windows.h> DIRECTLY and deliberately do NOT include
		Clib/simple_shaping_dwrite.h: that header's shim state is `static',
		so a second translation unit including it would get a SECOND,
		silently divergent copy. GDI32_API holds no native state of its own,
		which is exactly why it is allowed to bind directly.

		`create_font' builds the LOGFONTW in C (lfHeight = -pixel_height, so
		the number is character height rather than cell height) and keeps the
		family name in a caller-owned UTF-16 buffer; the SAME LOGFONTW shape
		must later feed cairo_win32_font_face_create_for_logfontw_hfont
		(D-S03). `realized_face_name' is GetTextFaceW decoded back to
		STRING_32 - the R1 existence probe's comparator, because GDI silently
		maps an unknown family onto a substitute.
	]"
	author: "Larry Rix"

class
	GDI32_API

create
	make

feature {NONE} -- Initialization

	make
			-- Inert surface.
		do
		end

feature -- Fonts

	create_font (a_family: READABLE_STRING_32; a_weight: INTEGER; a_italic: BOOLEAN;
			a_pixel_height: INTEGER): POINTER
			-- HFONT for the identity (default_pointer on failure; GDI maps
			-- unknown families - the R1 existence probe therefore compares
			-- the realized face name, Phase 4).
		require
			family_not_empty: not a_family.is_empty
			weight_range: a_weight >= 1 and a_weight <= 1000
			height_positive: a_pixel_height > 0
		local
			l_name: MANAGED_POINTER
		do
			l_name := utf16_face_name (a_family)
			Result := c_create_font_indirect (l_name.item, a_weight, a_italic, a_pixel_height)
		end

	create_memory_dc: POINTER
			-- Private memory DC (default_pointer on failure).
		do
			Result := c_create_compatible_dc
		end

	select_font (a_dc, a_hfont: POINTER): POINTER
			-- Select `a_hfont' into `a_dc'; the previously selected font
			-- (restore before deletion).
		require
			dc_present: a_dc /= default_pointer
			font_present: a_hfont /= default_pointer
		do
			Result := c_select_object (a_dc, a_hfont)
		end

	text_ascent (a_dc: POINTER): INTEGER
			-- TEXTMETRIC tmAscent of the selected font.
		require
			dc_present: a_dc /= default_pointer
		do
			Result := c_text_ascent (a_dc)
		ensure
			non_negative: Result >= 0
		end

	text_descent (a_dc: POINTER): INTEGER
			-- TEXTMETRIC tmDescent of the selected font.
		require
			dc_present: a_dc /= default_pointer
		do
			Result := c_text_descent (a_dc)
		ensure
			non_negative: Result >= 0
		end

	realized_face_name (a_dc: POINTER): STRING_32
			-- The face GDI actually selected (the R1 probe's comparator).
		require
			dc_present: a_dc /= default_pointer
		local
			l_buffer: MANAGED_POINTER
			l_units: INTEGER
		do
			create l_buffer.make (Face_name_capacity * 2)
			l_units := c_get_text_face (a_dc, l_buffer.item, Face_name_capacity)
			Result := string_from_utf16 (l_buffer, l_units.min (Face_name_capacity))
		ensure
			never_void: Result /= Void
		end

	delete_handle (a_handle: POINTER): BOOLEAN
			-- Delete a GDI object (HFONT).
		require
			handle_present: a_handle /= default_pointer
		do
			Result := c_delete_object (a_handle)
		end

	delete_dc (a_dc: POINTER): BOOLEAN
			-- Delete a memory DC.
		require
			dc_present: a_dc /= default_pointer
		do
			Result := c_delete_dc (a_dc)
		end

feature {NONE} -- Implementation

	Face_name_capacity: INTEGER = 64
			-- [ADDED Phase 4 Task 1] UTF-16 units reserved for a face name.
			-- LF_FACESIZE is 32 including the terminator; 64 leaves room for
			-- whatever GetTextFaceW reports without ever truncating it.

	utf16_face_name (a_family: READABLE_STRING_32): MANAGED_POINTER
			-- [ADDED Phase 4 Task 1] `a_family' as a NUL-terminated UTF-16
			-- buffer sized for LOGFONTW.lfFaceName. Code points above the
			-- BMP cannot appear in a face name and are folded to '?' rather
			-- than emitted as a surrogate pair that lfFaceName would cut in
			-- half.
		require
			family_not_empty: not a_family.is_empty
		local
			l_index, l_limit, l_code: INTEGER
		do
			l_limit := a_family.count.min (Face_name_capacity - 1)
			create Result.make ((l_limit + 1) * 2)
			from l_index := 1 until l_index > l_limit loop
				l_code := a_family.code (l_index).to_integer_32
				if l_code > 0xFFFF or l_code <= 0 then
					l_code := 0x003F
				end
				Result.put_natural_16 (l_code.to_natural_16, (l_index - 1) * 2)
				l_index := l_index + 1
			end
			Result.put_natural_16 (0, l_limit * 2)
		ensure
			never_void: Result /= Void
			room_for_terminator: Result.count >= 2
		end

	string_from_utf16 (a_buffer: MANAGED_POINTER; a_units: INTEGER): STRING_32
			-- [ADDED Phase 4 Task 1] The first `a_units' UTF-16 units of
			-- `a_buffer' decoded to code points, stopping at the first NUL.
			-- Surrogate pairs collapse to ONE code point (the same rule the
			-- DIRECTWRITE_* effectings own for text positions).
		require
			buffer_present: a_buffer.item /= default_pointer
			units_non_negative: a_units >= 0
			units_within_buffer: a_units * 2 <= a_buffer.count
		local
			l_index, l_code, l_trail: INTEGER
			l_done: BOOLEAN
		do
			create Result.make (a_units)
			from l_index := 0 until l_index >= a_units or l_done loop
				l_code := a_buffer.read_natural_16 (l_index * 2).to_integer_32
				if l_code = 0 then
					l_done := True
				else
					if l_code >= 0xD800 and l_code <= 0xDBFF and l_index + 1 < a_units then
						l_trail := a_buffer.read_natural_16 ((l_index + 1) * 2).to_integer_32
						if l_trail >= 0xDC00 and l_trail <= 0xDFFF then
							l_code := 0x10000 + (l_code - 0xD800) * 0x400 + (l_trail - 0xDC00)
							l_index := l_index + 1
						end
					end
					Result.append_code (l_code.to_natural_32)
					l_index := l_index + 1
				end
			end
		ensure
			never_void: Result /= Void
			bounded: Result.count <= a_units
		end

feature {NONE} -- Externals (plain Win32; NEVER the shim header - see the note)

	c_create_font_indirect (a_face_name: POINTER; a_weight: INTEGER; a_italic: BOOLEAN;
			a_pixel_height: INTEGER): POINTER
		external
			"C inline use <windows.h>, <string.h>"
		alias
			"LOGFONTW lf; const unsigned short *src = (const unsigned short *) $a_face_name; int i = 0; memset(&lf, 0, sizeof(lf)); lf.lfHeight = - (LONG) $a_pixel_height; lf.lfWidth = 0; lf.lfWeight = (LONG) $a_weight; lf.lfItalic = (BYTE) ($a_italic ? 1 : 0); lf.lfCharSet = DEFAULT_CHARSET; lf.lfOutPrecision = OUT_TT_PRECIS; lf.lfClipPrecision = CLIP_DEFAULT_PRECIS; lf.lfQuality = DEFAULT_QUALITY; lf.lfPitchAndFamily = DEFAULT_PITCH | FF_DONTCARE; while (i < LF_FACESIZE - 1 && src[i] != 0) { lf.lfFaceName[i] = (WCHAR) src[i]; i++; } lf.lfFaceName[i] = 0; return (EIF_POINTER) CreateFontIndirectW(&lf);"
		end

	c_create_compatible_dc: POINTER
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_POINTER) CreateCompatibleDC(NULL);"
		end

	c_select_object (a_dc, a_object: POINTER): POINTER
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_POINTER) SelectObject((HDC) $a_dc, (HGDIOBJ) $a_object);"
		end

	c_text_ascent (a_dc: POINTER): INTEGER
		external
			"C inline use <windows.h>"
		alias
			"TEXTMETRICW tm; if (GetTextMetricsW((HDC) $a_dc, &tm) && tm.tmAscent > 0) { return (EIF_INTEGER) tm.tmAscent; } return (EIF_INTEGER) 0;"
		end

	c_text_descent (a_dc: POINTER): INTEGER
		external
			"C inline use <windows.h>"
		alias
			"TEXTMETRICW tm; if (GetTextMetricsW((HDC) $a_dc, &tm) && tm.tmDescent > 0) { return (EIF_INTEGER) tm.tmDescent; } return (EIF_INTEGER) 0;"
		end

	c_get_text_face (a_dc: POINTER; a_buffer: POINTER; a_capacity: INTEGER): INTEGER
		external
			"C inline use <windows.h>"
		alias
			"int n = GetTextFaceW((HDC) $a_dc, (int) $a_capacity, (LPWSTR) $a_buffer); if (n < 0) { n = 0; } return (EIF_INTEGER) n;"
		end

	c_delete_object (a_handle: POINTER): BOOLEAN
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_BOOLEAN) (DeleteObject((HGDIOBJ) $a_handle) ? 1 : 0);"
		end

	c_delete_dc (a_dc: POINTER): BOOLEAN
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_BOOLEAN) (DeleteDC((HDC) $a_dc) ? 1 : 0);"
		end

end
