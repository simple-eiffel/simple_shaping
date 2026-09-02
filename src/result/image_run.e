note
	description: "[
		One resolved emoji sequence as a fixed image box (G3: Noto png/128;
		emoji_u1f916.png is U+1F916) - pixel-identical on every machine.

		ALWAYS RESOLVED (DR-006/A-C06): sequences without assets are degraded
		to the glyph path BEFORE run construction, inside EMOJI_SEGMENTER's
		FR-007 ladder - so a consumer never handles a broken image. The
		invariant `resolved' is that promise, unweakened.

		Immutable value.
	]"
	author: "Larry Rix"

class
	IMAGE_RUN

inherit
	SHAPED_RUN

create
	make

feature {NONE} -- Initialization

	make (a_source_start, a_source_count: INTEGER; a_level: NATURAL_8;
			a_codepoints: ARRAY [NATURAL_32];
			a_asset_key: READABLE_STRING_8; a_asset_path: READABLE_STRING_32;
			a_width, a_height: REAL_64)
			-- One emoji image box over paragraph characters
			-- `a_source_start' .. `a_source_start' + `a_source_count' - 1.
		require
			range_valid: a_source_start >= 1 and a_source_count > 0
			level_bounded: a_level <= Max_bidi_level
			codepoints_nonempty: not a_codepoints.is_empty
			key_resolved: not a_asset_key.is_empty
			path_resolved: not a_asset_path.is_empty
			box_positive: a_width > 0.0 and a_height > 0.0
		do
			source_start := a_source_start
			source_count := a_source_count
			embedding_level := a_level
			codepoints := a_codepoints
			create asset_key.make_from_string (a_asset_key)
			create asset_path.make_from_string_general (a_asset_path)
			width := a_width
			height := a_height
		ensure
			range_set: source_start = a_source_start and source_count = a_source_count
			level_set: embedding_level = a_level
			key_kept: asset_key.same_string (a_asset_key)
			path_kept: asset_path.same_string_general (a_asset_path)
			box_set: width = a_width and height = a_height
		end

feature -- Access

	source_start: INTEGER
			-- <Precursor>

	source_count: INTEGER
			-- <Precursor>

	embedding_level: NATURAL_8
			-- <Precursor>

	height: REAL_64
			-- <Precursor>

	codepoints: ARRAY [NATURAL_32]
			-- The emoji sequence as it appeared in the text (VS16 included
			-- here if present; the KEY drops it per Noto naming).

	asset_key: IMMUTABLE_STRING_8
			-- Noto asset name, e.g. "emoji_u1f916"; VS16 dropped, ZWJ
			-- sequence codepoints joined with '_'.

	asset_path: IMMUTABLE_STRING_32
			-- Absolute path under the configured asset directory.

	width: REAL_64
			-- Box width in pixels (advance_width = width for image runs).

	advance_width: REAL_64
			-- <Precursor>: an image box advances by exactly its width.
		do
			Result := width
		ensure then
			box_is_advance: Result = width
		end

feature -- Model queries (simple_mml)

	codepoints_model: MML_SEQUENCE [NATURAL_32]
			-- Codepoint sequence as a mathematical sequence.
		local
			i: INTEGER
		do
			create Result
			from i := codepoints.lower until i > codepoints.upper loop
				Result := Result & codepoints [i]
				i := i + 1
			end
		ensure
			same_count: Result.count = codepoints.count
		end

invariant
	codepoints_nonempty: not codepoints.is_empty
	resolved: not asset_key.is_empty and not asset_path.is_empty
	box_positive: width > 0.0 and height > 0.0

end
