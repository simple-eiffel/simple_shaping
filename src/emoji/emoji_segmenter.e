note
	description: "[
		UTS #51 scan: text + resolved levels -> TEXT_SEGMENTs. Owns the
		FR-007 DEGRADATION LADDER in ONE place (A-C06):
		  1. full-sequence asset (catalog probe on the whole RGI match);
		  2. else per-codepoint assets (sequence split into single heads);
		  3. else the span stays PLAIN into the glyph path (monochrome or
		     tofu) + Note_emoji_degraded.
		Consequence: every EMOJI segment this class emits is RESOLVED
		(DR-006) - IMAGE_RUN's `resolved' invariant is dischargeable because
		unresolvable sequences never become emoji segments at all.

		ORDER (A-C03/DR-005, spike-confirmed): this runs AFTER bidi
		resolution (emoji are bidi-neutral; their boxes inherit resolved
		levels for RTL placement) and BEFORE itemization. The dwrite spike
		measured what happens otherwise: AnalyzeScript folds U+1F916 into a
		neighboring text run and GetGlyphs shapes its surrogates to .notdef
		(glyph id 0) - an emoji that reaches a shaper is tofu by
		construction. SCRIPT_ITEMIZER.itemize's precondition therefore
		accepts only emoji-free spans; this class is what makes that
		precondition satisfiable.

		Phase 4 implements the full RGI longest-match scan (Q4: VS16, ZWJ
		families, skin tones, flag pairs - table-driven, tables generated).
		The Phase-1 body is the honest degenerate: with ungenerated tables
		no emoji can be detected, so the whole text is one PLAIN segment -
		which already satisfies every postcondition below.
	]"
	author: "Larry Rix"

class
	EMOJI_SEGMENTER

inherit
	SHAPING_CONSTANTS

create
	make

feature {NONE} -- Initialization

	make (a_tables: EMOJI_DATA_TABLES; a_catalog: EMOJI_ASSET_CATALOG)
			-- Segmenter over `a_tables', resolving against `a_catalog'.
		do
			tables := a_tables
			catalog := a_catalog
		ensure
			tables_kept: tables = a_tables
			catalog_kept: catalog = a_catalog
		end

feature -- Access

	tables: EMOJI_DATA_TABLES
			-- UTS #51 data (D-S08).

	catalog: EMOJI_ASSET_CATALOG
			-- Asset resolution (the ladder's oracle).

feature -- Operations

	segment (a_text: READABLE_STRING_32; a_bidi: BIDI_RESULT): ARRAYED_LIST [TEXT_SEGMENT]
			-- Split `a_text' into PLAIN spans and RESOLVED emoji spans;
			-- emoji spans inherit their characters' resolved levels from
			-- `a_bidi'.
		require
			bidi_matches: a_bidi.count = a_text.count
		do
			-- Phase 4: RGI longest-match scan (VS16, ZWJ, modifiers, flags)
			-- + the FR-007 ladder against `catalog'; emoji segments carry
			-- `a_bidi.level' of their first character.
			-- Phase 1 degenerate (real for ungenerated tables): no emoji
			-- detectable -> one PLAIN segment covering everything.
			create Result.make (1)
			if not a_text.is_empty then
				Result.extend (create {TEXT_SEGMENT}.make_plain (1, a_text.count))
			end
		ensure
			never_void: Result /= Void
			partition: segments_partition (Result, a_text.count)
			emoji_resolved: across Result as s all s.is_emoji implies s.has_resolved_asset end
			empty_text: a_text.is_empty implies Result.is_empty
		end

	segments_partition (a_segments: ARRAYED_LIST [TEXT_SEGMENT]; a_character_count: INTEGER): BOOLEAN
			-- Do `a_segments' cover characters 1 .. `a_character_count'
			-- contiguously, in order, exactly once (empty text: no segments)?
		local
			i, l_next: INTEGER
		do
			Result := True
			l_next := 1
			from i := 1 until i > a_segments.count or not Result loop
				Result := a_segments [i].start_index = l_next
				l_next := l_next + a_segments [i].count
				i := i + 1
			end
			Result := Result and l_next = a_character_count + 1
		end

end
