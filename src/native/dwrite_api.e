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

		PHASE 4 TASK 1 - THE BODIES ARE REAL. Every one binds
		Clib/simple_shaping_dwrite.h through `C inline use'; the Phase-1
		`Hresult_not_implemented' returns are gone and `last_hresult' now
		carries the HRESULT DirectWrite actually returned. Phase 2's
		ISSUE-11 postconditions have teeth in C: `ssd_analyze' converts a
		"success" that left a run table empty into a FAILURE, `ssd_shape_run'
		does the same for an empty glyph table, and every failure path resets
		the affected table before returning - so `runs_on_success' and
		`glyphs_on_success' cannot be violated from the native side and no
		caller ever reads a partly-filled table.

		GROWN BEYOND THE SPIKE (Task 3): the paragraph reading direction the
		analysis source reports is SETTABLE
		(`set_paragraph_reading_direction' / `paragraph_reading_direction').
		DirectWrite offers no first-strong facility - DWRITE_READING_DIRECTION
		has only LTR and RTL, and AnalyzeBidi takes the paragraph level as an
		INPUT - so UAX #9 P2/P3 is the CALLER's job, and this is the channel
		the caller's answer travels through.

		GROWN BEYOND THE SPIKE (Task 1): AnalyzeLineBreakpoints (analyzer
		slot 6) is typed and its SetLineBreakpoints sink is REAL - the
		spike's was a stub - so `analyze_line_breakpoints' plus the
		breakpoint accessors can feed SCRIPT_ITEMIZER.soft_breaks (Task 4).
		`copy_script_run_analysis' hands a run's DWRITE_SCRIPT_ANALYSIS bytes
		to the itemizer so SCRIPT_ITEM carries them VERBATIM back into
		`shape_run'. Every shim buffer is heap-allocated and grows on demand;
		the spike's fixed caps would have truncated a real chat line.
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
			Result := c_open = 1
			is_open := Result
			if Result then
				last_hresult := 0
			else
				last_hresult := non_zero_hresult (c_last_hresult)
			end
		ensure
			open_on_success: Result = is_open
			failure_reported: not Result implies last_hresult /= 0
		end

	close
			-- Release analyzer, interop, factory; free the DLL.
		do
			c_close
			is_open := False
		ensure
			closed: not is_open
		end

feature -- Paragraph reading direction (source callback) -- ADDED Phase 4 Task 3

	Reading_direction_ltr: INTEGER = 0
			-- [ADDED] DWRITE_READING_DIRECTION_LEFT_TO_RIGHT.

	Reading_direction_rtl: INTEGER = 1
			-- [ADDED] DWRITE_READING_DIRECTION_RIGHT_TO_LEFT.

	paragraph_reading_direction: INTEGER
			-- [ADDED] What the shim's IDWriteTextAnalysisSource answers from
			-- `GetParagraphReadingDirection' - the PARAGRAPH LEVEL AnalyzeBidi
			-- works from. LTR until somebody sets it; `close' puts it back.
		do
			Result := c_reading_direction
		ensure
			binary: Result = Reading_direction_ltr or Result = Reading_direction_rtl
		end

	set_paragraph_reading_direction (a_direction: INTEGER)
			-- [ADDED] Make the source answer `a_direction' from
			-- `GetParagraphReadingDirection', from the next `analyze' on.
			--
			-- WHY THIS EXISTS: DWRITE_READING_DIRECTION has no "auto" member
			-- and IDWriteTextAnalyzer runs no UAX #9 P2/P3 - the paragraph
			-- level is an INPUT to AnalyzeBidi, never an output. A caller that
			-- wants first-strong detection must resolve it itself and then set
			-- it here (DIRECTWRITE_BIDI_RESOLVER does exactly that, and its
			-- class note records how). The spike's source answered
			-- LEFT_TO_RIGHT unconditionally, so a forced-RTL paragraph could
			-- not be expressed at all.
		require
			binary: a_direction = Reading_direction_ltr or a_direction = Reading_direction_rtl
		do
			c_set_reading_direction (a_direction)
		ensure
			direction_installed: paragraph_reading_direction = a_direction
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
			Result := c_analyze (a_utf16_text, a_unit_count) = 1
			if Result then
				last_hresult := 0
			else
				last_hresult := non_zero_hresult (c_last_hresult)
			end
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
			Result := c_script_run_count.max (0)
		ensure
			non_negative: Result >= 0
		end

	script_run_position (a_index: INTEGER): INTEGER
			-- UTF-16 start of script run `a_index' (0-based).
		require
			in_range: a_index >= 0 and a_index < script_run_count
		do
			Result := c_script_run_position (a_index)
		end

	script_run_length (a_index: INTEGER): INTEGER
			-- UTF-16 length of script run `a_index'.
		require
			in_range: a_index >= 0 and a_index < script_run_count
		do
			Result := c_script_run_length (a_index)
		end

	script_run_script (a_index: INTEGER): INTEGER
			-- ENGINE-INTERNAL opaque script id of run `a_index'.
		require
			in_range: a_index >= 0 and a_index < script_run_count
		do
			Result := c_script_run_id (a_index)
		end

	script_analysis_size: INTEGER
			-- [ADDED Phase 4 Task 1] Bytes in one DWRITE_SCRIPT_ANALYSIS -
			-- the buffer size `copy_script_run_analysis' fills and
			-- `shape_run' reads back.
		do
			Result := c_script_analysis_size
		ensure
			positive: Result > 0
		end

	copy_script_run_analysis (a_index: INTEGER; a_buffer: POINTER)
			-- [ADDED Phase 4 Task 1] Copy the DWRITE_SCRIPT_ANALYSIS bytes
			-- of script run `a_index' VERBATIM into `a_buffer' (which must
			-- hold at least `script_analysis_size' bytes). SCRIPT_ITEM
			-- carries exactly these bytes back into `shape_run'.
		require
			in_range: a_index >= 0 and a_index < script_run_count
			buffer_present: a_buffer /= default_pointer
		do
			c_script_analysis (a_index, a_buffer)
		end

	bidi_run_count: INTEGER
			-- AnalyzeBidi runs delivered to the sink.
		do
			Result := c_bidi_run_count.max (0)
		ensure
			non_negative: Result >= 0
		end

	bidi_run_position (a_index: INTEGER): INTEGER
			-- UTF-16 start of bidi run `a_index'.
		require
			in_range: a_index >= 0 and a_index < bidi_run_count
		do
			Result := c_bidi_run_position (a_index)
		end

	bidi_run_length (a_index: INTEGER): INTEGER
			-- UTF-16 length of bidi run `a_index'.
		require
			in_range: a_index >= 0 and a_index < bidi_run_count
		do
			Result := c_bidi_run_length (a_index)
		end

	bidi_run_level (a_index: INTEGER): INTEGER
			-- Resolved level of bidi run `a_index'.
		require
			in_range: a_index >= 0 and a_index < bidi_run_count
		do
			Result := c_bidi_run_level (a_index).max (0)
		ensure
			non_negative: Result >= 0
		end

feature -- Line breaking (AnalyzeLineBreakpoints slot 6) -- ADDED Phase 4 Task 1

	analyze_line_breakpoints (a_utf16_text: POINTER; a_unit_count: INTEGER): BOOLEAN
			-- [ADDED] Run AnalyzeLineBreakpoints over `a_unit_count' UTF-16
			-- units; one DWRITE_LINE_BREAKPOINT lands per unit in the
			-- breakpoint table below. The script and bidi run tables are
			-- LEFT ALONE, so an itemizer may `analyze' once and then ask for
			-- the breaks of the SAME string (Task 4's `soft_breaks').
		require
			ready: is_open
			text_present: a_utf16_text /= default_pointer
			count_positive: a_unit_count > 0
		do
			Result := c_analyze_breaks (a_utf16_text, a_unit_count) = 1
			if Result then
				last_hresult := 0
			else
				last_hresult := non_zero_hresult (c_last_hresult)
			end
		ensure
			breaks_on_success: Result implies breakpoint_count = a_unit_count
				-- One breakpoint per unit or nothing at all: the shim turns a
				-- short delivery into a failure rather than a ragged table.
			failure_reported: not Result implies last_hresult /= 0
		end

	breakpoint_count: INTEGER
			-- [ADDED] UTF-16 units covered by the last successful
			-- `analyze_line_breakpoints'.
		do
			Result := c_break_count.max (0)
		ensure
			non_negative: Result >= 0
		end

	break_condition_before (a_index: INTEGER): INTEGER
			-- [ADDED] DWRITE_BREAK_CONDITION at the LEADING edge of unit
			-- `a_index': 0 neutral, 1 can break, 2 may not break, 3 must break.
		require
			in_range: a_index >= 0 and a_index < breakpoint_count
		do
			Result := c_break_before (a_index)
		ensure
			in_enumeration: Result >= 0 and Result <= 3
		end

	break_condition_after (a_index: INTEGER): INTEGER
			-- [ADDED] DWRITE_BREAK_CONDITION at the TRAILING edge of unit
			-- `a_index' (same enumeration).
		require
			in_range: a_index >= 0 and a_index < breakpoint_count
		do
			Result := c_break_after (a_index)
		ensure
			in_enumeration: Result >= 0 and Result <= 3
		end

	is_break_whitespace (a_index: INTEGER): BOOLEAN
			-- [ADDED] Is UTF-16 unit `a_index' whitespace? (R2's hanging
			-- space needs to know.)
		require
			in_range: a_index >= 0 and a_index < breakpoint_count
		do
			Result := c_break_is_whitespace (a_index) = 1
		end

	is_break_soft_hyphen (a_index: INTEGER): BOOLEAN
			-- [ADDED] Is UTF-16 unit `a_index' a soft hyphen?
		require
			in_range: a_index >= 0 and a_index < breakpoint_count
		do
			Result := c_break_is_soft_hyphen (a_index) = 1
		end

feature -- Fonts (GdiInterop slot 6)

	create_font_face_from_hdc (a_hdc: POINTER): POINTER
			-- IDWriteFontFace for the font currently selected into `a_hdc'
			-- (spike-proven bridge from the GDI world).
		require
			ready: is_open
			dc_present: a_hdc /= default_pointer
		do
			Result := c_create_face_from_hdc (a_hdc)
			if Result = default_pointer then
				last_hresult := non_zero_hresult (c_last_hresult)
			else
				last_hresult := 0
			end
		end

	release_font_face (a_face: POINTER)
			-- Release one IDWriteFontFace.
		do
			if a_face /= default_pointer then
				c_release_face (a_face)
			end
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
			Result := c_shape_run (a_utf16_text, a_unit_count, a_font_face,
				a_em_size_pixels.to_double, a_is_rtl, a_analysis) = 1
			if Result then
				last_hresult := 0
			else
				last_hresult := non_zero_hresult (c_last_hresult)
			end
		ensure
			glyphs_on_success: Result implies glyph_count >= 1
				-- The run is non-empty by precondition, so a successful shape
				-- produces at least one glyph - .notdef counts (ISSUE 11).
			failure_reported: not Result implies last_hresult /= 0
		end

	glyph_count: INTEGER
			-- Glyphs from the last successful `shape_run'.
		do
			Result := c_glyph_count.max (0)
		ensure
			non_negative: Result >= 0
		end

	glyph_id (a_index: INTEGER): NATURAL_32
			-- Physical glyph index (0 = .notdef).
		require
			in_range: a_index >= 0 and a_index < glyph_count
		do
			Result := c_glyph_id (a_index)
		end

	glyph_advance (a_index: INTEGER): REAL_64
			-- Advance of glyph `a_index' in pixels at the shaped em size.
		require
			in_range: a_index >= 0 and a_index < glyph_count
		do
			Result := c_glyph_advance (a_index)
		end

	glyph_x_offset (a_index: INTEGER): REAL_64
			-- advanceOffset of glyph `a_index'.
		require
			in_range: a_index >= 0 and a_index < glyph_count
		do
			Result := c_glyph_dx (a_index)
		end

	glyph_y_offset (a_index: INTEGER): REAL_64
			-- ascenderOffset of glyph `a_index'.
		require
			in_range: a_index >= 0 and a_index < glyph_count
		do
			Result := c_glyph_dy (a_index)
		end

	Hresult_not_implemented: NATURAL_32 = 0x80004001
			-- E_NOTIMPL - what the Phase-1 inert bodies reported, so
			-- `failure_reported' was honest before the shim existed. Phase 4
			-- retired every use of it; kept as the documented predecessor.

	Hresult_unspecified: NATURAL_32 = 0x80004005
			-- [ADDED Phase 4 Task 1] E_FAIL - the last-resort code
			-- `non_zero_hresult' substitutes if the shim ever reported a
			-- failure with a zero HRESULT, so `failure_reported' can never
			-- be violated by a silent native regression.

	cluster_of_unit (a_index: INTEGER): INTEGER
			-- Cluster-map entry for UTF-16 unit `a_index' of the shaped run.
		require
			non_negative: a_index >= 0
		do
			Result := c_cluster_entry (a_index)
		end

feature {NONE} -- Implementation

	non_zero_hresult (a_hresult: NATURAL_32): NATURAL_32
			-- [ADDED Phase 4 Task 1] `a_hresult' when it reports something,
			-- `Hresult_unspecified' otherwise - the guard that keeps every
			-- `failure_reported' postcondition dischargeable even if the
			-- shim were ever to fail without setting a code.
		do
			if a_hresult = 0 then
				Result := Hresult_unspecified
			else
				Result := a_hresult
			end
		ensure
			never_silent: Result /= 0
		end

feature {NONE} -- Externals (Clib/simple_shaping_dwrite.h)

	c_open: INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_open();"
		end

	c_close
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"ssd_close();"
		end

	c_last_hresult: NATURAL_32
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return (EIF_NATURAL_32) ssd_last_hr();"
		end

	c_set_reading_direction (a_direction: INTEGER)
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"ssd_set_reading_direction((int) $a_direction);"
		end

	c_reading_direction: INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_reading_direction();"
		end

	c_analyze (a_text: POINTER; a_len: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_analyze($a_text, (int) $a_len);"
		end

	c_script_run_count: INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_script_count();"
		end

	c_script_run_position (a_index: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_script_pos((int) $a_index);"
		end

	c_script_run_length (a_index: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_script_len((int) $a_index);"
		end

	c_script_run_id (a_index: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_script_id((int) $a_index);"
		end

	c_script_analysis (a_index: INTEGER; a_buffer: POINTER)
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"ssd_script_analysis((int) $a_index, $a_buffer);"
		end

	c_script_analysis_size: INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_script_analysis_size();"
		end

	c_bidi_run_count: INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_bidi_count();"
		end

	c_bidi_run_position (a_index: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_bidi_pos((int) $a_index);"
		end

	c_bidi_run_length (a_index: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_bidi_len((int) $a_index);"
		end

	c_bidi_run_level (a_index: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_bidi_level((int) $a_index);"
		end

	c_analyze_breaks (a_text: POINTER; a_len: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_analyze_breaks($a_text, (int) $a_len);"
		end

	c_break_count: INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_break_count();"
		end

	c_break_before (a_index: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_break_before((int) $a_index);"
		end

	c_break_after (a_index: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_break_after((int) $a_index);"
		end

	c_break_is_whitespace (a_index: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_break_is_ws((int) $a_index);"
		end

	c_break_is_soft_hyphen (a_index: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_break_is_hyph((int) $a_index);"
		end

	c_create_face_from_hdc (a_hdc: POINTER): POINTER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_create_face_from_hdc($a_hdc);"
		end

	c_release_face (a_face: POINTER)
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"ssd_release_face($a_face);"
		end

	c_shape_run (a_text: POINTER; a_len: INTEGER; a_face: POINTER;
			a_em: REAL_64; a_rtl: BOOLEAN; a_analysis: POINTER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_shape_run($a_text, (int) $a_len, $a_face, (double) $a_em, $a_rtl ? 1 : 0, $a_analysis);"
		end

	c_glyph_count: INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_glyph_count();"
		end

	c_glyph_id (a_index: INTEGER): NATURAL_32
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return (EIF_NATURAL_32) ssd_glyph_id((int) $a_index);"
		end

	c_glyph_advance (a_index: INTEGER): REAL_64
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return (EIF_REAL_64) ssd_glyph_advance((int) $a_index);"
		end

	c_glyph_dx (a_index: INTEGER): REAL_64
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return (EIF_REAL_64) ssd_glyph_dx((int) $a_index);"
		end

	c_glyph_dy (a_index: INTEGER): REAL_64
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return (EIF_REAL_64) ssd_glyph_dy((int) $a_index);"
		end

	c_cluster_entry (a_index: INTEGER): INTEGER
		external
			"C inline use %"simple_shaping_dwrite.h%""
		alias
			"return ssd_cluster_entry((int) $a_index);"
		end

end
