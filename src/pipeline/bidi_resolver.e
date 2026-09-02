note
	description: "[
		Seam 1 of four (C-006/D-014): UAX #9 embedding levels for a paragraph
		plus the per-line visual permutation (L2).

		THE CONTRACTS BELOW ARE NORMATIVE (I-001): they are the cross-backend
		equivalence oracle. Effectings may KEEP or STRENGTHEN every ensure and
		KEEP or WEAKEN every require - never the reverse. Full UAX #9
		conformance is NOT statable here; it is delegated to
		BIDI_CONFORMANCE_HARNESS (sampled in MVP, FULL BidiTest.txt +
		BidiCharacterTest.txt at Phase 5 - NFR-008).

		Backends: DIRECTWRITE_BIDI_RESOLVER is the MVP effecting (G1 FINAL,
		2026-09-01: Larry's ruling + the spikes/dwrite verdict PASS).
		UNISCRIBE_BIDI_RESOLVER (ScriptItemize levels + ScriptLayout reorder)
		is the named alternate slot - it does not exist yet. NULL_ is the
		headless double. EIFFEL_ is future, promotion-gated on the FULL
		conformance run (D-S06).

		All positions and counts are in READABLE_STRING_32 code-point space;
		UTF-16 is a backend-internal boundary concern.
	]"
	author: "Larry Rix"
	never_raises: "No exception propagates from any seam feature; failures degrade per NFR-011."

deferred class
	BIDI_RESOLVER

inherit
	SHAPING_CONSTANTS

feature -- Operations

	resolve (a_text: READABLE_STRING_32; a_base_direction: INTEGER): BIDI_RESULT
			-- Embedding levels for `a_text'; base Direction_auto
			-- (first-strong), Direction_ltr, or Direction_rtl.
		require
			base_valid: is_valid_base_direction (a_base_direction)
		deferred
		ensure
			never_void: Result /= Void
			one_level_per_character: Result.levels_model.count = a_text.count
			levels_bounded: Result.levels_model.for_all (agent level_bounded)
			paragraph_level_binary: Result.paragraph_level <= 1
			forced_ltr: a_base_direction = Direction_ltr implies Result.paragraph_level = 0
			forced_rtl: a_base_direction = Direction_rtl implies Result.paragraph_level = 1
			empty_text_default: a_text.is_empty implies Result.levels_model.is_empty
		end

	reorder (a_levels: ARRAY [NATURAL_8]): ARRAY [INTEGER]
			-- Visual order of `a_levels.count' logical positions for ONE line
			-- (UAX #9 L2): Result [visual_position] = logical_position.
		deferred
		ensure
			same_count: Result.count = a_levels.count
			one_based: Result.lower = 1
			is_permutation: across 1 |..| Result.count as i all occurrences_in (Result, i) = 1 end
			indices_in_range: across Result as r all r >= 1 and r <= a_levels.count end
			ltr_identity: is_all_even (a_levels) implies is_identity (Result)
		end

end
