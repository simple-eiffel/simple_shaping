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

		PHASE 4 TASK 2 - REALIZATION IS REAL. `realize' runs the D-S03 chain
		(LOGFONTW with lfHeight = -pixel_size through
		GDI32_API.create_font -> create_memory_dc -> select_font ->
		text_ascent/text_descent -> DWRITE_API.create_font_face_from_hdc) and
		`dispose' unwinds it in the reverse order (face Release, restore the
		DC's original font, DeleteObject (HFONT), DeleteDC). Both are
		{FONT_REGISTRY}-only: the registry owns native lifetime (DR-012), so
		no client can realize or release a font behind its back.

		WHAT `is_ready' MEANS, EXACTLY (the note above lists the happy path;
		this is the boundary rule). `is_ready' is the GDI half: an HFONT
		selected into a private memory DC with POSITIVE tmAscent read back.
		The IDWriteFontFace is BEST EFFORT and reported separately by
		`has_backend_face'. The split is deliberate and follows NFR-011: a
		machine that cannot load dwrite.dll still measures and paints, and an
		item whose font has no face degrades through R3's tofu-but-valid
		synthesis rather than through an assertion. A font that fails the GDI
		half keeps NOTHING - every handle is released inside `realize' and
		`is_ready' stays False, which is what `unrealized_has_no_metrics'
		demands.

		R1: `realized_family' is what GetTextFaceW reported after the
		selection - GDI silently substitutes for an unknown family, so the
		requested name proves nothing and `is_family_realized' is the
		comparator the facade's existence probe consumes.
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
			-- Ascent at `pixel_size' - TEXTMETRIC tmAscent of the HFONT
			-- selected into `device_context'. 0.0 until realized, and 0.0
			-- again after `dispose' (`unrealized_has_no_metrics').

	descent: REAL_64
			-- Descent at `pixel_size' - TEXTMETRIC tmDescent. 0.0 until
			-- realized, and 0.0 again after `dispose'.

	line_height: REAL_64
			-- Ascent + descent.
		require
			realized: is_ready
		do
			Result := ascent + descent
		ensure
			metric: Result = ascent + descent
		end

	realized_family: IMMUTABLE_STRING_32
			-- [ADDED Phase 4 Task 2] The face GDI ACTUALLY selected, as
			-- GetTextFaceW reported it (empty until realized). R1's
			-- comparator input: GDI maps an unknown family onto a
			-- substitute without saying so, so `family' alone cannot tell
			-- presence from substitution.
		attribute
			create Result.make_empty
		end

feature -- Native handles (implementation-visible; POINTER is opaque)

	font_handle: POINTER
			-- [ADDED Phase 4 Task 2] The HFONT (default_pointer until
			-- realized, and again after `dispose').

	device_context: POINTER
			-- [ADDED Phase 4 Task 2] The private memory HDC this font's
			-- HFONT is selected into (D-S03). The IDWriteFontFace was taken
			-- from it and the cairo face will be taken from it.

	backend_face: POINTER
			-- [ADDED Phase 4 Task 2] The IDWriteFontFace obtained via
			-- GdiInterop.CreateFontFaceFromHdc - what seam 3 shapes with.
			-- default_pointer when the backend was unreachable: BEST EFFORT,
			-- not part of `is_ready' (see the class note).

feature -- Status

	is_ready: BOOLEAN
			-- The GDI half of realization done: LOGFONTW built, HFONT created
			-- and selected into the private memory HDC, and a POSITIVE ascent
			-- read back from TEXTMETRIC. The backend face is reported
			-- separately by `has_backend_face' - see the class note for why
			-- the two are not one flag.

	has_cairo_face: BOOLEAN
			-- Cairo face created (lazy; requires realization; Phase 4 with
			-- the D-S07 dependency)?

	is_realization_attempted: BOOLEAN
			-- [ADDED Phase 4 Task 2] Has the registry already run `realize'
			-- on this identity? TRUE even when the attempt FAILED - that is
			-- the point: it stops the registry from re-probing a font the
			-- machine has already refused on every single call, and it is
			-- the fact `FONT_REGISTRY.font' can promise unconditionally
			-- (`is_ready' cannot be promised: it depends on the OS).

	has_backend_face: BOOLEAN
			-- [ADDED Phase 4 Task 2] Is the IDWriteFontFace live? Seam 3
			-- shapes when this is True and synthesizes R3 tofu when it is
			-- not - never asserts.
		do
			Result := backend_face /= default_pointer
		ensure
			definition: Result = (backend_face /= default_pointer)
		end

	is_family_realized: BOOLEAN
			-- [ADDED Phase 4 Task 2] R1's EXISTENCE VERDICT: did GDI give
			-- back the family that was asked for, rather than a silent
			-- substitute? Case-insensitive, because GDI's own matching is.
		do
			Result := is_ready and then realized_family.is_case_insensitive_equal (family)
		ensure
			needs_realization: Result implies is_ready
		end

feature {FONT_REGISTRY} -- Realization (native lifetime is the registry's, DR-012)

	realize (a_gdi: GDI32_API; a_dwrite: DWRITE_API)
			-- Run the D-S03 chain at `pixel_size' (same-N): LOGFONTW with
			-- lfHeight = -pixel_size, CreateFontIndirectW, a private memory
			-- DC, SelectObject, TEXTMETRIC ascent/descent, GetTextFaceW for
			-- R1, then GdiInterop.CreateFontFaceFromHdc for the shaper.
			--
			-- TOTAL, NEVER-RAISING (NFR-011): a failure at any step releases
			-- everything this call created and leaves the font exactly as it
			-- was born - not ready, no metrics, no handles - so
			-- `unrealized_has_no_metrics' holds and a caller can degrade on
			-- `is_ready' instead of catching an exception.
		require
			not_attempted: not is_realization_attempted
		local
			l_font, l_dc, l_previous: POINTER
			l_ascent, l_descent: INTEGER
			l_name: STRING_32
			l_gdi_half_done: BOOLEAN
		do
			is_realization_attempted := True
			create l_name.make_empty
			l_font := a_gdi.create_font (family, weight, is_italic, pixel_size)
			if l_font /= default_pointer then
				l_dc := a_gdi.create_memory_dc
				if l_dc /= default_pointer then
					l_previous := a_gdi.select_font (l_dc, l_font)
					l_ascent := a_gdi.text_ascent (l_dc)
					l_descent := a_gdi.text_descent (l_dc)
					l_name := a_gdi.realized_face_name (l_dc)
						-- `line_metrics' demands a POSITIVE ascent, so a
						-- font whose metrics did not come back is not a
						-- realized font at all.
					l_gdi_half_done := l_ascent > 0
				end
			end
			if l_gdi_half_done then
				font_handle := l_font
				device_context := l_dc
				previous_font := l_previous
				create realized_family.make_from_string_general (l_name)
				ascent := l_ascent.to_double
				descent := l_descent.to_double
				is_ready := True
					-- Best effort, and only now that the DC is stable.
				if a_dwrite.is_open or else a_dwrite.open then
					backend_face := a_dwrite.create_font_face_from_hdc (l_dc)
				end
			else
				release_gdi_chain (a_gdi, l_dc, l_previous, l_font)
			end
		ensure
			attempted: is_realization_attempted
			identity_kept: family = old family and weight = old weight
				and is_italic = old is_italic and pixel_size = old pixel_size
			handles_when_ready: is_ready implies
				(font_handle /= default_pointer and device_context /= default_pointer)
			nothing_kept_when_not_ready: not is_ready implies
				(font_handle = default_pointer and device_context = default_pointer
				and backend_face = default_pointer)
			face_needs_the_gdi_half: has_backend_face implies is_ready
		end

	dispose (a_gdi: GDI32_API; a_dwrite: DWRITE_API)
			-- Release every native handle IN ORDER - IDWriteFontFace
			-- Release, restore the DC's original font, DeleteObject (HFONT),
			-- DeleteDC - and return to the unrealized state, so the identity
			-- can be realized again (a registry may be reused after
			-- `dispose_all'). Idempotent: safe on a font that never
			-- realized and safe twice.
		local
			l_previous: POINTER
		do
			if backend_face /= default_pointer then
				a_dwrite.release_font_face (backend_face)
				backend_face := default_pointer
			end
			l_previous := previous_font
			previous_font := default_pointer
			release_gdi_chain (a_gdi, device_context, l_previous, font_handle)
			font_handle := default_pointer
			device_context := default_pointer
			ascent := 0.0
			descent := 0.0
			is_ready := False
			is_realization_attempted := False
			create realized_family.make_empty
		ensure
			unrealized: not is_ready
			no_cairo_face: not has_cairo_face
			handles_released: font_handle = default_pointer
				and device_context = default_pointer and backend_face = default_pointer
			metrics_cleared: ascent = 0.0 and descent = 0.0
			realizable_again: not is_realization_attempted
			identity_kept: family = old family and weight = old weight
				and is_italic = old is_italic and pixel_size = old pixel_size
		end

feature {NONE} -- Implementation

	previous_font: POINTER
			-- [ADDED Phase 4 Task 2] The stock font SelectObject displaced;
			-- Win32 requires it back in the DC before the DC dies, or the
			-- HFONT stays selected and DeleteObject silently fails.

	release_gdi_chain (a_gdi: GDI32_API; a_dc, a_previous, a_font: POINTER)
			-- [ADDED Phase 4 Task 2] Unwind `a_dc'/`a_font' in the ONE
			-- lawful order: restore `a_previous' into `a_dc', delete the
			-- HFONT, delete the DC. Every argument may be default_pointer
			-- (the partial-failure paths inside `realize' hand exactly the
			-- handles that were actually created).
		local
			l_restored: POINTER
		do
			l_restored := a_previous
			if a_dc /= default_pointer and l_restored /= default_pointer then
				l_restored := a_gdi.select_font (a_dc, l_restored)
			end
			if a_font /= default_pointer and then a_gdi.delete_handle (a_font) then
			end
			if a_dc /= default_pointer and then a_gdi.delete_dc (a_dc) then
			end
		end

invariant
	identity_positive: pixel_size > 0 and not family.is_empty
	weight_range: weight >= 1 and weight <= 1000
	line_metrics: is_ready implies (ascent > 0.0 and descent >= 0.0)
	face_needs_realization: has_cairo_face implies is_ready
	unrealized_has_no_metrics: not is_ready implies (ascent = 0.0 and descent = 0.0)

end
