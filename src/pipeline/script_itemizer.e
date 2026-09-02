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
		items differ in script id or level - so emitted boundaries are exactly
		the union of script boundaries and bidi boundaries. (Script-run
		constancy WITHIN an item is the engine's own claim over its opaque
		ids; level constancy is externally checked.)

		SCRIPT IDS ARE ENGINE-INTERNAL OPAQUE INTS - not ISO 15924. Never
		compare them across backends (spike: Hebrew/Greek/Latin = 36/30/49
		under DirectWrite; Uniscribe numbers differently).

		EMOJI NEVER ARRIVE HERE (DR-005): EMOJI_SEGMENTER runs after bidi
		resolution and BEFORE itemization, and `itemize''s precondition
		accepts only emoji-free spans. The spike proved the necessity:
		DirectWrite folds U+1F916 into a neighboring text run and GetGlyphs
		shapes it to .notdef (glyph id 0) - an emoji reaching a shaper is
		tofu by construction.

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
			-- a_text [`a_start' .. `a_start' + `a_count' - 1] - a PLAIN,
			-- emoji-free span (DR-005).
		require
			range_valid: a_start >= 1 and a_count >= 0 and a_start + a_count - 1 <= a_text.count
			bidi_covers: a_bidi.count = a_text.count
			plain_span_only: is_emoji_free (a_text, a_start, a_count)
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

	is_emoji_free (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): BOOLEAN
			-- Does a_text [`a_start' .. `a_start' + `a_count' - 1] contain no
			-- emoji sequence STARTER (Extended_Pictographic or regional
			-- indicator)? Inert joiners/selectors (ZWJ, VS16) without a base
			-- do not make a span emoji-laden.
		require
			range_valid: a_start >= 1 and a_count >= 0 and a_start + a_count - 1 <= a_text.count
		local
			i: INTEGER
		do
			Result := True
			from i := a_start until i > a_start + a_count - 1 or not Result loop
				Result := not emoji_tables.is_emoji_starter (a_text.code (i))
				i := i + 1
			end
		end

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

feature {NONE} -- Implementation

	emoji_tables: EMOJI_DATA_TABLES
			-- Shared structural emoji data (immutable; per-thread once is
			-- confinement-safe, DR-012).
		once
			create Result
		end

end
