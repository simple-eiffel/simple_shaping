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
		construction. SCRIPT_ITEMIZER carries that ordering as a CALLER DUTY
		note, NOT as a precondition (Phase 2, ISSUE 1): rung 3 deliberately
		sends unresolvable pictographs into the glyph path, so a precondition
		forbidding them would make the documented degradation an assertion
		violation.

		WHAT `segment' CAN HONESTLY PROMISE about PLAIN spans (ISSUE 1's
		mirror ensure): no character of a PLAIN span is a starter that THIS
		segmenter's own tables + catalog would have resolved ON ITS OWN -
		`no_resolvable_single_left_plain', computed by
		`has_resolvable_single' from `tables' and `catalog'. The GENERAL case
		(a multi-codepoint RGI sequence whose FULL-SEQUENCE asset exists) is
		NOT statable in a postcondition without re-running the longest-match
		ladder inside the assertion - which would be the implementation, not
		a specification of it, and would make assertion evaluation quadratic
		over the paragraph. The single-codepoint case is the part that is
		both cheap and complete, so that is the part that is contracted; the
		rest stays a Phase-5 test obligation.

		DEGRADATION OBSERVABILITY (ISSUE 6): rung 3 is the only party that
		knows a sequence degraded, so `segment' takes an `a_notes'
		ACCUMULATOR and appends one Note_emoji_degraded per degraded
		sequence. The list only grows, and every appended note carries that
		code - both contracted below - so the facade can count
		statistics.notes_emitted without re-deriving the degradation.

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

	segment (a_text: READABLE_STRING_32; a_bidi: BIDI_RESULT;
			a_notes: ARRAYED_LIST [SHAPING_NOTE]): ARRAYED_LIST [TEXT_SEGMENT]
			-- Split `a_text' into PLAIN spans and RESOLVED emoji spans;
			-- emoji spans inherit their characters' resolved levels from
			-- `a_bidi'. Every sequence that reaches rung 3 of the FR-007
			-- ladder appends one Note_emoji_degraded to `a_notes'
			-- (accumulator; never cleared, never reordered).
		require
			bidi_matches: a_bidi.count = a_text.count
			notes_attached: a_notes /= Void
		do
			-- Phase 4: RGI longest-match scan (VS16, ZWJ, modifiers, flags)
			-- + the FR-007 ladder against `catalog'; emoji segments carry
			-- `a_bidi.level' of their first character; each rung-3
			-- degradation extends `a_notes' with a Note_emoji_degraded over
			-- the degraded range.
			-- Phase 1 degenerate (real for ungenerated tables): no emoji
			-- detectable -> one PLAIN segment covering everything, nothing
			-- degraded, no notes.
			create Result.make (1)
			if not a_text.is_empty then
				Result.extend (create {TEXT_SEGMENT}.make_plain (1, a_text.count))
			end
		ensure
			never_void: Result /= Void
			partition: segments_partition (Result, a_text.count)
			emoji_resolved: across Result as s all s.is_emoji implies s.has_resolved_asset end
			empty_text: a_text.is_empty implies Result.is_empty
			emoji_levels_inherited: across Result as s all
				s.is_emoji implies s.embedding_level = a_bidi.level (s.start_index) end
			no_resolvable_single_left_plain: across Result as s all
				s.is_plain implies not has_resolvable_single (a_text, s.start_index, s.count) end
			notes_only_grow: a_notes.count >= old a_notes.count
			appended_notes_are_degradations: across (old a_notes.count + 1) |..| a_notes.count as k all
				a_notes [k].code = Note_emoji_degraded end
		end

	has_resolvable_single (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): BOOLEAN
			-- Does a_text [`a_start' .. `a_start' + `a_count' - 1] contain a
			-- single codepoint that is an emoji STARTER whose OWN one-codepoint
			-- asset THIS catalog resolves? Such a character must never be left
			-- in a PLAIN segment: the ladder's rung 1 would have lifted it.
			-- Deliberately single-codepoint only - see the class note on why
			-- the general RGI-sequence case is not statable here.
		require
			range_valid: a_start >= 1 and a_count >= 0 and a_start + a_count - 1 <= a_text.count
		local
			i: INTEGER
			l_code: NATURAL_32
		do
			from i := a_start until i > a_start + a_count - 1 or Result loop
				l_code := a_text.code (i)
				Result := tables.is_emoji_starter (l_code)
					and then catalog.has_asset (<<l_code>>)
				i := i + 1
			end
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
