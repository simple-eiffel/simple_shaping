note
	description: "[
		Ordered fallback font policy (G2): general ordered family names plus
		per-script-class prepend lists. Value-comparable; the cache-key digest
		is VALUE-based so equal configurations share cache entries (FR-N03).

		R1 (Q1): make_default builds the CONFIGURED list. The existence probe
		runs at REALIZATION - LIVE as of Phase 4 Task 2, in
		FONT_REGISTRY.family_exists (a transient GDI realization compared
		against GetTextFaceW, because GDI substitutes silently) and
		SIMPLE_SHAPING.effective_policy: absent families are dropped from the
		EFFECTIVE list with one Note_family_missing per family per facade
		lifetime.

		R5 (Q7) IS LIVE TOO, AND THIS CLASS IS NOT WHERE IT LANDED. `digest'
		here is and stays the CONFIGURED digest - a FONT_LIST is a value and
		knows nothing about a machine. The post-probe EFFECTIVE digest is
		SIMPLE_SHAPING.effective_digest: the facade builds an effective
		FONT_LIST out of the surviving families and takes ITS `digest', then
		memoizes the answer per configured digest (gate decision 3), because
		`cache_key' is evaluated inside `layout''s postconditions. So R5 is
		"the facade digests an effective FONT_LIST", never "FONT_LIST.digest
		changes meaning" - which is what keeps this class a pure value and
		keeps `is_equal' honest.

		G2 determinism is POLICY determinism: same list, same probe order,
		same decision procedure on every machine. Pixel-identical TEXT across
		machines is out of scope (only emoji are pixel-identical, G3).

		Immutable-after-configuration: build with the fluent with_* features,
		then hand to the facade and stop mutating (A-C05). The facade does
		NOT trust that: `make'/`set_default_fonts' take a defensive `twin'
		(Phase 2, ISSUE 14), which is why `copy' below is deep.

		VALUE SEMANTICS ARE TWO FEATURES, NOT ONE (Phase 2, ISSUE 3 - the
		simple_chat D5 lesson): `is_equal' is redefined as digest equality,
		so `copy' MUST be redefined too. ANY's field copy would alias
		`general_families' and `script_prepends', and `list.twin.with_family
		(...)' would then silently mutate the ORIGINAL policy - the facade's
		defaults, the fallback's walk, and every future cache key with it.
	]"
	author: "Larry Rix"

class
	FONT_LIST

inherit
	SHAPING_CONSTANTS
		undefine
			is_equal, copy
		end

	ANY
		redefine
			is_equal, copy
		end

create
	make_default, make_empty

feature {NONE} -- Initialization

	make_default
			-- The R1 default: guaranteed Win10/11 anchors in the general list;
			-- scholar-grade Hebrew faces first in the hebrew class (probed at
			-- realization); Greek polytonic-capable faces for the greek class.
			-- Consumers prepend their theme face themselves (Q1: the theme
			-- face is theme-owned and Latin-only, not library-known).
		do
			make_empty
			append_general ("Segoe UI")
			append_general ("Arial")
			append_general ("Tahoma")
			prepend_for_script (Script_class_hebrew, "David")
			prepend_for_script (Script_class_hebrew, "David Libre")
			prepend_for_script (Script_class_hebrew, "Noto Sans Hebrew")
			prepend_for_script (Script_class_hebrew, "Ezra SIL")
			prepend_for_script (Script_class_hebrew, "SBL Hebrew")
			prepend_for_script (Script_class_greek, "Times New Roman")
			prepend_for_script (Script_class_greek, "Palatino Linotype")
			prepend_for_script (Script_class_greek, "Segoe UI")
		ensure
			usable: not is_empty
			anchored: general_count >= 3
		end

	make_empty
			-- Start from scratch (facade preconditions demand non-empty lists in use).
		do
			create general_families.make (4)
			create script_prepends.make (5)
		ensure
			empty: is_empty
		end

