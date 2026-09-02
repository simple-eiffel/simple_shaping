note
	description: "[
		One (family, weight, style, pixel size) realization - the D-S03
		same-N contract holder. NOT a value: an identity object that will own
		native resources once realized (Phase 4): LOGFONTW, HFONT selected
		into a private memory HDC, the backend's per-font handle, and a
		lazily created cairo font face.

		SAME-N RULE (D-S03/DR-009): shaping and placement run at `pixel_size'
		through the HFONT; the paint side MUST set_font_size (pixel_size) on
		the same face - cairo ignores LOGFONT lfHeight and sizes via the font
		matrix. Shaper positions are authoritative.

		BACKEND HANDLE: under DirectWrite (G1 final) the per-font handle is
		the IDWriteFontFace obtained via GdiInterop.CreateFontFaceFromHdc
		over this font's HDC - the exact call the spike proved (Segoe UI at
		16 px: 4 positive-advance glyphs for shalom). Under the named
		Uniscribe alternate it would be a SCRIPT_CACHE. Either way the handle
		is {NONE}-held POINTER state, Phase 4.

		CAIRO FACE: the typed `cairo_face' query arrives with the gated
		D-S07 simple_cairo dependency (Phase 4) - no cairo types compile in
		Phase 1; `has_cairo_face' stays False until then.

		CONFINEMENT (DR-012/OQ-1): owned by exactly ONE FONT_REGISTRY on one
		processor; never shared, never passed separate. The back-pointer
		`registry' fixes ownership at birth.

		R9 (Q12): MVP shapes everything regular-weight upright - the facade
		freezes (Weight_regular, not italic); this class KEEPS weight/italic
		so the future styled-runs extension changes the facade only.
	]"
	author: "Larry Rix"

class
	SHAPING_FONT

create {FONT_REGISTRY}
	make

feature {NONE} -- Initialization

	make (a_family: READABLE_STRING_32; a_weight: INTEGER; a_italic: BOOLEAN;
			a_pixel_size: INTEGER; a_registry: FONT_REGISTRY)
			-- Unrealized identity (native realization is Phase 4).
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
			-- LOGFONT FW_NORMAL; the R9 facade freeze.

feature -- Access

	family: IMMUTABLE_STRING_32
			-- Family name as configured.

	weight: INTEGER
			-- LOGFONT weight (1 .. 1000; 400 = regular, 700 = bold).

	is_italic: BOOLEAN
			-- Italic style?

	pixel_size: INTEGER
			-- THE size (same-N): shaping, placement, and painting all happen
			-- at this many pixels.

	registry: FONT_REGISTRY
			-- The one registry (one processor) owning this font (DR-012).

	ascent: REAL_64
			-- Ascent at `pixel_size' (0.0 until realized; Phase 4: TEXTMETRIC).

	descent: REAL_64
			-- Descent at `pixel_size' (0.0 until realized; Phase 4: TEXTMETRIC).

	line_height: REAL_64
			-- Ascent + descent.
		require
			realized: is_ready
		do
			Result := ascent + descent
		ensure
			metric: Result = ascent + descent
		end

feature -- Status

	is_ready: BOOLEAN
			-- Native handles realized (Phase 4 flips this: LOGFONTW built,
			-- HFONT created and selected into the memory HDC, metrics read,
			-- backend face obtained)?

	has_cairo_face: BOOLEAN
			-- Cairo face created (lazy; requires realization; Phase 4 with
			-- the D-S07 dependency)?

invariant
	identity_positive: pixel_size > 0 and not family.is_empty
	weight_range: weight >= 1 and weight <= 1000
	line_metrics: is_ready implies (ascent > 0.0 and descent >= 0.0)
	face_needs_realization: has_cairo_face implies is_ready
	unrealized_has_no_metrics: not is_ready implies (ascent = 0.0 and descent = 0.0)

end
