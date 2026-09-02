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

		Phase-1 bodies are inert stubs; zero native code compiles this cycle
		by design.
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
		do
			-- Phase 4: external CreateFontIndirectW over LOGFONTW.
		end

	create_memory_dc: POINTER
			-- Private memory DC (default_pointer on failure).
		do
			-- Phase 4: external CreateCompatibleDC (NULL).
		end

	select_font (a_dc, a_hfont: POINTER): POINTER
			-- Select `a_hfont' into `a_dc'; the previously selected font
			-- (restore before deletion).
		require
			dc_present: a_dc /= default_pointer
			font_present: a_hfont /= default_pointer
		do
			-- Phase 4: external SelectObject.
		end

	text_ascent (a_dc: POINTER): INTEGER
			-- TEXTMETRIC tmAscent of the selected font.
		require
			dc_present: a_dc /= default_pointer
		do
			-- Phase 4: external GetTextMetricsW.
		ensure
			non_negative: Result >= 0
		end

	text_descent (a_dc: POINTER): INTEGER
			-- TEXTMETRIC tmDescent of the selected font.
		require
			dc_present: a_dc /= default_pointer
		do
			-- Phase 4: external GetTextMetricsW.
		ensure
			non_negative: Result >= 0
		end

	realized_face_name (a_dc: POINTER): STRING_32
			-- The face GDI actually selected (the R1 probe's comparator).
		require
			dc_present: a_dc /= default_pointer
		do
			-- Phase 4: external GetTextFaceW.
			create Result.make_empty
		ensure
			never_void: Result /= Void
		end

	delete_handle (a_handle: POINTER): BOOLEAN
			-- Delete a GDI object (HFONT).
		require
			handle_present: a_handle /= default_pointer
		do
			-- Phase 4: external DeleteObject.
		end

	delete_dc (a_dc: POINTER): BOOLEAN
			-- Delete a memory DC.
		require
			dc_present: a_dc /= default_pointer
		do
			-- Phase 4: external DeleteDC.
		end

end
