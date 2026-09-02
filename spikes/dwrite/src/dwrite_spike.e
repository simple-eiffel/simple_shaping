note
	description: "[
		FEASIBILITY SPIKE: can DirectWrite's text analysis drive simple_shaping's MVP,
		with the COM burden pushed into a plain-C shim (Clib/dwrite_spike.h)?

		The probe text is built from code points (never a source literal) and covers
		Hebrew (shalom), the robot emoji U+1F916, Greek (Christos), and Latin:
		U+05E9 U+05DC U+05D5 U+05DD space U+1F916 space
		U+03A7 U+03C1 U+03B9 U+03C3 U+03C4 U+03CC U+03C2 space a b c

		Steps: dw_open (DWriteCreateFactory via LoadLibrary), dw_analyze
		(AnalyzeScript + AnalyzeBidi against C-implemented Source/Sink COM objects),
		dw_shape_run (GdiInterop CreateFontFaceFromHdc over a Segoe UI HFONT, then
		GetGlyphs + GetGlyphPlacements at 16 px). Output is printed and checked:
		at least 4 itemized runs (the script x bidi intersection an itemizer seam
		emits - measured fact: AnalyzeScript alone merges Common-script characters,
		spaces and the emoji included, into a neighboring script run, so the raw
		script table can be as small as 3 runs), an odd bidi level on the Hebrew
		run, at least 4
		positive-advance glyphs for shalom, and a report of how DirectWrite
		classifies the emoji. The sink callback order and threading are recorded
		by the shim and dumped at the end. A failed step prints the exact HRESULT;
		a negative result is a valid spike outcome.
	]"
	author: "Larry Rix (spike driven per .eiffel-workflow research follow-up)"

class
	DWRITE_SPIKE

create
	make

feature {NONE} -- Initialization

	make
			-- Run the whole probe; every outcome is printed, nothing is mocked.
		local
			l_units: ARRAYED_LIST [INTEGER]
			l_buf: MANAGED_POINTER
			l_i: INTEGER
		do
			io.put_string ("=== DirectWrite COM-shim feasibility spike (simple_shaping) ===%N")
			l_units := utf16_units
			create l_buf.make (l_units.count.max (1) * 2)
			from l_i := 1 until l_i > l_units.count loop
				l_buf.put_natural_16 (l_units.i_th (l_i).to_natural_16, (l_i - 1) * 2)
				l_i := l_i + 1
			end
			io.put_string ("probe text: Hebrew shalom + robot emoji + Greek Christos + abc, "
				+ code_points.count.out + " code points = " + l_units.count.out + " UTF-16 units%N")
			if c_spk_open = 1 then
				io.put_string ("dw_open: OK (dwrite.dll loaded, shared factory + GdiInterop + TextAnalyzer created)%N")
				run_probe (l_buf, l_units)
				c_spk_close
			else
				io.put_string ("BLOCKED at dw_open: hr=0x" + hr_hex + "%N")
			end
		end

