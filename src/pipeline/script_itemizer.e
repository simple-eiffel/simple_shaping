note
	description: "[
		Seam 2 of four (C-006/D-014): split a PLAIN span into the items one
		engine shapes with one font, plus per-item soft-break flags (A-C07:
		break opportunities are a property of characters and their analysis,
		so they live on THIS seam, not on the shaper).

		THE OUTPUT IS THE SCRIPT x BIDI INTERSECTION - not the raw script-run
		table. The dwrite spike measured why this must be said: DirectWrite's
		AnalyzeScript alone MERGES Common-script characters (spaces, emoji
		surrogate pairs) into neighboring script runs (3 script runs for the
		D-015 probe text), while AnalyzeBidi produced 2 level runs; the
		itemizer's lawful output was their intersection - 4 runs, each with
		ONE script id and ONE bidi level. The postconditions demand: the items
		partition the span contiguously in order; every item's characters
		share the item's level (checked against BIDI_RESULT); and adjacent
		items differ in script id or level.

		WHAT THE ORACLE ACTUALLY ENFORCES (Phase 2, ISSUE 20): LEVEL
		boundaries are checked in BOTH directions - `one_level_per_item'
		forces a split at every level change, `boundaries_are_script_or_bidi'
		forbids a split that is neither. SCRIPT boundaries are the ENGINE'S
		OWN CLAIM: `script_code' is an opaque self-reported int, so a backend
		can merge across a script change or split within one script by
		varying ids and still satisfy the letter. Read the emitted boundaries
		as "the bidi boundaries, oracle-checked, plus whatever script
		boundaries the engine claims" - not as a verified union.

		SCRIPT IDS ARE ENGINE-INTERNAL OPAQUE INTS - not ISO 15924. Never
		compare them across backends (spike: Hebrew/Greek/Latin = 36/30/49
		under DirectWrite; Uniscribe numbers differently).

		CALLER DUTY, NOT A PRECONDITION (Phase 2, ISSUE 1): EMOJI_SEGMENTER
		runs after bidi resolution and BEFORE itemization, and the facade
		must hand THIS seam only the segmenter's PLAIN spans (DR-005). That
		duty is stated here and nowhere else - there is deliberately NO
		`plain_span_only' precondition, because FR-007 rung 3 (A-C06)
		lawfully leaves an UNRESOLVABLE emoji sequence PLAIN and sends it
		down the glyph path. A pictograph arriving here is therefore not a
		caller bug: it IS rung 3. The spike measured what happens next -
		DirectWrite folds U+1F916 into a neighboring text run and GetGlyphs
		shapes its surrogates to .notdef (glyph id 0) - i.e. tofu by
		construction, which is exactly the degradation rung 3 promises, and
		the never-raises law (NFR-011) requires that it degrade rather than
		trip an assertion.

		Backends: DIRECTWRITE_SCRIPT_ITEMIZER (MVP, G1 final);
		UNISCRIBE_SCRIPT_ITEMIZER named alternate (does not exist yet);
		NULL_ double; EIFFEL_ future (D-S06).
	]"
	author: "Larry Rix"
	never_raises: "No exception propagates from any seam feature; failures degrade per NFR-011."

deferred class
	SCRIPT_ITEMIZER

inherit
	SHAPING_CONSTANTS

feature -- Operations

	itemize (a_text: READABLE_STRING_32; a_start, a_count: INTEGER;
			a_bidi: BIDI_RESULT): ARRAYED_LIST [SCRIPT_ITEM]
			-- Same-script, same-level items covering
			-- a_text [`a_start' .. `a_start' + `a_count' - 1] - normally a
			-- PLAIN span from EMOJI_SEGMENTER (DR-005; class-note caller
			-- duty). An unresolvable pictograph reaching here degrades to
			-- .notdef by construction - FR-007 rung 3 - never an assertion.
		require
			range_valid: a_start >= 1 and a_count >= 0 and a_start + a_count - 1 <= a_text.count
			bidi_covers: a_bidi.count = a_text.count
		deferred
		ensure
			never_void: Result /= Void
			empty_iff_empty: Result.is_empty = (a_count = 0)
			first_at_start: a_count > 0 implies Result.first.start_index = a_start
			contiguous: across 1 |..| (Result.count - 1) as i all
				Result [i + 1].start_index = Result [i].start_index + Result [i].count end
			total_cover: a_count > 0 implies
				Result.last.start_index + Result.last.count = a_start + a_count
			items_nonempty: across Result as it all it.count > 0 end
			one_level_per_item: across Result as it all levels_constant_within (a_bidi, it) end
			boundaries_are_script_or_bidi: across 1 |..| (Result.count - 1) as i all
				Result [i + 1].script_code /= Result [i].script_code
				or Result [i + 1].embedding_level /= Result [i].embedding_level end
		end

	soft_breaks (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM): ARRAY [BOOLEAN]
			-- True at i = wrap legally allowed BEFORE the item's i-th
			-- character (A-C07). Layout additionally refuses breaks inside
			-- clusters and emoji segments regardless of these flags (DR-007).
		require
			item_in_text: a_item.start_index + a_item.count - 1 <= a_text.count
		deferred
		ensure
			one_per_character: Result.count = a_item.count
			one_based: Result.lower = 1
			no_break_before_first: a_item.count > 0 implies not Result [1]
		end

feature -- Contract support

	levels_constant_within (a_bidi: BIDI_RESULT; a_item: SCRIPT_ITEM): BOOLEAN
			-- Do all of `a_item''s characters carry exactly
			-- `a_item.embedding_level' in `a_bidi'?
		require
			item_covered: a_item.start_index + a_item.count - 1 <= a_bidi.count
		local
			i: INTEGER
		do
			Result := True
			from i := a_item.start_index until i > a_item.start_index + a_item.count - 1 or not Result loop
				Result := a_bidi.level (i) = a_item.embedding_level
				i := i + 1
			end
		end

note
	emoji_tables_ownership: "[
		ISSUE 19 (Phase 2) closed with ISSUE 1: this class no longer owns an
		EMOJI_DATA_TABLES `once'. The facade owns the SINGLE instance and
		injects it into EMOJI_SEGMENTER and EMOJI_ASSET_CATALOG, so no
		descendant-injected table can ever disagree with a base-class one
		about what "emoji" means.
	]"

end
