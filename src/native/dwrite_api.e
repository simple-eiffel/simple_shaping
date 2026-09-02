note
	description: "[
		The ONE home for the DirectWrite externals (Phase 4). Implementation
		layer: consumers never see this class; the DIRECTWRITE_* effectings
		are its only intended clients.

		SINGLE-TRANSLATION-UNIT RULE (spike-proven): the production C shim
		(Clib/simple_shaping_dwrite.h, grown from spikes/dwrite/Clib/
		dwrite_spike.h - the spike itself stays untouched as evidence) keeps
		its state and COM objects as statics, so ALL `C inline use' externals
		binding it MUST live in THIS one class to land in one generated
		translation unit.

		PROVEN BINDING PATTERN (spikes/dwrite, verdict PASS):
		- dwrite.h is C++-only; the shim hand-declares C vtable structs with
		  slot order transcribed verbatim from the SDK header (unused slots
		  void*); COM's binary contract makes the call legal from C.
		- dwrite.dll loads via LoadLibraryW + GetProcAddress
		  ("DWriteCreateFactory") - no import library; gdi32 links via
		  #pragma comment.
		- Shared factory -> GetGdiInterop (factory slot 17) and
		  CreateTextAnalyzer (slot 21).
		- IDWriteTextAnalyzer: AnalyzeScript (slot 3), AnalyzeBidi (slot 4),
		  GetGlyphs (slot 7), GetGlyphPlacements (slot 8).
		- IDWriteGdiInterop.CreateFontFaceFromHdc (slot 6) turns a
		  SHAPING_FONT's HDC-selected HFONT into the IDWriteFontFace that
		  GetGlyphs consumes (measured: Segoe UI em 16 px, real glyphs,
		  positive advances).
		- Source/Sink are static C singletons; all callbacks arrived
		  synchronously on the calling thread (spike event log) -
		  confinement-safe (DR-012).
		- This surface speaks UTF-16 units and engine positions; the
		  DIRECTWRITE_* effectings own all mapping to code-point space.

		Phase-1 bodies are inert stubs (is_open stays False, so the
		index-guarded queries are uncallable) - zero native code compiles
		this cycle by design (no Clib yet, ECF audit clean). They DO set
		`last_hresult' on their False returns, because Phase 2 (ISSUE 11)
		gave the three workhorse calls real success-and-failure
		postconditions: a shim that returns success without populating the
		run/glyph tables, or failure without reporting an HRESULT, is now a
		CONTRACT VIOLATION at the trust boundary rather than a surprise
		three layers up. The never-raises law needs teeth exactly here.
	]"
	author: "Larry Rix"
	never_raises: "Every native call is HRESULT-checked in the shim; failures surface as False/last_hresult, never exceptions (NFR-011)."

class
	DWRITE_API

create
	make

feature {NONE} -- Initialization

	make
			-- Inert surface (Phase 4 opens the DLL lazily).
		do
		ensure
			closed: not is_open
		end

feature -- Status

	is_open: BOOLEAN
			-- Factory + GdiInterop + TextAnalyzer live?

	last_hresult: NATURAL_32
			-- The failing HRESULT of the most recent unsuccessful call
			-- (0 when the last call succeeded).

feature -- Lifecycle

	open: BOOLEAN
			-- Load dwrite.dll, create the shared factory, GdiInterop and
			-- TextAnalyzer. False with `last_hresult' set on failure.
		do
			-- Phase 4: external shim dw_open (LoadLibraryW +
			-- DWriteCreateFactory + GetGdiInterop + CreateTextAnalyzer).
			last_hresult := Hresult_not_implemented
			Result := False
		ensure
			open_on_success: Result = is_open
			failure_reported: not Result implies last_hresult /= 0
		end

	close
			-- Release analyzer, interop, factory; free the DLL.
		do
			-- Phase 4: external shim dw_close.
		ensure
			closed: not is_open
		end

feature -- Analysis (AnalyzeScript slot 3 + AnalyzeBidi slot 4)

	analyze (a_utf16_text: POINTER; a_unit_count: INTEGER): BOOLEAN
			-- Run script and bidi analysis over `a_unit_count' UTF-16 units;
			-- results land in the run tables below.
		require
			ready: is_open
			text_present: a_utf16_text /= default_pointer
			count_positive: a_unit_count > 0
		do
			-- Phase 4: external shim dw_analyze.
			last_hresult := Hresult_not_implemented
			Result := False
		ensure
			runs_on_success: Result implies (script_run_count >= 1 and bidi_run_count >= 1)
				-- Every UTF-16 unit belongs to SOME script run and SOME bidi
				-- run, so a successful analysis of a non-empty text cannot
				-- deliver an empty run table (ISSUE 11).
			failure_reported: not Result implies last_hresult /= 0
		end

	script_run_count: INTEGER
			-- AnalyzeScript runs delivered to the sink.
		do
			-- Phase 4: external shim accessor.
		ensure
			non_negative: Result >= 0
		end

	script_run_position (a_index: INTEGER): INTEGER
			-- UTF-16 start of script run `a_index' (0-based).
		require
			in_range: a_index >= 0 and a_index < script_run_count
		do
			-- Phase 4: external shim accessor.
		end

	script_run_length (a_index: INTEGER): INTEGER
			-- UTF-16 length of script run `a_index'.
		require
			in_range: a_index >= 0 and a_index < script_run_count
		do
			-- Phase 4: external shim accessor.
		end

	script_run_script (a_index: INTEGER): INTEGER
			-- ENGINE-INTERNAL opaque script id of run `a_index'.
		require
			in_range: a_index >= 0 and a_index < script_run_count
		do
			-- Phase 4: external shim accessor.
		end

	bidi_run_count: INTEGER
			-- AnalyzeBidi runs delivered to the sink.
		do
			-- Phase 4: external shim accessor.
		ensure
			non_negative: Result >= 0
		end

	bidi_run_position (a_index: INTEGER): INTEGER
			-- UTF-16 start of bidi run `a_index'.
		require
			in_range: a_index >= 0 and a_index < bidi_run_count
		do
			-- Phase 4: external shim accessor.
		end

	bidi_run_length (a_index: INTEGER): INTEGER
			-- UTF-16 length of bidi run `a_index'.
		require
			in_range: a_index >= 0 and a_index < bidi_run_count
		do
			-- Phase 4: external shim accessor.
		end

	bidi_run_level (a_index: INTEGER): INTEGER
			-- Resolved level of bidi run `a_index'.
		require
			in_range: a_index >= 0 and a_index < bidi_run_count
		do
			-- Phase 4: external shim accessor.
		ensure
			non_negative: Result >= 0
		end

