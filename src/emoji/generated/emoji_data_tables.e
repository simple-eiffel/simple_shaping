note
	description: "[
		Pinned UTS #51 emoji data (D-S08). GENERATOR-OWNED FILE: Phase 3's
		tools/ generator REPLACES this file from emoji-test.txt (RGI) and
		emoji-zwj-sequences.txt, and records - per R4 (Q6) - the acquired
		Noto Emoji release tag, source URL, archive sha256, and the matching
		data-file versions in tools/. `unicode_version' then becomes the
		Noto release's Unicode emoji version, and EMOJI_ASSET_CATALOG's
		invariant compares it against the asset acquisition record (DR-013:
		tables and assets move in lockstep, one commit).

		Until generation: STRUCTURAL Unicode facts (fixed codepoints and
		ranges - VS16, ZWJ, regional indicators, skin-tone modifiers, the
		keycap combiner) are hand-held and real; SET MEMBERSHIP
		(Extended_Pictographic, RGI sequences) answers False - so the
		segmenter lawfully finds no emoji and every span degrades PLAIN
		(A-C06's last rung), which is exactly the honest pre-asset behavior.
	]"
	author: "Larry Rix (structural stubs); tools/generate_emoji_tables (Phase 3 output)"

class
	EMOJI_DATA_TABLES

feature -- Version (DR-013)

	unicode_version: STRING_8 = "UNPINNED-0.0.0"
			-- Phase 3: the acquired Noto release's Unicode emoji version.

feature -- Structural facts (hand-held, real)

	is_vs16 (a_codepoint: NATURAL_32): BOOLEAN
			-- U+FE0F VARIATION SELECTOR-16 (emoji presentation)?
		do
			Result := a_codepoint = 0xFE0F
		ensure
			definition: Result = (a_codepoint = 0xFE0F)
		end

	is_zwj (a_codepoint: NATURAL_32): BOOLEAN
			-- U+200D ZERO WIDTH JOINER?
		do
			Result := a_codepoint = 0x200D
		ensure
			definition: Result = (a_codepoint = 0x200D)
		end

	is_regional_indicator (a_codepoint: NATURAL_32): BOOLEAN
			-- U+1F1E6 .. U+1F1FF (flag pair halves)?
		do
			Result := a_codepoint >= 0x1F1E6 and a_codepoint <= 0x1F1FF
		ensure
			definition: Result = (a_codepoint >= 0x1F1E6 and a_codepoint <= 0x1F1FF)
		end

	is_emoji_modifier (a_codepoint: NATURAL_32): BOOLEAN
			-- U+1F3FB .. U+1F3FF (skin tones)?
		do
			Result := a_codepoint >= 0x1F3FB and a_codepoint <= 0x1F3FF
		ensure
			definition: Result = (a_codepoint >= 0x1F3FB and a_codepoint <= 0x1F3FF)
		end

	is_combining_enclosing_keycap (a_codepoint: NATURAL_32): BOOLEAN
			-- U+20E3 (keycap sequences)?
		do
			Result := a_codepoint = 0x20E3
		ensure
			definition: Result = (a_codepoint = 0x20E3)
		end

feature -- Generated membership (Phase 3)

	is_extended_pictographic (a_codepoint: NATURAL_32): BOOLEAN
			-- Extended_Pictographic property?
			-- Phase 3: generated table lookup. Until then: False (no emoji
			-- detected; spans stay PLAIN - the lawful pre-asset degradation).
		do
			Result := False
		end

feature -- Composition

	is_emoji_starter (a_codepoint: NATURAL_32): BOOLEAN
			-- Can `a_codepoint' START an emoji sequence (segmentation
			-- trigger)? Inert joiners/selectors/modifiers without a base are
			-- NOT starters.
		do
			Result := is_extended_pictographic (a_codepoint)
				or is_regional_indicator (a_codepoint)
		ensure
			definition: Result = (is_extended_pictographic (a_codepoint)
				or is_regional_indicator (a_codepoint))
		end

end
