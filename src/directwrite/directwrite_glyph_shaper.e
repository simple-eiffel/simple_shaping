note
	description: "[
		MVP effecting of seam 3 (G1 FINAL). Phase 4 effects `shape' with
		IDWriteTextAnalyzer.GetGlyphs (vtable slot 7) + GetGlyphPlacements
		(slot 8) over the IDWriteFontFace from GdiInterop.CreateFontFaceFromHdc
		(slot 6) on the SHAPING_FONT's memory HDC - the exact chain the spike
		PROVED: Segoe UI at em 16 px shaped shalom to 4 glyphs (ids
		2945/2932/2925/2933) with positive advances (12.55/8.81/4.29/11.10)
		and identity cluster map; .notdef came back as glyph id 0
		(spikes/dwrite/run_output.txt, check A3 PASS). Em size = pixel_size
		(same-N, D-S03); isRightToLeft = item level parity; the item's
		DWRITE_SCRIPT_ANALYSIS bytes are passed back verbatim from
		SCRIPT_ITEM.analysis.

		Missing-glyph counting (the G2 probe verdict): count characters whose
		cluster's glyphs are all id 0. On a hard HRESULT failure: R3's
		tofu-but-valid synthesis (id 0 per character, advance pixel_size/2,
		identity clusters) - never an empty item, never a raise.

		UNISCRIBE_GLYPH_SHAPER (ScriptShape + ScriptPlace + SCRIPT_CACHE) is
		the named alternate slot - it does not exist yet.

		PHASE 4 TASK 5 - SEAM 3 IS REAL. What follows is the boundary rule
		the effecting had to settle, because the spike measured it and the
		frozen contracts constrain it.

		GLYPH ORDER. DirectWrite delivers glyphs in LOGICAL order for BOTH
		directions, and a cluster map that is NON-DECREASING for both: the
		Task-1 native round trip shaped shalom with isRightToLeft = TRUE and
		measured the cluster map 0 1 2 3, not 3 2 1 0. Handed straight
		through, that map is non-DECREASING - which violates
		`clusters_monotone_rtl' for any RTL item of 2+ characters. So for an
		RTL item this class emits the glyph, advance and offset arrays in
		VISUAL order (left to right on screen) and mirrors the cluster map
		with them. That is the only arrangement in which BOTH frozen clauses
		hold AND `clusters' still names the first glyph of the character's
		own cluster; a mirrored map over an unmirrored glyph array would
		satisfy the contract while pointing at the wrong glyph. LTR items
		pass through untouched. NULL_GLYPH_SHAPER leaves its glyphs in
		logical order with a mirrored map - a knowing divergence: the double
		is metric-predictable, not order-faithful.

		A cluster map that is NOT non-decreasing is not guessed at. It is
		treated as an unrecoverable backend answer and degrades through R3,
		because inventing an order for an answer no measurement covers is
		exactly the silent wrong answer this backend exists to avoid.

		CODE POINTS, NOT UNITS. The shim's cluster map is indexed by UTF-16
		UNIT; every seam clause is per CODE POINT. Each character's entry is
		read at its FIRST unit through DIRECTWRITE_UTF16_MAPPING - which
		collapses a surrogate pair's low half away, and is what keeps
		`cluster_per_character' true for the robot and its kin.

		BUFFER DISCIPLINE (A-C02). First allocation 1.5n + 16 glyphs with
		grow-and-retry up to 3 attempts lives in C, inside `ssd_shape_run'
		(Task 1): that is the only place that can see
		ERROR_INSUFFICIENT_BUFFER come back from GetGlyphs.
		`DWRITE_API.shape_run' answering False means those three attempts are
		already spent, so THIS class's answer to False is the R3 synthesis -
		no second retry loop, and no glyph-count bound promised.

		MISSING GLYPHS ARE NOT AN ERROR. A run with no coverage shapes
		SUCCESSFULLY to .notdef; `missing_glyph_count' counts the characters
		whose whole cluster came back id 0, and `is_complete' is then False.
		That is the G2 probe verdict seam 4 consumes - it is NOT the R3 path,
		and `last_shape_was_synthesized' is the query that tells the two
		apart.

		The Phase-1 body IS the R3 tofu synthesis (satisfies every seam
		contract; visibly boxes until Phase 4 lands real shaping). It
		survives, unchanged in behavior, as `synthesized_tofu'.
	]"
	author: "Larry Rix"
	never_raises: "Every failure - no face, a closed backend, a refused shape_run, an unreadable cluster map - degrades to R3's tofu synthesis, and a rescue catches anything left (NFR-011)."

