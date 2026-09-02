note
	description: "[
		Creates, caches, and (Phase 4) disposes SHAPING_FONTs for ONE facade
		on ONE processor (DR-012/OQ-1). Owns native lifetime: HFONT/HDC and
		backend handles live and die here, never in value classes (04).

		The ownership contract is statable and stated: every cached font's
		back-pointer names THIS registry (invariant), fixed at birth
		(SHAPING_FONT.make's owner_registered) - a font cannot lawfully
		migrate between processors.

		R1: Phase 4's realization step is where the existence probe runs;
		a missing family falls back to the effective list's next entry with
		one Note_family_missing.
	]"
	author: "Larry Rix"

class
	FONT_REGISTRY

create
	make

feature {NONE} -- Initialization

	make
			-- Empty registry.
		do
			create fonts.make (8)
		ensure
			registry_empty: fonts_model.is_empty
		end

feature -- Access

	count: INTEGER
			-- Realized identities held.
		do
			Result := fonts.count
		ensure
			non_negative: Result >= 0
		end

	font (a_family: READABLE_STRING_32; a_weight: INTEGER; a_italic: BOOLEAN;
			a_pixel_size: INTEGER): SHAPING_FONT
			-- The one SHAPING_FONT for this identity - created on first use,
			-- cached thereafter (same object every call; D-S03 demands one
			-- holder per identity so SCRIPT-level caches and faces never split).
		require
			family_not_empty: not a_family.is_empty
			weight_range: a_weight >= 1 and a_weight <= 1000
			size_positive: a_pixel_size > 0
		local
			l_key: STRING_32
		do
			l_key := registry_key (a_family, a_weight, a_italic, a_pixel_size)
			if attached fonts.item (l_key) as al_font then
				Result := al_font
			else
				create Result.make (a_family, a_weight, a_italic, a_pixel_size, Current)
				fonts.put (Result, l_key)
			end
		ensure
			identity: Result.family.same_string_general (a_family)
				and Result.weight = a_weight and Result.is_italic = a_italic
				and Result.pixel_size = a_pixel_size
			owned: Result.registry = Current
			registered: fonts_model.domain [registry_key (a_family, a_weight, a_italic, a_pixel_size)]
			growth_bounded: fonts_model.count <= old fonts_model.count + 1
			idempotent: (old fonts_model.domain [registry_key (a_family, a_weight, a_italic, a_pixel_size)])
				implies fonts_model.count = old fonts_model.count
		end

	registry_key (a_family: READABLE_STRING_32; a_weight: INTEGER; a_italic: BOOLEAN;
			a_pixel_size: INTEGER): STRING_32
			-- Deterministic identity key (case-folded family | weight |
			-- italic | size).
		require
			family_not_empty: not a_family.is_empty
		do
			create Result.make (a_family.count + 12)
			Result.append_string_general (a_family.as_lower)
			Result.append_character ('|')
			Result.append_string_general (a_weight.out)
			Result.append_character ('|')
			if a_italic then
				Result.append_character ('1')
			else
				Result.append_character ('0')
			end
			Result.append_character ('|')
			Result.append_string_general (a_pixel_size.out)
		ensure
			never_empty: not Result.is_empty
		end

feature -- Commands

	dispose_all
			-- Release every font.
			-- Phase 4: DeleteObject (HFONT), DeleteDC, release backend faces,
			-- in that order, before dropping the identities.
		do
			fonts.wipe_out
		ensure
			emptied: fonts_model.is_empty
		end

feature -- Model queries (simple_mml)

	fonts_model: MML_MAP [STRING_32, SHAPING_FONT]
			-- Identity key -> font as a mathematical map.
		local
			l_keys: ARRAY [STRING_32]
			i: INTEGER
		do
			create Result
			l_keys := fonts.current_keys
			from i := l_keys.lower until i > l_keys.upper loop
				Result := Result.updated (l_keys [i], fonts.definite_item (l_keys [i]))
				i := i + 1
			end
		end

feature {NONE} -- Implementation

	fonts: HASH_TABLE [SHAPING_FONT, STRING_32]
			-- Identity key -> the one holder.

invariant
	fonts_are_owned: across fonts as f all f.registry = Current end

end
