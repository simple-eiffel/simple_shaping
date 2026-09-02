note
	description: "[
		Shared constants and pure contract-helper predicates for simple_shaping.

		Direction codes, script-class codes for FONT_LIST policy, SHAPING_NOTE
		codes, limits, and the pure functions that seam postconditions lean on
		(permutation checks, monotonicity over MML sequences, level parity).
		Conventional constants mixin (04): facade, seams, engines and the run
		model inherit it; everything here is pure and processor-confined-safe.
	]"
	author: "Larry Rix"

class
	SHAPING_CONSTANTS

feature -- Direction codes

	Direction_ltr: INTEGER = 0
			-- Forced left-to-right paragraph base.

	Direction_rtl: INTEGER = 1
			-- Forced right-to-left paragraph base.

	Direction_auto: INTEGER = 2
			-- First-strong paragraph direction detection (UAX #9 P2/P3).

	is_valid_base_direction (a_direction: INTEGER): BOOLEAN
			-- Is `a_direction` one of the three base-direction codes?
		do
			Result := a_direction = Direction_ltr or a_direction = Direction_rtl or a_direction = Direction_auto
		ensure
			definition: Result = (a_direction = Direction_ltr or a_direction = Direction_rtl or a_direction = Direction_auto)
		end

feature -- Script classes (FONT_LIST fallback policy buckets)

	Script_class_hebrew: INTEGER = 1
	Script_class_greek: INTEGER = 2
	Script_class_latin: INTEGER = 3
	Script_class_symbol: INTEGER = 4
	Script_class_other: INTEGER = 5

	is_valid_script_class (a_class: INTEGER): BOOLEAN
			-- Is `a_class` a known FONT_LIST script class?
			-- NOTE: these are OUR fallback-policy buckets. They are NOT the
			-- engine-internal script ids carried by SCRIPT_ITEM.script_code,
			-- which are opaque and never comparable across backends.
		do
			Result := a_class >= Script_class_hebrew and a_class <= Script_class_other
		ensure
			definition: Result = (a_class >= Script_class_hebrew and a_class <= Script_class_other)
		end

feature -- Note codes (degradation observability channel, NFR-011)

	Note_fallback_exhausted: INTEGER = 1
			-- No configured font covered a stretch; requested font's
			-- missing-glyph boxes were used (DR-010).

	Note_emoji_degraded: INTEGER = 2
			-- An emoji sequence had no full-sequence asset and no complete
			-- per-codepoint assets; it stayed PLAIN into the glyph path (A-C06).

	Note_backend_error_recovered: INTEGER = 3
			-- A native call failed hard; the item degraded to a synthesized
			-- tofu run (glyph id 0 per character, advance pixel_size/2, and a
			-- TRIVIAL ONE-TO-ONE CLUSTER MAP, REVERSED FOR RTL ITEMS) -
			-- "tofu-but-valid", never a dropped range (R3, amended Phase 2 /
			-- ISSUE 12: an identity map violates `clusters_monotone_rtl' for
			-- any RTL item of 2+ characters, so "identity" was impossible).

	Note_family_missing: INTEGER = 4
			-- A configured font family was absent at realization and was
			-- dropped from the effective list (R1).

	Note_asset_missing: INTEGER = 5
			-- The configured asset directory lacked an expected file.

	is_valid_note_code (a_code: INTEGER): BOOLEAN
			-- Is `a_code` a known SHAPING_NOTE code?
		do
			Result := a_code >= Note_fallback_exhausted and a_code <= Note_asset_missing
		ensure
			definition: Result = (a_code >= Note_fallback_exhausted and a_code <= Note_asset_missing)
		end

feature -- Limits

	Max_bidi_level: NATURAL_8 = 125
			-- UAX #9 max_depth for explicit embeddings.

	No_wrap: INTEGER = 0
			-- Width value meaning: one unbounded line.

	Default_cache_capacity: INTEGER = 512
			-- LAYOUT_CACHE default (Q2: ~2.5x a 200-message scrollback).

feature -- Contract helpers (pure)

	occurrences_in (a_values: ARRAY [INTEGER]; a_value: INTEGER): INTEGER
			-- How many entries of `a_values` equal `a_value`?
		local
			i: INTEGER
		do
			from i := a_values.lower until i > a_values.upper loop
				if a_values [i] = a_value then
					Result := Result + 1
				end
				i := i + 1
			end
		ensure
			non_negative: Result >= 0
		end

	is_identity (a_permutation: ARRAY [INTEGER]): BOOLEAN
			-- Is `a_permutation` the identity mapping i -> i?
		local
			i: INTEGER
		do
			Result := True
			from i := a_permutation.lower until i > a_permutation.upper or not Result loop
				Result := a_permutation [i] = i - a_permutation.lower + 1
				i := i + 1
			end
		end

	is_all_even (a_levels: ARRAY [NATURAL_8]): BOOLEAN
			-- Are all levels even (pure LTR line)?
		local
			i: INTEGER
		do
			Result := True
			from i := a_levels.lower until i > a_levels.upper or not Result loop
				Result := a_levels [i] \\ 2 = 0
				i := i + 1
			end
		end

	is_all_odd (a_levels: ARRAY [NATURAL_8]): BOOLEAN
			-- Are all levels odd (pure RTL line)? Vacuously True when empty.
		local
			i: INTEGER
		do
			Result := True
			from i := a_levels.lower until i > a_levels.upper or not Result loop
				Result := a_levels [i] \\ 2 = 1
				i := i + 1
			end
		end

	is_reversal (a_permutation: ARRAY [INTEGER]): BOOLEAN
			-- Is `a_permutation` the full reversal i -> count + 1 - i
			-- (the UAX #9 L2 answer for an all-odd line)?
		local
			i: INTEGER
		do
			Result := True
			from i := a_permutation.lower until i > a_permutation.upper or not Result loop
				Result := a_permutation [i] = a_permutation.count - (i - a_permutation.lower)
				i := i + 1
			end
		end

	is_non_decreasing (a_sequence: MML_SEQUENCE [INTEGER]): BOOLEAN
			-- Is `a_sequence` sorted non-decreasing (LTR cluster maps)?
		local
			i: INTEGER
		do
			Result := True
			from i := 1 until i >= a_sequence.count or not Result loop
				Result := a_sequence [i] <= a_sequence [i + 1]
				i := i + 1
			end
		end

	is_non_increasing (a_sequence: MML_SEQUENCE [INTEGER]): BOOLEAN
			-- Is `a_sequence` sorted non-increasing (RTL cluster maps)?
		local
			i: INTEGER
		do
			Result := True
			from i := 1 until i >= a_sequence.count or not Result loop
				Result := a_sequence [i] >= a_sequence [i + 1]
				i := i + 1
			end
		end

	non_negative (a_index: INTEGER; a_value: REAL_64): BOOLEAN
			-- Predicate for MML for_all over advance sequences.
		do
			Result := a_value >= 0.0
		ensure
			definition: Result = (a_value >= 0.0)
		end

	level_bounded (a_index: INTEGER; a_level: NATURAL_8): BOOLEAN
			-- Predicate for MML for_all over level sequences (DR-001).
		do
			Result := a_level <= Max_bidi_level
		ensure
			definition: Result = (a_level <= Max_bidi_level)
		end

	lines_partition_text (a_lines: ARRAYED_LIST [SHAPED_LINE]; a_character_count: INTEGER): BOOLEAN
			-- Do `a_lines` cover characters 1 .. `a_character_count` contiguously,
			-- in order, exactly once (DR-008)? Empty text: one line of count 0.
		local
			i, l_next: INTEGER
		do
			if a_lines.is_empty then
				Result := False
			else
				Result := True
				l_next := 1
				from i := 1 until i > a_lines.count or not Result loop
					Result := a_lines [i].source_start = l_next and a_lines [i].source_count >= 0
					l_next := l_next + a_lines [i].source_count
					i := i + 1
				end
				Result := Result and l_next = a_character_count + 1
			end
		end

	runs_at_layout_size (a_lines: ARRAYED_LIST [SHAPED_LINE]; a_pixel_size: INTEGER): BOOLEAN
			-- Is EVERY glyph run in `a_lines` shaped at `a_pixel_size`
			-- (D-S03 same-N, closed Phase 2 / ISSUE 8)? Image runs carry no
			-- font and are exempt; a run-less line is vacuously fine.
			--
			-- GLYPH_RUN.pixel_size is DEFINED as font.pixel_size, so its own
			-- `same_n_rule` ensure proves nothing; seam 4 preserves size only
			-- relative to the REQUESTED font. This predicate is the missing
			-- link: it forces the requested font itself to have been realized
			-- at the LAYOUT's size, so a Phase-4 body cannot shape at one
			-- size and stamp the layout with another.
		do
			Result := True
			across a_lines as l loop
				across l.runs as r loop
					if attached {GLYPH_RUN} r as al_glyphs then
						Result := Result and al_glyphs.font.pixel_size = a_pixel_size
					end
				end
			end
		end

end