class
	DIRECTWRITE_GLYPH_SHAPER

inherit
	GLYPH_SHAPER

	DIRECTWRITE_UTF16_MAPPING

create
	make

feature {NONE} -- Initialization

	make
			-- Wire the native surface.
		do
			create api.make
		end

feature -- Operations

	shape (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM; a_font: SHAPING_FONT): SHAPED_ITEM
			-- <Precursor>
		require else
			range_only: a_item.start_index + a_item.count - 1 <= a_text.count
				-- [ADDED Phase 4 Task 5 - a LAWFUL WEAKENING, never a change
				-- to the seam's own clause.] The inherited `font_ready' drops
				-- out of the effective precondition: a seam that promises
				-- never to raise cannot answer an unrealized font with an
				-- assertion violation. R3 is the documented answer, and it
				-- needs only `pixel_size', which the SHAPING_FONT invariant
				-- keeps positive whether the machine realized the font or
				-- refused it.
		local
			l_real: detachable SHAPED_ITEM
			l_degraded: BOOLEAN
		do
			if not l_degraded and then a_font.has_backend_face and then backend_open then
				l_real := shaped_over_backend (a_text, a_item, a_font)
			end
			if attached l_real as al_real then
				Result := al_real
				last_shape_was_synthesized := False
			else
				Result := synthesized_tofu (a_item, a_font)
				last_shape_was_synthesized := True
			end
		ensure then
			synthesis_is_reported: last_shape_was_synthesized implies
				(Result.glyphs.count = a_item.count
				and Result.missing_glyph_count = a_item.count
				and not Result.is_complete)
		rescue
			if not l_degraded then
				l_degraded := True
				l_real := Void
				retry
			end
		end

feature -- Status

	last_shape_was_synthesized: BOOLEAN
			-- [ADDED Phase 4 Task 5] Did the LAST `shape' call answer with
			-- R3's tofu synthesis rather than with real DirectWrite glyphs?
			-- THE observable the caller (Task 11) reads before emitting
			-- `Note_backend_error_recovered'.
			--
			-- WHY NOT JUST LOOK AT THE GLYPH IDS. An item of all-zero ids is
			-- ambiguous: a REAL shape of an uncovered run is also all zeros,
			-- and that is a coverage verdict (G2), not a backend error. Only
			-- this flag separates "the backend spoke and had no glyph" from
			-- "the backend never spoke". `shape' is therefore a query that
			-- writes one flag - a DECLARED CQS EXCEPTION, taken because the
			-- alternative is a signature change to a FROZEN seam.

feature {NONE} -- Implementation: real shaping (GetGlyphs + GetGlyphPlacements)

	shaped_over_backend (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
			a_font: SHAPING_FONT): detachable SHAPED_ITEM
			-- One real shaping pass for `a_item' over `a_font.backend_face'
			-- at `a_font.pixel_size' (same-N) - or Void when the backend
			-- refused, or answered a cluster map this class will not guess
			-- at, so the caller synthesizes R3 tofu instead.
		require
			range_valid: a_item.start_index + a_item.count - 1 <= a_text.count
			face_present: a_font.has_backend_face
			backend_open: api.is_open
		local
			l_first, l_start, l_stop, l_clusters: ARRAY [INTEGER]
			l_glyphs: ARRAY [NATURAL_32]
			l_advances, l_x, l_y: ARRAY [REAL_64]
			l_buffer, l_analysis: MANAGED_POINTER
			i, n, g, l_units, l_slot, l_missing: INTEGER
			l_sane: BOOLEAN
		do
			n := a_item.count
			l_units := unit_count (a_text, a_item.start_index, n)
			l_first := first_units (a_text, a_item.start_index, n)
			l_buffer := utf16_span (a_text, a_item.start_index, n)
			l_analysis := analysis_buffer (a_item)
			if api.shape_run (l_buffer.item, l_units, a_font.backend_face,
				a_font.pixel_size.to_real, a_item.is_rtl, l_analysis.item)
			then
				g := api.glyph_count
					-- ONE entry per CODE POINT, read at that code point's
					-- FIRST UTF-16 unit: the low surrogate's own entry is
					-- collapsed away here, which is what makes
					-- `cluster_per_character' true.
				create l_start.make_filled (0, 1, n)
				l_sane := g >= 1
				from i := 1 until i > n or not l_sane loop
					l_slot := api.cluster_of_unit (l_first [i])
					if l_slot < 0 or else l_slot >= g or else
						(i > 1 and then l_slot < l_start [i - 1])
					then
							-- Outside the glyph table, or not non-decreasing:
							-- an answer no measurement covers. R3, not a guess.
						l_sane := False
					else
						l_start [i] := l_slot
					end
					i := i + 1
				end
				if l_sane then
						-- A character's cluster ENDS where the next DISTINCT
						-- cluster begins; the last one ends at the last glyph.
						-- `l_stop' is non-decreasing because `l_start' is.
					create l_stop.make_filled (g - 1, 1, n)
					from i := n - 1 until i < 1 loop
						if l_start [i + 1] > l_start [i] then
							l_stop [i] := l_start [i + 1] - 1
						else
							l_stop [i] := l_stop [i + 1]
						end
						i := i - 1
					end
						-- The glyph tables. An RTL item is MIRRORED into
						-- visual order (see the class note); an LTR item is
						-- passed through.
					create l_glyphs.make_filled (0, 1, g)
					create l_advances.make_filled (0.0, 1, g)
					create l_x.make_filled (0.0, 1, g)
					create l_y.make_filled (0.0, 1, g)
					from i := 0 until i >= g loop
						if a_item.is_rtl then
							l_slot := g - i
						else
							l_slot := i + 1
						end
						l_glyphs [l_slot] := api.glyph_id (i)
							-- `advances_non_negative' is FROZEN, and this is
							-- its guard: DirectWrite's advances came back
							-- non-negative for every run measured, so the
							-- clamp changes no measurement - it only makes a
							-- native regression unable to violate the seam.
						l_advances [l_slot] := api.glyph_advance (i).max (0.0)
						l_x [l_slot] := api.glyph_x_offset (i)
						l_y [l_slot] := api.glyph_y_offset (i)
						i := i + 1
					end
						-- The cluster map, in the SAME order as the glyphs:
						-- ascending for LTR, mirrored (and so non-increasing)
						-- for RTL, both naming the FIRST glyph of the
						-- character's own cluster.
					create l_clusters.make_filled (1, 1, n)
					from i := 1 until i > n loop
						if a_item.is_rtl then
							l_clusters [i] := g - l_stop [i]
						else
							l_clusters [i] := l_start [i] + 1
						end
						if all_notdef (l_start [i], l_stop [i]) then
							l_missing := l_missing + 1
						end
						i := i + 1
					end
					create Result.make (a_font, n, l_glyphs, l_advances, l_x, l_y,
						l_clusters, l_missing)
				end
			end
		ensure
			cluster_per_character: attached Result as al_result implies
				al_result.clusters.count = a_item.count
			font_recorded: attached Result as al_result implies al_result.font = a_font
		end

	analysis_buffer (a_item: SCRIPT_ITEM): MANAGED_POINTER
			-- `a_item.analysis' VERBATIM in a native buffer at least as wide
			-- as the shim's DWRITE_SCRIPT_ANALYSIS record. Zero-filled when
			-- the itemizer degraded and carried no bytes - which is exactly
			-- what the shim reads a NULL analysis as, so the two paths agree.
		require
			backend_open: api.is_open
		local
			i: INTEGER
		do
			create Result.make (api.script_analysis_size.max (a_item.analysis.count).max (1))
			from i := a_item.analysis.lower until i > a_item.analysis.upper loop
				Result.put_natural_8 (a_item.analysis [i], i - a_item.analysis.lower)
				i := i + 1
			end
		ensure
			buffer_present: Result.item /= default_pointer
			holds_the_record: Result.count >= api.script_analysis_size
			holds_the_bytes: Result.count >= a_item.analysis.count
		end

	all_notdef (a_from, a_to: INTEGER): BOOLEAN
			-- Are ALL of the shim's glyphs `a_from' .. `a_to' (0-based, in
			-- the LOGICAL order DirectWrite delivered them) .notdef? That is
			-- the G2 probe verdict for the character whose cluster they are:
			-- a character counts as MISSING only when nothing in its cluster
			-- found a real glyph.
		require
			ordered: a_from >= 0 and a_to >= a_from
			in_range: a_to < api.glyph_count
		local
			i: INTEGER
		do
			Result := True
			from i := a_from until i > a_to or not Result loop
				Result := api.glyph_id (i) = 0
				i := i + 1
			end
		end

	backend_open: BOOLEAN
			-- Is the native surface usable? Opens it if it is not.
			-- `DWRITE_API.open' is idempotent, so asking every time is the
			-- cheap way to stay correct after another component closed the
			-- DLL. A False answer sends the caller down R3; it never raises.
		do
			Result := api.open
		end

feature {NONE} -- Implementation: the R3 synthesis

	synthesized_tofu (a_item: SCRIPT_ITEM; a_font: SHAPING_FONT): SHAPED_ITEM
			-- R3, tofu-but-valid: glyph id 0 per character, advance
			-- `pixel_size' / 2, zero offsets, and a TRIVIAL ONE-TO-ONE
			-- cluster map REVERSED for an RTL item (R3 as amended by
			-- ISSUE 12 - an identity map violates `clusters_monotone_rtl'
			-- for any RTL item of 2+ characters, so "identity" was never
			-- available). Never an empty item, never a dropped range; the
			-- `Note_backend_error_recovered' is the caller's to emit.
		require
			source_positive: a_item.count > 0
		local
			i, n: INTEGER
			l_glyphs: ARRAY [NATURAL_32]
			l_advances, l_x, l_y: ARRAY [REAL_64]
			l_clusters: ARRAY [INTEGER]
		do
			n := a_item.count
			create l_glyphs.make_filled (0, 1, n)
			create l_advances.make_filled ((a_font.pixel_size / 2).max (0.0), 1, n)
			create l_x.make_filled (0.0, 1, n)
			create l_y.make_filled (0.0, 1, n)
			create l_clusters.make_filled (0, 1, n)
			from i := 1 until i > n loop
				if a_item.is_rtl then
					l_clusters [i] := n - i + 1
				else
					l_clusters [i] := i
				end
				i := i + 1
			end
			create Result.make (a_font, n, l_glyphs, l_advances, l_x, l_y, l_clusters, n)
		ensure
			one_box_per_character: Result.glyphs.count = a_item.count
			cluster_per_character: Result.clusters.count = a_item.count
			every_character_missing: Result.missing_glyph_count = a_item.count
			never_complete: not Result.is_complete
			clusters_valid: Result.clusters_in_range
			font_recorded: Result.font = a_font
		end

feature {NONE} -- Implementation

	api: DWRITE_API
			-- The one native surface (single-translation-unit rule).

end
