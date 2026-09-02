note
	description: "[
		One pre-itemization span of the paragraph: PLAIN text destined for the
		itemizer/shaper, or one EMOJI sequence destined for the image path
		(UTS #51). Produced by EMOJI_SEGMENTER AFTER bidi resolution and
		BEFORE itemization (DR-005/A-C03) - so emoji spans inherit resolved
		levels and the shaper NEVER sees an emoji.

		DR-006: an emoji segment is ALWAYS resolved (asset key + path):
		unresolvable sequences stayed PLAIN under the FR-007 ladder and this
		class never sees them as emoji.

		`embedding_level' is load-bearing for EMOJI segments (image box
		placement in RTL lines); PLAIN spans carry per-character levels in
		BIDI_RESULT and store 0 here.

		Immutable value.
	]"
	author: "Larry Rix"

class
	TEXT_SEGMENT

inherit
	SHAPING_CONSTANTS

create
	make_plain, make_emoji

feature {NONE} -- Initialization

	make_plain (a_start, a_count: INTEGER)
			-- A plain span over characters `a_start' .. `a_start' + `a_count' - 1.
		require
			range_valid: a_start >= 1 and a_count > 0
		do
			start_index := a_start
			count := a_count
			is_plain := True
			create codepoints.make_empty
			create asset_key.make_from_string ("")
			create asset_path.make_from_string_general ("")
		ensure
			plain: is_plain
			range_set: start_index = a_start and count = a_count
			bare: codepoints.is_empty
		end

	make_emoji (a_start, a_count: INTEGER; a_level: NATURAL_8;
			a_codepoints: ARRAY [NATURAL_32];
			a_asset_key: READABLE_STRING_8; a_asset_path: READABLE_STRING_32)
			-- A RESOLVED emoji span (DR-006: the catalog already answered).
		require
			range_valid: a_start >= 1 and a_count > 0
			level_bounded: a_level <= Max_bidi_level
			codepoints_nonempty: not a_codepoints.is_empty
			key_resolved: not a_asset_key.is_empty
			path_resolved: not a_asset_path.is_empty
		do
			start_index := a_start
			count := a_count
			embedding_level := a_level
			is_plain := False
			codepoints := a_codepoints
			create asset_key.make_from_string (a_asset_key)
			create asset_path.make_from_string_general (a_asset_path)
		ensure
			emoji: is_emoji
			range_set: start_index = a_start and count = a_count
			level_set: embedding_level = a_level
			resolved: has_resolved_asset
		end

feature -- Access

	start_index: INTEGER
			-- First character (1-based, code-point space).

	count: INTEGER
			-- Number of characters.

	embedding_level: NATURAL_8
			-- Resolved level (meaningful for emoji segments; 0 for plain).

	codepoints: ARRAY [NATURAL_32]
			-- The emoji sequence (empty for plain spans).

	asset_key: IMMUTABLE_STRING_8
			-- Resolved Noto asset key (empty for plain spans).

	asset_path: IMMUTABLE_STRING_32
			-- Resolved absolute asset path (empty for plain spans).

feature -- Status

	is_plain: BOOLEAN
			-- Is this a plain text span (itemizer/shaper path)?

	is_emoji: BOOLEAN
			-- Is this an emoji sequence (image path)?
		do
			Result := not is_plain
		ensure
			definition: Result = not is_plain
		end

	has_resolved_asset: BOOLEAN
			-- Are both asset key and path present?
		do
			Result := not asset_key.is_empty and not asset_path.is_empty
		ensure
			definition: Result = (not asset_key.is_empty and not asset_path.is_empty)
		end

invariant
	range_valid: start_index >= 1 and count > 0
	emoji_resolved: is_emoji implies has_resolved_asset
	plain_bare: is_plain implies codepoints.is_empty
	emoji_carries_sequence: is_emoji implies not codepoints.is_empty

end