feature -- Fonts (GdiInterop slot 6)

	create_font_face_from_hdc (a_hdc: POINTER): POINTER
			-- IDWriteFontFace for the font currently selected into `a_hdc'
			-- (spike-proven bridge from the GDI world).
		require
			ready: is_open
			dc_present: a_hdc /= default_pointer
		do
			-- Phase 4: external shim over GdiInterop.CreateFontFaceFromHdc.
		end

	release_font_face (a_face: POINTER)
			-- Release one IDWriteFontFace.
		do
			-- Phase 4: external shim Release.
		end

feature -- Shaping (GetGlyphs slot 7 + GetGlyphPlacements slot 8)

	shape_run (a_utf16_text: POINTER; a_unit_count: INTEGER; a_font_face: POINTER;
			a_em_size_pixels: REAL_32; a_is_rtl: BOOLEAN; a_analysis: POINTER): BOOLEAN
			-- GetGlyphs + GetGlyphPlacements for one itemized run at
			-- `a_em_size_pixels' (same-N: the SHAPING_FONT's pixel size);
			-- `a_analysis' is the run's DWRITE_SCRIPT_ANALYSIS bytes.
			-- Results land in the glyph tables below.
		require
			ready: is_open
			text_present: a_utf16_text /= default_pointer
			count_positive: a_unit_count > 0
			face_present: a_font_face /= default_pointer
			size_positive: a_em_size_pixels > 0.0
		do
			-- Phase 4: external shim dw_shape_run (grow-and-retry per
			-- A-C02; 1.5n+16 first allocation).
			last_hresult := Hresult_not_implemented
			Result := False
		ensure
			glyphs_on_success: Result implies glyph_count >= 1
				-- The run is non-empty by precondition, so a successful shape
				-- produces at least one glyph - .notdef counts (ISSUE 11).
			failure_reported: not Result implies last_hresult /= 0
		end

	glyph_count: INTEGER
			-- Glyphs from the last successful `shape_run'.
		do
			-- Phase 4: external shim accessor.
		ensure
			non_negative: Result >= 0
		end

	glyph_id (a_index: INTEGER): NATURAL_32
			-- Physical glyph index (0 = .notdef).
		require
			in_range: a_index >= 0 and a_index < glyph_count
		do
			-- Phase 4: external shim accessor.
		end

	glyph_advance (a_index: INTEGER): REAL_64
			-- Advance of glyph `a_index' in pixels at the shaped em size.
		require
			in_range: a_index >= 0 and a_index < glyph_count
		do
			-- Phase 4: external shim accessor.
		end

	glyph_x_offset (a_index: INTEGER): REAL_64
			-- advanceOffset of glyph `a_index'.
		require
			in_range: a_index >= 0 and a_index < glyph_count
		do
			-- Phase 4: external shim accessor.
		end

	glyph_y_offset (a_index: INTEGER): REAL_64
			-- ascenderOffset of glyph `a_index'.
		require
			in_range: a_index >= 0 and a_index < glyph_count
		do
			-- Phase 4: external shim accessor.
		end

	Hresult_not_implemented: NATURAL_32 = 0x80004001
			-- E_NOTIMPL - what the Phase-1 inert bodies report, so
			-- `failure_reported' is honest before the shim exists.

	cluster_of_unit (a_index: INTEGER): INTEGER
			-- Cluster-map entry for UTF-16 unit `a_index' of the shaped run.
		require
			non_negative: a_index >= 0
		do
			-- Phase 4: external shim accessor.
		end

end