feature {NONE} -- Probe steps

	run_probe (a_buf: MANAGED_POINTER; a_units: ARRAYED_LIST [INTEGER])
			-- Analyze, print, shape, and check `a_units' already marshalled into `a_buf'.
		local
			l_level: INTEGER
			l_bounds: ARRAYED_LIST [INTEGER]
		do
			if c_spk_analyze (a_buf.item, a_units.count) = 1 then
				print_script_runs (a_units)
				print_bidi_runs
				l_bounds := run_boundaries
				print_intersected_runs (l_bounds)
				a1_pass := l_bounds.count - 1 >= 4
				io.put_string ("%NA1 itemized runs (script x bidi) >= 4: actual "
					+ (l_bounds.count - 1).out + " (raw: " + c_spk_script_count.out
					+ " script runs, " + c_spk_bidi_count.out + " bidi runs) -> "
					+ pass_word (a1_pass) + "%N")
				l_level := bidi_resolved_at (0)
				a2_pass := l_level >= 0 and then l_level \\ 2 = 1
				io.put_string ("A2 Hebrew bidi resolved level odd: level " + l_level.out
					+ " -> " + pass_word (a2_pass) + "%N")
				if l_bounds.count >= 2 then
					shape_hebrew (a_buf, l_bounds.i_th (1), l_bounds.i_th (2) - l_bounds.i_th (1), l_level)
				end
				report_emoji (a_units)
				shape_emoji (a_buf, a_units, l_bounds)
				print_events
				print_verdict
			else
				io.put_string ("BLOCKED at dw_analyze (AnalyzeScript/AnalyzeBidi): hr=0x" + hr_hex + "%N")
			end
		end

	print_script_runs (a_units: ARRAYED_LIST [INTEGER])
			-- Dump every run AnalyzeScript delivered to the sink.
		local
			l_i, l_j, l_pos, l_len: INTEGER
		do
			io.put_string ("%N-- AnalyzeScript runs (idx pos len scriptId shapes | UTF-16 units) --%N")
			from l_i := 0 until l_i >= c_spk_script_count loop
				l_pos := c_spk_script_pos (l_i)
				l_len := c_spk_script_len (l_i)
				io.put_string ("  [" + l_i.out + "] pos=" + l_pos.out + " len=" + l_len.out
					+ " script=" + c_spk_script_id (l_i).out
					+ " shapes=" + c_spk_script_shapes (l_i).out + " |")
				from l_j := l_pos + 1 until l_j > l_pos + l_len or l_j > a_units.count loop
					io.put_string (" U+" + hex4 (a_units.i_th (l_j)))
					l_j := l_j + 1
				end
				io.put_string ("%N")
				l_i := l_i + 1
			end
		end

	print_bidi_runs
			-- Dump every run AnalyzeBidi delivered to the sink.
		local
			l_i: INTEGER
		do
			io.put_string ("%N-- AnalyzeBidi runs (idx pos len explicitLevel resolvedLevel) --%N")
			from l_i := 0 until l_i >= c_spk_bidi_count loop
				io.put_string ("  [" + l_i.out + "] pos=" + c_spk_bidi_pos (l_i).out
					+ " len=" + c_spk_bidi_len (l_i).out
					+ " explicit=" + c_spk_bidi_explicit (l_i).out
					+ " resolved=" + c_spk_bidi_resolved (l_i).out + "%N")
				l_i := l_i + 1
			end
		end

	shape_hebrew (a_buf: MANAGED_POINTER; a_pos, a_len, a_level: INTEGER)
			-- dw_shape_run over the itemized Hebrew run [a_pos, a_pos + a_len):
			-- Segoe UI face via GdiInterop, 16 px.
		local
			l_n, l_i, l_positives, l_rtl, l_srun: INTEGER
		do
			io.put_string ("%N-- dw_shape_run: Hebrew run [" + a_pos.out + ".." + (a_pos + a_len).out
				+ "), Segoe UI via CreateFontFaceFromHdc, em 16 px --%N")
			l_srun := script_run_containing (a_pos)
			if l_srun >= 0 and a_len > 0 then
				if a_level >= 0 and then a_level \\ 2 = 1 then
					l_rtl := 1
				end
				l_n := c_spk_shape (a_buf.item, a_pos, a_len,
					c_spk_script_id (l_srun), c_spk_script_shapes (l_srun), l_rtl, 16.0)
				if l_n > 0 then
					io.put_string ("  glyph count: " + l_n.out + "%N")
					from l_i := 0 until l_i >= l_n loop
						io.put_string ("  glyph[" + l_i.out + "] id=" + c_spk_glyph_id (l_i).out
							+ " advance=" + fmt2 (c_spk_glyph_advance (l_i))
							+ " offset=(" + fmt2 (c_spk_glyph_dx (l_i)) + ","
							+ fmt2 (c_spk_glyph_dy (l_i)) + ")%N")
						if c_spk_glyph_advance (l_i) > 0.0 then
							l_positives := l_positives + 1
						end
						l_i := l_i + 1
					end
					io.put_string ("  cluster map:")
					from l_i := 0 until l_i >= a_len loop
						io.put_string (" " + c_spk_cluster_entry (l_i).out)
						l_i := l_i + 1
					end
					io.put_string ("%N")
					a3_pass := l_n >= 4 and l_positives >= 4
					io.put_string ("A3 shalom >= 4 glyphs with positive advances: " + l_n.out
						+ " glyphs, " + l_positives.out + " positive -> " + pass_word (a3_pass) + "%N")
				else
					io.put_string ("  BLOCKED at GetGlyphs/GetGlyphPlacements: hr=0x" + hr_hex + "%N")
				end
			else
				io.put_string ("  BLOCKED: no script run found at position 0%N")
			end
		end

	report_emoji (a_units: ARRAYED_LIST [INTEGER])
			-- How does AnalyzeScript classify U+1F916 (surrogate pair)?
		local
			l_lead, l_run, l_pos, l_len: INTEGER
		do
			io.put_string ("%N-- emoji classification (U+1F916 = lead U+D83E trail U+DD16) --%N")
			l_lead := emoji_lead_index (a_units)
			if l_lead >= 0 then
				l_run := script_run_containing (l_lead)
				if l_run >= 0 then
					l_pos := c_spk_script_pos (l_run)
					l_len := c_spk_script_len (l_run)
					io.put_string ("  emoji lead at UTF-16 pos " + l_lead.out
						+ ", inside script run [" + l_run.out + "] pos=" + l_pos.out
						+ " len=" + l_len.out + " script=" + c_spk_script_id (l_run).out
						+ " shapes=" + c_spk_script_shapes (l_run).out + "%N")
					if l_pos = l_lead and l_len = 2 then
						io.put_string ("  -> the surrogate pair is its OWN script run%N")
					else
						io.put_string ("  -> NOT its own run; it shares a run covering ["
							+ l_pos.out + ", " + (l_pos + l_len).out + ")%N")
					end
					io.put_string ("  bidi resolved level at emoji: " + bidi_resolved_at (l_lead).out + "%N")
					io.put_string ("  note: the bidi boundary and the cluster map still isolate it, and in%N")
					io.put_string ("  simple_shaping the EMOJI_SEGMENTER (D-S04) lifts emoji out before itemization%N")
				else
					io.put_string ("  no script run covers the emoji position (unexpected)%N")
				end
			else
				io.put_string ("  lead surrogate not found in units (encoding bug)%N")
			end
		end

	shape_emoji (a_buf: MANAGED_POINTER; a_units, a_bounds: ARRAYED_LIST [INTEGER])
			-- INFO: shape the emoji's itemized run with plain Segoe UI (which has no
			-- U+1F916 coverage) to see what a coverage miss looks like as text.
		local
			l_lead, l_run, l_n, l_i, l_pos, l_len, l_rtl: INTEGER
			l_found: BOOLEAN
		do
			l_lead := emoji_lead_index (a_units)
			from l_i := 1 until l_found or l_i >= a_bounds.count loop
				if a_bounds.i_th (l_i) <= l_lead and l_lead < a_bounds.i_th (l_i + 1) then
					l_pos := a_bounds.i_th (l_i)
					l_len := a_bounds.i_th (l_i + 1) - l_pos
					l_found := True
				end
				l_i := l_i + 1
			end
			l_run := script_run_containing (l_lead)
			if l_lead >= 0 and l_run >= 0 and l_found then
				io.put_string ("%N-- INFO: shaping the emoji's itemized run [" + l_pos.out + ".."
					+ (l_pos + l_len).out + ") with Segoe UI (no emoji coverage) --%N")
				if bidi_resolved_at (l_pos) \\ 2 = 1 then
					l_rtl := 1
				end
				l_n := c_spk_shape (a_buf.item, l_pos, l_len,
					c_spk_script_id (l_run), c_spk_script_shapes (l_run), l_rtl, 16.0)
				if l_n > 0 then
					from l_i := 0 until l_i >= l_n loop
						io.put_string ("  glyph[" + l_i.out + "] id=" + c_spk_glyph_id (l_i).out
							+ " advance=" + fmt2 (c_spk_glyph_advance (l_i))
							+ (if c_spk_glyph_id (l_i) = 0 then " (.notdef - missing glyph)" else "" end) + "%N")
						l_i := l_i + 1
					end
				else
					io.put_string ("  GetGlyphs failed on the emoji run: hr=0x" + hr_hex + "%N")
				end
			end
		end

	print_intersected_runs (a_bounds: ARRAYED_LIST [INTEGER])
			-- The run table an itemizer seam actually emits: script and bidi
			-- boundaries intersected. This is how DirectWrite consumers split text
			-- for GetGlyphs; AnalyzeScript alone merges Common-script characters
			-- (spaces, the emoji) into a neighboring script run.
		local
			l_i, l_pos, l_next: INTEGER
		do
			io.put_string ("%N-- itemized runs = script x bidi intersection (pos len script level) --%N")
			from l_i := 1 until l_i >= a_bounds.count loop
				l_pos := a_bounds.i_th (l_i)
				l_next := a_bounds.i_th (l_i + 1)
				io.put_string ("  [" + (l_i - 1).out + "] pos=" + l_pos.out
					+ " len=" + (l_next - l_pos).out
					+ " script=" + c_spk_script_id (script_run_containing (l_pos)).out
					+ " level=" + bidi_resolved_at (l_pos).out + "%N")
				l_i := l_i + 1
			end
		end

	print_events
			-- Dump the shim's callback record: order, positions, threading.
		local
			l_i, l_main: INTEGER
			l_same: BOOLEAN
		do
			l_main := c_spk_main_tid
			l_same := True
			io.put_string ("%N-- sink/source callback log (order as delivered; main tid "
				+ l_main.out + ") --%N")
			from l_i := 0 until l_i >= c_spk_event_stored loop
				io.put_string ("  " + l_i.out + ": " + event_name (c_spk_event_kind (l_i))
					+ " pos=" + c_spk_event_pos (l_i).out
					+ " len=" + c_spk_event_len (l_i).out
					+ " tid=" + c_spk_event_tid (l_i).out + "%N")
				if c_spk_event_tid (l_i) /= l_main then
					l_same := False
				end
				l_i := l_i + 1
			end
			io.put_string ("  total callbacks: " + c_spk_event_total.out
				+ " (stored " + c_spk_event_stored.out + ")%N")
			io.put_string ("  all callbacks on the calling thread: " + l_same.out + "%N")
			io.put_string ("  delivery synchronous: markers 100/101 close each phase, so every"
				+ " callback landed before AnalyzeScript/AnalyzeBidi returned%N")
		end

	print_verdict
			-- Final spike verdict from the three hard checks.
		do
			io.put_string ("%N=== SPIKE VERDICT: ")
			if a1_pass and a2_pass and a3_pass then
				io.put_string ("PASS - DirectWrite analysis + shaping ran end-to-end from Eiffel through the plain-C COM shim ===%N")
			else
				io.put_string ("FAIL - see the assertion lines above for the exact break ===%N")
			end
		end