feature -- Access

	general_count: INTEGER
			-- Families in the general list.
		do
			Result := general_families.count
		ensure
			non_negative: Result >= 0
		end

	families_for (a_script_class: INTEGER): ARRAYED_LIST [IMMUTABLE_STRING_32]
			-- What fallback will probe for `a_script_class', in order:
			-- the class prepends, then the general list. Duplicates are kept
			-- (the probe cache dedupes verdicts, not the policy).
		require
			class_valid: is_valid_script_class (a_script_class)
		do
			create Result.make (general_families.count + 4)
			if attached script_prepends.item (a_script_class) as al_prepends then
				across al_prepends as f loop
					Result.extend (f)
				end
			end
			across general_families as f loop
				Result.extend (f)
			end
		ensure
			never_void: Result /= Void
			general_included: Result.count >= general_count
			composition: Result.count = general_count
				+ (if script_families_model.domain [a_script_class]
				then script_families_model [a_script_class].count else 0 end)
		end

	digest: STRING_8
			-- VALUE-based cache-key part (FR-N03): a deterministic UTF-8
			-- serialization of the whole policy. Equal lists yield equal
			-- digests BY CONSTRUCTION.
			--
			-- LENGTH-PREFIXED, THEREFORE INJECTIVE (Phase 2, ISSUE 2): every
			-- family name is emitted as `byte count' + ':' + UTF-8 bytes, and
			-- every list as `element count' + ';' before its elements. Family
			-- names are arbitrary non-empty strings and MAY contain ';', '|'
			-- and ':'; with bare separators ["A;B"] and ["A","B"] serialized
			-- identically, so `is_equal' equated different policies and two
			-- policies could share a cache key. A length prefix cannot be
			-- forged by content, so distinct policies now always differ here.
		local
			l_class: INTEGER
			l_utf: UTF_CONVERTER
			l_bytes: STRING_8
		do
			create Result.make (64)
			Result.append ("g:")
			Result.append_integer (general_families.count)
			Result.append_character (';')
			across general_families as f loop
				l_bytes := l_utf.utf_32_string_to_utf_8_string_8 (f)
				Result.append_integer (l_bytes.count)
				Result.append_character (':')
				Result.append (l_bytes)
			end
			from l_class := Script_class_hebrew until l_class > Script_class_other loop
				Result.append_character ('|')
				Result.append_integer (l_class)
				Result.append_character (':')
				if attached script_prepends.item (l_class) as al_prepends then
					Result.append_integer (al_prepends.count)
					Result.append_character (';')
					across al_prepends as f loop
						l_bytes := l_utf.utf_32_string_to_utf_8_string_8 (f)
						Result.append_integer (l_bytes.count)
						Result.append_character (':')
						Result.append (l_bytes)
					end
				else
					Result.append_integer (0)
					Result.append_character (';')
				end
				l_class := l_class + 1
			end
		ensure
			never_empty: not Result.is_empty
		end

feature -- Status

	is_empty: BOOLEAN
			-- No families configured anywhere?
		do
			Result := general_families.is_empty
			if Result then
				across script_prepends as p loop
					Result := Result and p.is_empty
				end
			end
		end

feature -- Configuration (fluent, immutable-after-configuration)

	with_family (a_name: READABLE_STRING_32): like Current
			-- Append `a_name' to the general list.
		require
			name_not_empty: not a_name.is_empty
		do
			append_general (a_name)
			Result := Current
		ensure
			chaining: Result = Current
			appended: general_count = old general_count + 1
			at_end: families_model [general_count].same_string_general (a_name)
			prefix_kept: families_model.front (old general_count) |=| old families_model
			scripts_untouched: script_families_model |=| old script_families_model
		end

	with_family_for_script (a_script_class: INTEGER; a_name: READABLE_STRING_32): like Current
			-- Prepend `a_name' for `a_script_class' (highest priority for that class).
		require
			class_valid: is_valid_script_class (a_script_class)
			name_not_empty: not a_name.is_empty
		do
			prepend_for_script (a_script_class, a_name)
			Result := Current
		ensure
			chaining: Result = Current
			prepended_first: families_for (a_script_class).first.same_string_general (a_name)
			general_untouched: families_model |=| old families_model
			class_present: script_families_model.domain [a_script_class]
			class_grew_by_one: script_families_model [a_script_class].count =
				(if old script_families_model.domain [a_script_class]
				then (old script_families_model) [a_script_class].count + 1 else 1 end)
			rest_of_class_kept: (old script_families_model.domain [a_script_class]) implies
				script_families_model [a_script_class].but_first |=| (old script_families_model) [a_script_class]
			other_classes_kept: script_families_model.removed (a_script_class) |=|
				(old script_families_model).removed (a_script_class)
		end

