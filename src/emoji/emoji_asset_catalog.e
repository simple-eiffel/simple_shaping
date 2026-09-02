note
	description: "[
		Codepoint sequence -> Noto asset name/path (G3).

		NAMING (contracted, real now): keys follow the Noto png scheme -
		"emoji_u" + lowercase hex codepoints joined by '_', VS16 (U+FE0F)
		DROPPED: [1F916] -> "emoji_u1f916"; [2764, FE0F] -> "emoji_u2764";
		ZWJ family members joined: [1F469, 200D, 1F4BB] ->
		"emoji_u1f469_200d_1f4bb".

		RESOLUTION WITHOUT DISK (Phase 1 decision, documented): existence is
		answered by an INJECTED probe function - production (Phase 4) injects
		a real file probe over the acquired assets/ (Phase 3, R4); tests
		inject pure predicates; production BEFORE assets exist creates via
		`make_without_assets' (no probe: nothing exists), so every sequence
		lawfully degrades PLAIN until assets ship (A-C06's last rung).
		Verdicts memoize into `resolved' (benign, write-once growth).

		DR-013: the invariant pins `data_tables.unicode_version' to this
		catalog's `expected_unicode_version' - Phase 3 sets the expectation
		from the asset acquisition record so tables and assets cannot drift
		apart silently.
	]"
	author: "Larry Rix"

class
	EMOJI_ASSET_CATALOG

create
	make, make_without_assets

