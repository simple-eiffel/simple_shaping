note
	description: "[
		One (family, weight, style, pixel size) realization, on macOS and Linux: a font
		file opened for HarfBuzz, FreeType and cairo. Same interface as the Windows class
		of this name (src/fonts); its GDI handles are always null here. Adapted from
		simple_eif_phone's android_shaping. Glyph ids from the shaper
		and ids cairo draws are one id space, because both read the same file.
	]"
	author: "Larry Rix"

class
	SHAPING_FONT

create {FONT_REGISTRY}
	make

feature {NONE} -- Initialization

	make (a_family: READABLE_STRING_32; a_weight: INTEGER; a_italic: BOOLEAN;
			a_pixel_size: INTEGER; a_registry: FONT_REGISTRY)
			-- Unrealized identity.
		require
			family_not_empty: not a_family.is_empty
			weight_range: a_weight >= 1 and a_weight <= 1000
			size_positive: a_pixel_size > 0
		do
			create family.make_from_string_general (a_family)
			weight := a_weight
			is_italic := a_italic
			pixel_size := a_pixel_size
			registry := a_registry
		ensure
			family_kept: family.same_string_general (a_family)
			style_kept: weight = a_weight and is_italic = a_italic
			size_kept: pixel_size = a_pixel_size
			owner_registered: registry = a_registry
			unrealized: not is_ready
			no_face_yet: not has_cairo_face
		end

feature -- Constants

	Weight_regular: INTEGER = 400

	Weight_bold: INTEGER = 700

feature -- Access

	family: IMMUTABLE_STRING_32

	weight: INTEGER

	is_italic: BOOLEAN

	pixel_size: INTEGER

	registry: FONT_REGISTRY

	ascent: REAL_64

	descent: REAL_64

	line_height: REAL_64
		require
			realized: is_ready
		do
			Result := ascent + descent
		ensure
			metric: Result = ascent + descent
		end

	realized_family: IMMUTABLE_STRING_32
			-- The family, once its file has opened.
		attribute
			create Result.make_empty
		end

	backend_face: POINTER
			-- The open font; null until realized.

	font_handle: POINTER
			-- The Windows HFONT; there is none off Windows.
		do
		end

	device_context: POINTER
			-- The Windows memory DC; there is none off Windows.
		do
		end

feature -- Status

	is_ready: BOOLEAN

	has_cairo_face: BOOLEAN

	is_realization_attempted: BOOLEAN

	has_backend_face: BOOLEAN
		do
			Result := backend_face /= default_pointer
		ensure
			definition: Result = (backend_face /= default_pointer)
		end

	is_family_realized: BOOLEAN
		do
			Result := is_ready and then realized_family.is_case_insensitive_equal (family)
		ensure
			needs_realization: Result implies is_ready
		end

feature -- Paint bridge

	cairo_face: CAIRO_FONT_FACE
			-- The cairo face over this font's file, built on the first ask.
		require
			realized: is_ready
		do
			if attached internal_cairo_face as al_face then
				Result := al_face
			else
				create Result.make_for_hfont (c_cairo_face (backend_face))
				internal_cairo_face := Result
				has_cairo_face := True
			end
		ensure
			created: has_cairo_face
		end

feature {FONT_REGISTRY} -- Realization

	realize (a_file: READABLE_STRING_8; a_index: INTEGER)
			-- Open face `a_index' of `a_file'. A file that cannot be used leaves this font not ready.
		local
			l_path: C_STRING
		do
			is_realization_attempted := True
			if not a_file.is_empty then
				create l_path.make (a_file)
				backend_face := c_open (l_path.item, a_index, weight, is_italic.to_integer)
				if backend_face /= default_pointer then
					ascent := c_ascent (backend_face, pixel_size)
					descent := c_descent (backend_face, pixel_size)
					if ascent > 0.0 then
						is_ready := True
						create realized_family.make_from_string_general (family)
					end
				end
			end
		ensure
			attempted: is_realization_attempted
		end

	dispose
			-- Let go of the file.
		do
			if backend_face /= default_pointer then
				c_close (backend_face)
			end
			backend_face := default_pointer
			internal_cairo_face := Void
			has_cairo_face := False
			is_ready := False
			is_realization_attempted := False
			ascent := 0.0
			descent := 0.0
		end

feature {NONE} -- Implementation

	internal_cairo_face: detachable CAIRO_FONT_FACE

feature {NONE} -- C

	c_open (a_path: POINTER; a_index, a_weight, a_italic: INTEGER): POINTER
		external "C inline use %"simple_shaping_posix.h%"" alias "return st_font_open((const char *)$a_path, (int)$a_index, (int)$a_weight, (int)$a_italic);" end

	c_close (a_font: POINTER)
		external "C inline use %"simple_shaping_posix.h%"" alias "st_font_close($a_font);" end

	c_ascent (a_font: POINTER; a_size: INTEGER): REAL_64
		external "C inline use %"simple_shaping_posix.h%"" alias "return st_font_ascent($a_font, (int)$a_size);" end

	c_descent (a_font: POINTER; a_size: INTEGER): REAL_64
		external "C inline use %"simple_shaping_posix.h%"" alias "return st_font_descent($a_font, (int)$a_size);" end

	c_cairo_face (a_font: POINTER): POINTER
		external "C inline use %"simple_shaping_posix.h%"" alias "return st_font_cairo_face($a_font);" end

invariant
	identity_positive: pixel_size > 0 and not family.is_empty
	weight_range: weight >= 1 and weight <= 1000
	line_metrics: is_ready implies (ascent > 0.0 and descent >= 0.0)
	face_needs_realization: has_cairo_face implies is_ready

end