feature -- Comparison

	is_equal (other: like Current): BOOLEAN
			-- Value equality: same policy, position by position (FR-N03).
		do
			Result := digest.same_string (other.digest)
		end

	copy (other: like Current)
			-- Re-initialize from `other', DEEP over both collections
			-- (Phase 2, ISSUE 3): fresh ARRAYED_LISTs and a fresh HASH_TABLE
			-- of fresh inner lists, so a twin can be mutated without
			-- touching the original. IMMUTABLE_STRING_32 elements are
			-- shared on purpose - they cannot be mutated.
		local
			l_class: INTEGER
			l_copy: ARRAYED_LIST [IMMUTABLE_STRING_32]
		do
			if other /= Current then
				-- Self-copy guard (EiffelBase's ARRAYED_LIST.copy has the same):
				-- without it, reassigning `general_families' first and then
				-- iterating `other.general_families' would iterate the NEW
				-- empty list and wipe Current.
				create general_families.make (other.general_count.max (4))
				across other.general_families as f loop
					general_families.extend (f)
				end
				create script_prepends.make (5)
				from l_class := Script_class_hebrew until l_class > Script_class_other loop
					if attached other.script_prepends.item (l_class) as al_source then
						create l_copy.make (al_source.count.max (1))
						across al_source as f loop
							l_copy.extend (f)
						end
						script_prepends.put (l_copy, l_class)
					end
					l_class := l_class + 1
				end
			end
		ensure then
			lists_not_shared: other /= Current implies
				(general_families /= other.general_families
				and script_prepends /= other.script_prepends)
		end

feature -- Model queries (simple_mml)

	families_model: MML_SEQUENCE [IMMUTABLE_STRING_32]
			-- The general list as a mathematical sequence.
		do
			create Result
			across general_families as f loop
				Result := Result & f
			end
		ensure
			same_count: Result.count = general_count
		end

	script_families_model: MML_MAP [INTEGER, MML_SEQUENCE [IMMUTABLE_STRING_32]]
			-- Per-script-class prepends as a mathematical map.
		local
			l_class: INTEGER
			l_seq: MML_SEQUENCE [IMMUTABLE_STRING_32]
		do
			create Result
			from l_class := Script_class_hebrew until l_class > Script_class_other loop
				if attached script_prepends.item (l_class) as al_prepends then
					create l_seq
					across al_prepends as f loop
						l_seq := l_seq & f
					end
					Result := Result.updated (l_class, l_seq)
				end
				l_class := l_class + 1
			end
		end

feature {FONT_LIST} -- Implementation (peer access for `copy')

	general_families: ARRAYED_LIST [IMMUTABLE_STRING_32]
			-- Ordered general fallback families.

	script_prepends: HASH_TABLE [ARRAYED_LIST [IMMUTABLE_STRING_32], INTEGER]
			-- Script class -> prepend families (first = highest priority).

feature {NONE} -- Implementation

	append_general (a_name: READABLE_STRING_GENERAL)
			-- Append `a_name' to `general_families'.
		require
			name_not_empty: not a_name.is_empty
		local
			l_name: IMMUTABLE_STRING_32
		do
			create l_name.make_from_string_general (a_name)
			general_families.extend (l_name)
		ensure
			appended: general_families.count = old general_families.count + 1
			at_end: general_families.last.same_string_general (a_name)
			scripts_untouched: script_families_model |=| old script_families_model
		end

	prepend_for_script (a_script_class: INTEGER; a_name: READABLE_STRING_GENERAL)
			-- Prepend `a_name' to `a_script_class''s list.
		require
			class_valid: is_valid_script_class (a_script_class)
			name_not_empty: not a_name.is_empty
		local
			l_name: IMMUTABLE_STRING_32
			l_list: ARRAYED_LIST [IMMUTABLE_STRING_32]
		do
			create l_name.make_from_string_general (a_name)
			if attached script_prepends.item (a_script_class) as al_list then
				l_list := al_list
			else
				create l_list.make (4)
				script_prepends.put (l_list, a_script_class)
			end
			l_list.put_front (l_name)
		ensure
			class_present: script_prepends.has (a_script_class)
			first_is_name: attached script_prepends.item (a_script_class) as al_head
				and then al_head.first.same_string_general (a_name)
			general_untouched: families_model |=| old families_model
		end

invariant
	general_attached: general_families /= Void
	prepends_attached: script_prepends /= Void
	model_count_consistent: families_model.count = general_count

note
	digest_is_value_based: "(Current ~ other) implies (digest ~ other.digest) - by construction: is_equal IS digest equality (FR-N03; tested, not asserted)."
	digest_is_injective: "[
		Phase 2, ISSUE 2 - the previous note here claimed "a serialization
		cannot collide two different lists", which was FALSE while the
		separators were bare: family names may contain ';', '|' and ':'.
		Injectivity is now EARNED by length prefixes (see `digest'), not
		assumed: distinct configurations serialize to distinct byte strings,
		so `is_equal' cannot equate different policies and SIMPLE_SHAPING's
		cache key cannot serve a layout computed under another policy.
	]"
	copy_is_deep: "[
		`copy' is redefined alongside `is_equal' (ISSUE 3). Anything that
		hands a FONT_LIST across an ownership boundary should `twin' it;
		the facade does.
	]"

end