feature {NONE} -- Initialization

	make (a_directory: READABLE_STRING_32; a_tables: EMOJI_DATA_TABLES;
			a_exists_probe: FUNCTION [READABLE_STRING_32, BOOLEAN])
			-- Catalog over `a_directory', deciding existence via
			-- `a_exists_probe' (disk-free by injection).
		require
			directory_not_empty: not a_directory.is_empty
		do
			create directory.make_from_string_general (a_directory)
			data_tables := a_tables
			exists_probe := a_exists_probe
			expected_unicode_version := a_tables.unicode_version
				-- Phase 3: replaced by the acquisition record's constant (R4).
			create resolved.make (16)
		ensure
			directory_set: directory.same_string_general (a_directory)
			tables_kept: data_tables = a_tables
			probe_kept: exists_probe = a_exists_probe
			expectation_pinned: expected_unicode_version ~ a_tables.unicode_version
			nothing_resolved: resolved_model.is_empty
		end

	make_without_assets (a_directory: READABLE_STRING_32; a_tables: EMOJI_DATA_TABLES)
			-- The pre-asset catalog (before Phase 3's acquisition): no
			-- probe, nothing exists, every sequence degrades PLAIN
			-- (A-C06's last rung).
		require
			directory_not_empty: not a_directory.is_empty
		do
			create directory.make_from_string_general (a_directory)
			data_tables := a_tables
			expected_unicode_version := a_tables.unicode_version
			create resolved.make (0)
		ensure
			directory_set: directory.same_string_general (a_directory)
			tables_kept: data_tables = a_tables
			probeless: exists_probe = Void
			expectation_pinned: expected_unicode_version ~ a_tables.unicode_version
			nothing_resolved: resolved_model.is_empty
		end

feature -- Access

	directory: IMMUTABLE_STRING_32
			-- Root of the Noto png/128 assets.

	data_tables: EMOJI_DATA_TABLES
			-- The pinned tables this catalog must match (DR-013).

	expected_unicode_version: STRING_8
			-- The asset set's Unicode emoji version (R4 record).

	asset_key (a_codepoints: ARRAY [NATURAL_32]): STRING_8
			-- Noto naming for `a_codepoints' (see class note).
		require
			nonempty: not a_codepoints.is_empty
			meaningful: has_non_vs16 (a_codepoints)
		local
			i: INTEGER
			l_first: BOOLEAN
		do
			create Result.make (16)
			Result.append ("emoji_u")
			l_first := True
			from i := a_codepoints.lower until i > a_codepoints.upper loop
				if not data_tables.is_vs16 (a_codepoints [i]) then
					if not l_first then
						Result.append_character ('_')
					end
					Result.append (lower_hex (a_codepoints [i]))
					l_first := False
				end
				i := i + 1
			end
		ensure
			noto_prefix: Result.starts_with ("emoji_u")
			no_vs16_component: not Result.has_substring ("fe0f")
			deterministic: Result ~ asset_key (a_codepoints)
		end

	has_asset (a_codepoints: ARRAY [NATURAL_32]): BOOLEAN
			-- Does the full-sequence asset for `a_codepoints' exist (per the
			-- injected probe)? Memoizes positive verdicts (benign).
		require
			nonempty: not a_codepoints.is_empty
			meaningful: has_non_vs16 (a_codepoints)
		local
			l_key: STRING_8
			l_path: STRING_32
		do
			l_key := asset_key (a_codepoints)
			if resolved.has (l_key) then
				Result := True
			else
				l_path := path_for (l_key)
				if attached exists_probe as al_probe and then al_probe.item ([l_path]) then
					resolved.put (create {IMMUTABLE_STRING_32}.make_from_string_general (l_path), l_key)
					Result := True
				end
			end
		ensure
			resolution_cached: Result implies resolved_model.domain [asset_key (a_codepoints)]
			memo_only_grows: resolved_model.count >= old resolved_model.count
			growth_bounded: resolved_model.count <= old resolved_model.count + 1
			domain_monotone: (old resolved_model).domain <= resolved_model.domain
			verdicts_write_once: (resolved_model | (old resolved_model).domain) |=| old resolved_model
			negative_no_memo: not Result implies resolved_model |=| old resolved_model
		end

	asset_path (a_codepoints: ARRAY [NATURAL_32]): IMMUTABLE_STRING_32
			-- Absolute path of the resolved asset.
		require
			nonempty: not a_codepoints.is_empty
			meaningful: has_non_vs16 (a_codepoints)
			known: has_asset (a_codepoints)
		do
			Result := resolved.definite_item (asset_key (a_codepoints))
		ensure
			under_directory: Result.starts_with (directory)
			is_png: Result.ends_with ({STRING_32} ".png")
			memo_unchanged: resolved_model |=| old resolved_model
			key_derived: Result.same_string_general (path_for (asset_key (a_codepoints)))
		end

	path_for (a_key: READABLE_STRING_8): STRING_32
			-- Where `a_key''s file would live under `directory'.
		require
			key_not_empty: not a_key.is_empty
		do
			create Result.make (directory.count + a_key.count + 5)
			Result.append_string_general (directory)
			Result.append_character ('\')
			Result.append_string_general (a_key)
			Result.append_string_general (".png")
		ensure
			under_directory: Result.starts_with (directory)
			is_png: Result.ends_with ({STRING_32} ".png")
		end

	has_non_vs16 (a_codepoints: ARRAY [NATURAL_32]): BOOLEAN
			-- Is at least one codepoint not VS16 (so a key exists)?
		do
			Result := across a_codepoints as cp some not data_tables.is_vs16 (cp) end
		end

feature -- Model queries (simple_mml)

	resolved_model: MML_MAP [STRING_8, IMMUTABLE_STRING_32]
			-- Memoized key -> path resolutions as a mathematical map.
		local
			l_keys: ARRAY [STRING_8]
			i: INTEGER
		do
			create Result
			l_keys := resolved.current_keys
			from i := l_keys.lower until i > l_keys.upper loop
				Result := Result.updated (l_keys [i], resolved.definite_item (l_keys [i]))
				i := i + 1
			end
		end

feature {NONE} -- Implementation

	exists_probe: detachable FUNCTION [READABLE_STRING_32, BOOLEAN]
			-- The injected existence decision (see class note); Void =
			-- nothing exists (the pre-asset state, `make_without_assets').

	resolved: HASH_TABLE [IMMUTABLE_STRING_32, STRING_8]
			-- Positive verdicts: key -> absolute path.

	lower_hex (a_codepoint: NATURAL_32): STRING_8
			-- Lowercase hex of `a_codepoint', no leading zeros ("1f916").
		local
			v, d: NATURAL_32
		do
			create Result.make (6)
			if a_codepoint = 0 then
				Result.append_character ('0')
			else
				from v := a_codepoint until v = 0 loop
					d := v \\ 16
					Result.prepend_character (Hex_digits [d.to_integer_32 + 1])
					v := v // 16
				end
			end
		ensure
			never_empty: not Result.is_empty
		end

	Hex_digits: STRING_8 = "0123456789abcdef"

invariant
	tables_and_assets_pinned_together: data_tables.unicode_version ~ expected_unicode_version
	resolved_paths_under_directory: across resolved as p all p.starts_with (directory) end

end
