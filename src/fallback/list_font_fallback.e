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
		(cross-backend rule on SCRIPT_ITEM).

		Verdict cache (Phase 4): write-once per (script class, family) -
		grows monotonically, never invalidated within a facade lifetime; it
		is keyed by (script class, family) and NOT by policy identity, so it
		stays valid across per-call policies.
		R7 amended (ISSUE 7): probe shapes are REPORTED here through
		FALLBACK_CHOICE.probes_performed and COUNTED by the calling engine;
		this class never touches SHAPING_STATISTICS.

		Phase-1 body is the degenerate requested-font answer, marked for
		Phase 4.
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
		ensure
			probe_kept: probe = a_probe
			registry_kept: registry = a_registry
		end

feature -- Access

	probe: GLYPH_SHAPER
			-- Coverage probes happen BY SHAPING through this seam.

	registry: FONT_REGISTRY
			-- Where candidate faces are realized (same processor).

feature -- Operations

	font_for (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
			a_requested: SHAPING_FONT; a_policy: FONT_LIST): FALLBACK_CHOICE
			-- <Precursor>
		do
			-- Phase 4: requested-first probe via `probe'; on gaps walk
			-- a_policy.families_for (script_class_of (item characters)),
			-- realize via `registry' at a_requested's (weight, italic,
			-- pixel_size), write-once verdicts; exhaustion ->
			-- (a_requested, False). The probe TALLY travels back in the
			-- choice (R7 amended) - never into SHAPING_STATISTICS here.
			create Result.make (a_requested, True, 0)
		end

end