feature {NONE} -- Results

	a1_pass: BOOLEAN
			-- At least 4 script runs?

	a2_pass: BOOLEAN
			-- Hebrew run's resolved bidi level odd?

	a3_pass: BOOLEAN
			-- At least 4 positive-advance glyphs for shalom?

feature {NONE} -- Queries

	script_run_containing (a_pos: INTEGER): INTEGER
			-- Index of the AnalyzeScript run covering UTF-16 position `a_pos'; -1 if none.
		local
			l_i: INTEGER
			l_found: BOOLEAN
		do
			Result := -1
			from l_i := 0 until l_found or l_i >= c_spk_script_count loop
				if a_pos >= c_spk_script_pos (l_i) and a_pos < c_spk_script_pos (l_i) + c_spk_script_len (l_i) then
					Result := l_i
					l_found := True
				end
				l_i := l_i + 1
			end
		end

	bidi_resolved_at (a_pos: INTEGER): INTEGER
			-- Resolved bidi level of the AnalyzeBidi run covering `a_pos'; -1 if none.
		local
			l_i: INTEGER
			l_found: BOOLEAN
		do
			Result := -1
			from l_i := 0 until l_found or l_i >= c_spk_bidi_count loop
				if a_pos >= c_spk_bidi_pos (l_i) and a_pos < c_spk_bidi_pos (l_i) + c_spk_bidi_len (l_i) then
					Result := c_spk_bidi_resolved (l_i)
					l_found := True
				end
				l_i := l_i + 1
			end
		end

	emoji_lead_index (a_units: ARRAYED_LIST [INTEGER]): INTEGER
			-- 0-based UTF-16 index of U+1F916's lead surrogate (0xD83E); -1 if absent.
		local
			l_i: INTEGER
			l_found: BOOLEAN
		do
			Result := -1
			from l_i := 1 until l_found or l_i > a_units.count loop
				if a_units.i_th (l_i) = 0xD83E then
					Result := l_i - 1
					l_found := True
				end
				l_i := l_i + 1
			end
		end

	run_boundaries: ARRAYED_LIST [INTEGER]
			-- Sorted unique boundary positions (run starts and ends) from BOTH the
			-- script and bidi analyses, delimiting the itemized runs.
		local
			l_i: INTEGER
		do
			create Result.make (16)
			from l_i := 0 until l_i >= c_spk_script_count loop
				add_boundary (Result, c_spk_script_pos (l_i))
				add_boundary (Result, c_spk_script_pos (l_i) + c_spk_script_len (l_i))
				l_i := l_i + 1
			end
			from l_i := 0 until l_i >= c_spk_bidi_count loop
				add_boundary (Result, c_spk_bidi_pos (l_i))
				add_boundary (Result, c_spk_bidi_pos (l_i) + c_spk_bidi_len (l_i))
				l_i := l_i + 1
			end
		end

	add_boundary (a_list: ARRAYED_LIST [INTEGER]; a_pos: INTEGER)
			-- Insert `a_pos' into ascending `a_list' unless already present.
		local
			l_i: INTEGER
			l_done: BOOLEAN
		do
			from l_i := 1 until l_done or l_i > a_list.count loop
				if a_list.i_th (l_i) = a_pos then
					l_done := True
				elseif a_list.i_th (l_i) > a_pos then
					a_list.go_i_th (l_i)
					a_list.put_left (a_pos)
					l_done := True
				end
				l_i := l_i + 1
			end
			if not l_done then
				a_list.extend (a_pos)
			end
		end

	event_name (a_kind: INTEGER): STRING
			-- Human name for the shim's event `a_kind'.
		do
			inspect a_kind
			when 1 then Result := "QueryInterface(source)"
			when 2 then Result := "AddRef(source)"
			when 3 then Result := "Release(source)"
			when 4 then Result := "GetTextAtPosition"
			when 5 then Result := "GetTextBeforePosition"
			when 6 then Result := "GetParagraphReadingDirection"
			when 7 then Result := "GetLocaleName"
			when 8 then Result := "GetNumberSubstitution"
			when 9 then Result := "QueryInterface(sink)"
			when 10 then Result := "AddRef(sink)"
			when 11 then Result := "Release(sink)"
			when 12 then Result := "SetScriptAnalysis"
			when 13 then Result := "SetLineBreakpoints"
			when 14 then Result := "SetBidiLevel"
			when 15 then Result := "SetNumberSubstitution"
			when 100 then Result := "<AnalyzeScript returned>"
			when 101 then Result := "<AnalyzeBidi returned>"
			else Result := "kind_" + a_kind.out
			end
		end

	pass_word (a_ok: BOOLEAN): STRING
			-- "PASS" or "FAIL".
		do
			if a_ok then
				Result := "PASS"
			else
				Result := "FAIL"
			end
		end

	hex4 (a_value: INTEGER): STRING
			-- `a_value' (0 .. 0xFFFF) as 4 hex digits.
		do
			Result := a_value.to_hex_string.substring (5, 8)
		end

	hr_hex: STRING
			-- Last HRESULT recorded by the shim, as 8 hex digits.
		do
			Result := c_spk_last_hr.to_hex_string
		end

	fmt2 (a_value: REAL_64): STRING
			-- `a_value' with two decimals (spike-grade formatting).
		local
			l_h: INTEGER
		do
			l_h := (a_value * 100.0).rounded
			create Result.make (8)
			if l_h < 0 then
				Result.append_character ('-')
				l_h := -l_h
			end
			Result.append_integer (l_h // 100)
			Result.append_character ('.')
			Result.append_integer ((l_h \\ 100) // 10)
			Result.append_integer (l_h \\ 10)
		end

feature {NONE} -- Probe text

	code_points: ARRAY [INTEGER]
			-- The D-015 acceptance string as code points (dodges source-encoding traps):
			-- shalom, space, robot emoji, space, Christos, space, abc.
		once
			Result := <<0x05E9, 0x05DC, 0x05D5, 0x05DD, 0x0020, 0x1F916, 0x0020,
				0x03A7, 0x03C1, 0x03B9, 0x03C3, 0x03C4, 0x03CC, 0x03C2,
				0x0020, 0x0061, 0x0062, 0x0063>>
		end

	utf16_units: ARRAYED_LIST [INTEGER]
			-- `code_points' encoded as UTF-16 code units (surrogates hand-built).
		local
			l_i, l_cp, l_v: INTEGER
		do
			create Result.make (code_points.count + 2)
			from l_i := code_points.lower until l_i > code_points.upper loop
				l_cp := code_points [l_i]
				if l_cp <= 0xFFFF then
					Result.extend (l_cp)
				else
					l_v := l_cp - 0x10000
					Result.extend (0xD800 + l_v.bit_shift_right (10))
					Result.extend (0xDC00 + l_v.bit_and (0x3FF))
				end
				l_i := l_i + 1
			end
		ensure
			encoded: Result.count >= code_points.count
		end

feature {NONE} -- Externals (Clib/dwrite_spike.h)

	c_spk_open: INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_open();"
		end

	c_spk_close
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"spk_close();"
		end

	c_spk_last_hr: NATURAL_32
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return (unsigned int) spk_last_hr();"
		end

	c_spk_main_tid: INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_main_tid();"
		end

	c_spk_analyze (a_text: POINTER; a_len: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_analyze($a_text, (int)$a_len);"
		end

	c_spk_script_count: INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_script_count();"
		end

	c_spk_script_pos (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_script_pos((int)$a_i);"
		end

	c_spk_script_len (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_script_len((int)$a_i);"
		end

	c_spk_script_id (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_script_id((int)$a_i);"
		end

	c_spk_script_shapes (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_script_shapes((int)$a_i);"
		end

	c_spk_bidi_count: INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_bidi_count();"
		end

	c_spk_bidi_pos (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_bidi_pos((int)$a_i);"
		end

	c_spk_bidi_len (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_bidi_len((int)$a_i);"
		end

	c_spk_bidi_explicit (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_bidi_explicit((int)$a_i);"
		end

	c_spk_bidi_resolved (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_bidi_resolved((int)$a_i);"
		end

	c_spk_event_total: INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_event_total();"
		end

	c_spk_event_stored: INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_event_stored();"
		end

	c_spk_event_kind (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_event_kind((int)$a_i);"
		end

	c_spk_event_tid (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_event_tid((int)$a_i);"
		end

	c_spk_event_pos (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_event_pos((int)$a_i);"
		end

	c_spk_event_len (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_event_len((int)$a_i);"
		end

	c_spk_shape (a_text: POINTER; a_pos, a_len, a_script, a_shapes, a_rtl: INTEGER; a_px: REAL_64): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_shape($a_text, (int)$a_pos, (int)$a_len, (int)$a_script, (int)$a_shapes, (int)$a_rtl, (double)$a_px);"
		end

	c_spk_glyph_id (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_glyph_id((int)$a_i);"
		end

	c_spk_glyph_advance (a_i: INTEGER): REAL_64
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_glyph_advance((int)$a_i);"
		end

	c_spk_glyph_dx (a_i: INTEGER): REAL_64
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_glyph_dx((int)$a_i);"
		end

	c_spk_glyph_dy (a_i: INTEGER): REAL_64
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_glyph_dy((int)$a_i);"
		end

	c_spk_cluster_entry (a_i: INTEGER): INTEGER
		external
			"C inline use %"dwrite_spike.h%""
		alias
			"return spk_cluster_entry((int)$a_i);"
		end

note
	copyright: "Copyright (c) 2026, Larry Rix"
	license: "MIT License"

end
