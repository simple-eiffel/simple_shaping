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

		PHASE 4 (Task 8) - WHAT THE SCAN ACTUALLY DOES. One left-to-right
		pass, no backtracking. At each position the candidate is
		`tables.longest_rgi_prefix_length' - VS16 pairs, ZWJ families, skin
		tones, flag pairs and keycaps all come out of that ONE generated
		lookup, and it is deliberately not gated on `is_emoji_starter'
		because keycap bases are Emoji_Component, not Extended_Pictographic.
		The ladder then runs, in this order, in this class, and nowhere else:

		  RUNG 1 `span_resolves_whole' - the whole sequence has an asset of
		         its own: ONE emoji segment carrying the joined key
		         (a ZWJ family is one image, FR-006/AC-1).
		  RUNG 2 `span_resolves_by_component' - it does not, but every
		         COMPONENT images on its own: one emoji segment per
		         component. This is where FLAG PAIRS land against Noto
		         v2.051, which ships the 26 regional-indicator letters but
		         no waved-flag PNG - two letter tiles, which is the
		         Unicode-recommended fallback.
		  RUNG 3 - neither: the span stays PLAIN on the glyph path and
		         EXACTLY ONE Note_emoji_degraded covering it is appended to
		         `a_notes'. Characters inside that span which image on their
		         own are still lifted (`append_resolvable_singles'), because
		         `no_resolvable_single_left_plain' forbids leaving them - a
		         MIXED sequence (one component with an asset, one without)
		         is precisely the case where degrading the whole span
		         wholesale would violate that clause.

		A position that heads no RGI sequence is still tested as a lone
		starter, so a bare, unqualified pictograph whose own asset exists is
		lifted too - again `no_resolvable_single_left_plain'.

		GLUE - VS16, ZWJ and the TAG characters U+E0020..U+E007F - never
		forms a segment of its own: it rides with the base it joins. A
		joiner that reached the shaper would come back as .notdef, a VISIBLE
		tofu square in the middle of a degraded family, so rungs 2 and 3
		hand the shaper the base's image or nothing at all. The England flag
		is the worked example: U+1F3F4 plus six tag characters has no asset
		in v2.051, but U+1F3F4 does, so rung 2 emits ONE black-flag image
		over all seven characters and no tag ever reaches DirectWrite.
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
		local
			l_emoji: ARRAYED_LIST [TEXT_SEGMENT]
			i, l_match: INTEGER
		do
				-- The emoji segments are collected first and the PLAIN spans
				-- are the GAPS between them (`with_plain_spans'), which is
				-- what makes `partition' true by construction rather than by
				-- bookkeeping inside the scan.
			create l_emoji.make (4)
			from i := 1 until i > a_text.count loop
				l_match := tables.longest_rgi_prefix_length (a_text, i)
				if l_match >= 1 then
					if span_resolves_whole (a_text, i, l_match) then
							-- RUNG 1: one asset for the whole sequence.
						append_whole (l_emoji, a_text, a_bidi, i, l_match)
					elseif span_resolves_by_component (a_text, i, l_match) then
							-- RUNG 2: every component images on its own.
						append_components (l_emoji, a_text, a_bidi, i, l_match)
					else
							-- RUNG 3: the span degrades to plain text and the
							-- accumulator gets EXACTLY ONE note for it (ISSUE
							-- 6 - the only channel this rung has). Whatever
							-- inside it still images is lifted anyway.
						a_notes.extend (degradation_note (a_text, i, l_match))
						append_resolvable_singles (l_emoji, a_text, a_bidi, i, l_match)
					end
					i := i + l_match
				else
						-- Heads no RGI sequence - but a bare, unqualified
						-- pictograph with an asset of its own must not be
						-- left plain either.
					append_resolvable_singles (l_emoji, a_text, a_bidi, i, 1)
					i := i + 1
				end
			end
			Result := with_plain_spans (l_emoji, a_text.count)
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

feature {NONE} -- Implementation: the FR-007 ladder (Task 8)

	span_resolves_whole (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): BOOLEAN
			-- RUNG 1: does the whole span
			-- `a_text' [`a_start' .. `a_start' + `a_count' - 1] have ONE
			-- asset of its own? A query: it decides, it never emits.
		require
			range_valid: a_start >= 1 and a_count >= 1 and a_start + a_count - 1 <= a_text.count
		local
			l_codes: ARRAY [NATURAL_32]
		do
			l_codes := tables.codepoints_of (a_text, a_start, a_count)
			Result := catalog.has_non_vs16 (l_codes) and then catalog.has_asset (l_codes)
		end

	span_resolves_by_component (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): BOOLEAN
			-- RUNG 2: does EVERY component of the span image on its own?
			-- All or nothing - a half-imaged sequence is not a rung.
		require
			range_valid: a_start >= 1 and a_count >= 1 and a_start + a_count - 1 <= a_text.count
		local
			s, l_last: INTEGER
		do
			l_last := a_start + a_count - 1
			Result := True
			from s := a_start until s > l_last or not Result loop
				if component_resolves (a_text, s) then
					s := component_last (a_text, s, l_last) + 1
				else
					Result := False
				end
			end
		end

	component_resolves (a_text: READABLE_STRING_32; a_start: INTEGER): BOOLEAN
			-- Does the component beginning at `a_start' have a
			-- single-codepoint asset? Glue never does - and asking the
			-- catalog about a lone VS16 would break its `meaningful'
			-- precondition, which is why the guard comes first.
		require
			in_range: a_start >= 1 and a_start <= a_text.count
		local
			l_code: NATURAL_32
		do
			l_code := a_text.code (a_start)
			Result := not is_sequence_glue (l_code) and then catalog.has_asset (<<l_code>>)
		end

	component_last (a_text: READABLE_STRING_32; a_start, a_limit: INTEGER): INTEGER
			-- Last character of the component beginning at `a_start', never
			-- past `a_limit': the base plus every glue character trailing it.
		require
			range_valid: a_start >= 1 and a_start <= a_limit and a_limit <= a_text.count
		do
			from
				Result := a_start
			until
				Result >= a_limit or else not is_sequence_glue (a_text.code (Result + 1))
			loop
				Result := Result + 1
			end
		ensure
			within_span: Result >= a_start and Result <= a_limit
		end

	is_sequence_glue (a_codepoint: NATURAL_32): BOOLEAN
			-- Is `a_codepoint' invisible sequence machinery - VS16, ZWJ, or
			-- a TAG character (U+E0020 .. U+E007F, the subdivision-flag
			-- spelling)? Glue has no image of its own and must never reach
			-- the shaper alone, so it always rides with the base it joins.
		do
			Result := tables.is_vs16 (a_codepoint) or tables.is_zwj (a_codepoint)
				or (a_codepoint >= 0xE0020 and a_codepoint <= 0xE007F)
		ensure
			glue_definition: Result = (tables.is_vs16 (a_codepoint) or tables.is_zwj (a_codepoint)
				or (a_codepoint >= 0xE0020 and a_codepoint <= 0xE007F))
		end

	append_whole (a_into: ARRAYED_LIST [TEXT_SEGMENT]; a_text: READABLE_STRING_32;
			a_bidi: BIDI_RESULT; a_start, a_count: INTEGER)
			-- RUNG 1's emission: ONE emoji segment over the whole span,
			-- keyed by the whole sequence (the ZWJ family's joined name).
		require
			range_valid: a_start >= 1 and a_count >= 1 and a_start + a_count - 1 <= a_text.count
			bidi_matches: a_bidi.count = a_text.count
			resolves: span_resolves_whole (a_text, a_start, a_count)
		do
			append_emoji (a_into, a_text, a_bidi, a_start, a_count,
				tables.codepoints_of (a_text, a_start, a_count))
		ensure
			one_more: a_into.count = old a_into.count + 1
			whole_span: a_into.last.start_index = a_start and a_into.last.count = a_count
		end

	append_components (a_into: ARRAYED_LIST [TEXT_SEGMENT]; a_text: READABLE_STRING_32;
			a_bidi: BIDI_RESULT; a_start, a_count: INTEGER)
			-- RUNG 2's emission: one emoji segment per component, each
			-- keyed by its own base codepoint and covering the glue that
			-- trails it.
		require
			range_valid: a_start >= 1 and a_count >= 1 and a_start + a_count - 1 <= a_text.count
			bidi_matches: a_bidi.count = a_text.count
			resolves: span_resolves_by_component (a_text, a_start, a_count)
		local
			s, e, l_last: INTEGER
		do
			l_last := a_start + a_count - 1
			from s := a_start until s > l_last loop
				e := component_last (a_text, s, l_last)
				append_emoji (a_into, a_text, a_bidi, s, e - s + 1, <<a_text.code (s)>>)
				s := e + 1
			end
		ensure
			grew: a_into.count > old a_into.count
		end

	append_resolvable_singles (a_into: ARRAYED_LIST [TEXT_SEGMENT]; a_text: READABLE_STRING_32;
			a_bidi: BIDI_RESULT; a_start, a_count: INTEGER)
			-- RUNG 3's aftermath (and the non-RGI position): the span stays
			-- PLAIN except that every character which is an emoji STARTER
			-- with an asset of its own is still lifted into an image, with
			-- its trailing glue. That is exactly `has_resolvable_single''s
			-- test applied character by character, so what
			-- `no_resolvable_single_left_plain' forbids cannot be left
			-- behind - which the postcondition below states outright.
		require
			range_valid: a_start >= 1 and a_count >= 1 and a_start + a_count - 1 <= a_text.count
			bidi_matches: a_bidi.count = a_text.count
		local
			s, e, l_last: INTEGER
			l_code: NATURAL_32
		do
			l_last := a_start + a_count - 1
			from s := a_start until s > l_last loop
				l_code := a_text.code (s)
				if tables.is_emoji_starter (l_code) and then catalog.has_asset (<<l_code>>) then
					e := component_last (a_text, s, l_last)
					append_emoji (a_into, a_text, a_bidi, s, e - s + 1, <<l_code>>)
					s := e + 1
				else
					s := s + 1
				end
			end
		ensure
			every_resolvable_single_lifted: across a_start |..| (a_start + a_count - 1) as k all
				(tables.is_emoji_starter (a_text.code (k))
					and then catalog.has_asset (<<a_text.code (k)>>))
				implies covered_by_emoji (a_into, k) end
			never_shrinks: a_into.count >= old a_into.count
		end

	covered_by_emoji (a_segments: ARRAYED_LIST [TEXT_SEGMENT]; a_index: INTEGER): BOOLEAN
			-- Does some segment of `a_segments' cover character `a_index'?
			-- The contract helper behind `append_resolvable_singles''s
			-- promise; it is what makes `no_resolvable_single_left_plain'
			-- provable at the rung where it is hardest to see.
		do
			Result := across a_segments as s some
				s.start_index <= a_index and a_index <= s.start_index + s.count - 1 end
		end

	append_emoji (a_into: ARRAYED_LIST [TEXT_SEGMENT]; a_text: READABLE_STRING_32;
			a_bidi: BIDI_RESULT; a_start, a_count: INTEGER; a_codes: ARRAY [NATURAL_32])
			-- Append ONE RESOLVED emoji segment covering
			-- `a_start' .. `a_start' + `a_count' - 1, imaged by the asset of
			-- `a_codes' (DR-006: only resolved sequences ever become emoji
			-- segments, which is what makes `emoji_resolved' dischargeable
			-- and IMAGE_RUN's own `resolved' invariant reachable), carrying
			-- the resolved level of its FIRST character - RTL image
			-- placement depends on that.
		require
			range_valid: a_start >= 1 and a_count >= 1 and a_start + a_count - 1 <= a_text.count
			bidi_matches: a_bidi.count = a_text.count
			codes_nonempty: not a_codes.is_empty
			codes_meaningful: catalog.has_non_vs16 (a_codes)
			codes_resolve: catalog.has_asset (a_codes)
		do
			a_into.extend (create {TEXT_SEGMENT}.make_emoji (a_start, a_count,
				a_bidi.level (a_start), tables.codepoints_of (a_text, a_start, a_count),
				catalog.asset_key (a_codes), catalog.asset_path (a_codes)))
		ensure
			one_more: a_into.count = old a_into.count + 1
			resolved_emoji: a_into.last.is_emoji and a_into.last.has_resolved_asset
			range_kept: a_into.last.start_index = a_start and a_into.last.count = a_count
			level_inherited: a_into.last.embedding_level = a_bidi.level (a_start)
		end

	degradation_note (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): SHAPING_NOTE
			-- The ONE Note_emoji_degraded that rung 3 owes the accumulator
			-- for the span it could not image (ISSUE 6). The message names
			-- the asset key that was looked for, so a missing PNG is a
			-- one-line diagnosis rather than a hunt.
		require
			range_valid: a_start >= 1 and a_count >= 1 and a_start + a_count - 1 <= a_text.count
		local
			l_message: STRING_32
			l_codes: ARRAY [NATURAL_32]
		do
			create l_message.make (96)
			l_message.append_string_general ("no Noto asset for this emoji sequence")
			l_codes := tables.codepoints_of (a_text, a_start, a_count)
			if catalog.has_non_vs16 (l_codes) then
				l_message.append_string_general (" (")
				l_message.append_string_general (catalog.asset_key (l_codes))
				l_message.append_string_general (")")
			end
			l_message.append_string_general ("; it stays plain text on the glyph path")
			create Result.make (Note_emoji_degraded, l_message, a_start, a_count)
		ensure
			degradation: Result.code = Note_emoji_degraded
			covers_the_span: Result.source_start = a_start and Result.source_count = a_count
		end

	with_plain_spans (a_emoji: ARRAYED_LIST [TEXT_SEGMENT]; a_character_count: INTEGER): ARRAYED_LIST [TEXT_SEGMENT]
			-- `a_emoji' - ordered, non-overlapping, inside
			-- 1 .. `a_character_count' - with every GAP between them filled
			-- by one PLAIN span. The partition is assembled here, once, so
			-- the scan above cannot get it wrong.
		require
			character_count_non_negative: a_character_count >= 0
		local
			i, l_next: INTEGER
		do
			create Result.make (2 * a_emoji.count + 1)
			l_next := 1
			from i := 1 until i > a_emoji.count loop
				if a_emoji [i].start_index > l_next then
					Result.extend (create {TEXT_SEGMENT}.make_plain (l_next,
						a_emoji [i].start_index - l_next))
				end
				Result.extend (a_emoji [i])
				l_next := a_emoji [i].start_index + a_emoji [i].count
				i := i + 1
			end
			if l_next <= a_character_count then
				Result.extend (create {TEXT_SEGMENT}.make_plain (l_next,
					a_character_count - l_next + 1))
			end
		ensure
			partitions: segments_partition (Result, a_character_count)
			every_emoji_kept: Result.count >= a_emoji.count
		end

end
