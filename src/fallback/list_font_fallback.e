note
	description: "[
		G2: the library's OWN effecting of seam 4, in EVERY MVP
		configuration - a deterministic FONT_LIST walk with shaper probes
		(the Learn 'Using Font Fallback' procedure):
		  1. try `a_requested' (probe by shaping; missing_glyph_count is the
		     verdict);
		  2. on gaps, walk a_policy.families_for (script class) in order,
		     realizing candidates via `registry' at the SAME (weight, italic,
		     pixel_size) as the request (seam's same_style/same_pixel_size);
		  3. exhaustion: `a_requested' again with is_complete_coverage =
		     False (DR-010: tofu boxes + Note_fallback_exhausted upstream,
		     never a silent drop).

		NO CREATION-TIME POLICY (R11, Phase 2 / ISSUE 4): the walked list
		arrives as `font_for''s `a_policy' argument, so this class no longer
		holds a FONT_LIST at all. It used to, and that reference went stale
		the moment a consumer called `layout' with another policy or
		`set_default_fonts' with a new one - the defect ISSUE 4 named. What
		remains at creation is the probe seam and the registry, both of
		which are facade-lifetime objects by construction (DR-012).

		SCRIPT CLASS MAPPING: the walk buckets an item's CHARACTERS into
		SHAPING_CONSTANTS script classes by codepoint range (Hebrew
		U+0590-05FF etc.) - NEVER by the engine's opaque script_code
		(cross-backend rule on SCRIPT_ITEM). SHAPING_CONSTANTS.script_class_of
		is that mapping (ADDED Task 9, Larry's gate decision 5).

		Verdict cache (Phase 4): write-once per (script class, family) -
		grows monotonically, never invalidated within a facade lifetime; it
		is keyed by (script class, family) and NOT by policy identity, so it
		stays valid across per-call policies.
		R7 amended (ISSUE 7): probe shapes are REPORTED here through
		FALLBACK_CHOICE.probes_performed and COUNTED by the calling engine;
		this class never touches SHAPING_STATISTICS.

		WHAT A VERDICT RECORDS (Phase 4 Task 9, the exact semantics). One
		BOOLEAN per (script class, family): did that family cover the FIRST
		item of that class this facade asked about? True means "shaped with
		zero missing glyphs"; False means "did not" - and False is also the
		answer when the family is ABSENT ON THIS MACHINE, because a font the
		machine cannot realize as ITSELF covers nothing that can be painted.
		Absence is settled by `FONT_REGISTRY.family_exists' (R1's transient
		GetTextFaceW comparison, itself memoized), never by realizing and
		hoping: GDI substitutes a stand-in for an unknown family without
		saying so, and a substitute WOULD often shape complete - which would
		make the walk answer with a SHAPING_FONT whose `family' names a font
		nobody on this machine has.

		AN ABSENT FAMILY THEREFORE COSTS NO PROBE, and a cached verdict costs
		no probe either: `probes_performed' is the number of coverage SHAPES
		this call actually RAN, so a second identical call over a warm cache
		reports fewer - usually zero. That is the honest reading of R7's
		"how many probes it cost".

		COVERAGE IS A CLASS-WIDE VERDICT, NOT A PER-ITEM ONE (D-S05: cached
		per codepoint-range x font). Two Hebrew items with different rare
		characters share one verdict; the walk trades exactness for a bounded
		number of native shapes per facade lifetime, which is the trade D-S05
		chose and the reason the cache can be write-once.
	]"
	author: "Larry Rix"

class
	LIST_FONT_FALLBACK

inherit
	FONT_FALLBACK

create
	make

feature {NONE} -- Initialization

	make (a_probe: GLYPH_SHAPER; a_registry: FONT_REGISTRY)
			-- Probe through `a_probe', realize candidates in `a_registry'
			-- (one processor, DR-012). The policy is NOT captured here -
			-- it arrives per call as `font_for''s `a_policy' (R11).
		do
			probe := a_probe
			registry := a_registry
			create verdicts.make (8)
		ensure
			probe_kept: probe = a_probe
			registry_kept: registry = a_registry
		end

feature -- Access

	probe: GLYPH_SHAPER
			-- Coverage probes happen BY SHAPING through this seam.

	registry: FONT_REGISTRY
			-- Where candidate faces are realized (same processor).

	verdict_count: INTEGER
			-- [ADDED Phase 4 Task 9] How many (script class, family)
			-- coverage verdicts are on record. The cache is write-once, so
			-- this only ever grows - which is what `font_for''s added
			-- `verdicts_only_grow' clause states.
		do
			Result := verdicts.count
		ensure
			non_negative: Result >= 0
		end

feature -- Operations

	font_for (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
			a_requested: SHAPING_FONT; a_policy: FONT_LIST): FALLBACK_CHOICE
			-- <Precursor>
		local
			l_class, l_probes: INTEGER
			l_key: STRING_32
			l_found, l_covered: BOOLEAN
			l_families: ARRAYED_LIST [IMMUTABLE_STRING_32]
			l_candidate, l_chosen: SHAPING_FONT
		do
				-- The bucket comes from the ITEM'S CHARACTERS, never from
				-- its opaque script_code.
			l_chosen := a_requested
			l_class := script_class_of (a_text, a_item.start_index, a_item.count)

				-- Step 1: the requested font itself, probed BY SHAPING.
			l_key := verdict_key (l_class, a_requested.family)
			if verdicts.has (l_key) then
				l_found := verdicts.item (l_key)
			else
				l_found := probe.shape (a_text, a_item, a_requested).is_complete
				l_probes := l_probes + 1
				verdicts.put (l_found, l_key)
			end

				-- Step 2: the PER-CALL policy (R11), in order, realized at
				-- the request's own (weight, italic, pixel_size).
			if not l_found then
				l_families := a_policy.families_for (l_class)
				from
					l_families.start
				until
					l_families.after or l_found
				loop
					l_key := verdict_key (l_class, l_families.item)
					if verdicts.has (l_key) then
							-- Already on record: no probe, and the policy
							-- that first produced it is irrelevant.
						if verdicts.item (l_key) then
							l_candidate := registry.font (l_families.item,
								a_requested.weight, a_requested.is_italic,
								a_requested.pixel_size)
							if l_candidate.is_ready then
								l_found := True
								l_chosen := l_candidate
							end
						end
					elseif not registry.family_exists (l_families.item) then
							-- Absent on this machine: NOT covered, and no
							-- probe is spent on it (see the class note).
						verdicts.put (False, l_key)
					else
						l_candidate := registry.font (l_families.item,
							a_requested.weight, a_requested.is_italic,
							a_requested.pixel_size)
						if l_candidate.is_ready then
							l_covered := probe.shape (a_text, a_item, l_candidate).is_complete
							l_probes := l_probes + 1
							verdicts.put (l_covered, l_key)
							if l_covered then
								l_found := True
								l_chosen := l_candidate
							end
						else
							verdicts.put (False, l_key)
						end
					end
					l_families.forth
				end
			end

				-- Step 3: exhaustion keeps `a_requested' - DR-010's
				-- no-silent-drop answer - with `l_found' still False.
			create Result.make (l_chosen, l_found, l_probes)
		ensure then
			verdicts_only_grow: verdict_count >= old verdict_count
			verdict_recorded: verdict_count >= 1
			probes_bounded_by_verdicts: Result.probes_performed <= verdict_count
			rescue_comes_from_this_registry: (Result.is_complete_coverage
				and Result.font /= a_requested) implies
				Result.font.registry = registry
		end

feature {NONE} -- Implementation

	verdicts: HASH_TABLE [BOOLEAN, STRING_32]
			-- [ADDED Phase 4 Task 9] (script class, family) -> coverage
			-- verdict; write-once, never invalidated, and never keyed by
			-- policy identity. See the class note for what a verdict
			-- records and why an absent family records False.

	verdict_key (a_script_class: INTEGER; a_family: READABLE_STRING_32): STRING_32
			-- [ADDED Phase 4 Task 9] The cache key for `a_family' under
			-- `a_script_class'. Case-folded on the family because GDI's own
			-- family matching is, so "segoe ui" and "Segoe UI" must not earn
			-- two probes.
		require
			class_valid: is_valid_script_class (a_script_class)
			family_not_empty: not a_family.is_empty
		do
			create Result.make (a_family.count + 4)
			Result.append_string_general (a_script_class.out)
			Result.append_character ('|')
			Result.append_string_general (a_family.as_string_32.as_lower)
		ensure
			never_empty: not Result.is_empty
		end

end
