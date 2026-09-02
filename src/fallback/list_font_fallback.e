note
	description: "[
		G2: the library's OWN effecting of seam 4, in EVERY MVP
		configuration - a deterministic FONT_LIST walk with shaper probes
		(the Learn 'Using Font Fallback' procedure):
		  1. try `a_requested' (probe by shaping; missing_glyph_count is the
		     verdict);
		  2. on gaps, walk fonts.families_for (script class) in order,
		     realizing candidates via `registry' at the SAME (weight, italic,
		     pixel_size) as the request (seam's same_style/same_pixel_size);
		  3. exhaustion: `a_requested' again with is_complete_coverage =
		     False (DR-010: tofu boxes + Note_fallback_exhausted upstream,
		     never a silent drop).

		SCRIPT CLASS MAPPING: the walk buckets an item's CHARACTERS into
		SHAPING_CONSTANTS script classes by codepoint range (Hebrew
		U+0590-05FF etc.) - NEVER by the engine's opaque script_code
		(cross-backend rule on SCRIPT_ITEM).

		Verdict cache (Phase 4): write-once per (script class, family) -
		grows monotonically, never invalidated within a facade lifetime.
		R7: probe shapes are counted as fallback_probes by the CALLING
		engine, not here.

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

	make (a_fonts: FONT_LIST; a_probe: GLYPH_SHAPER; a_registry: FONT_REGISTRY)
			-- Fallback policy `a_fonts', probing through `a_probe',
			-- realizing candidates in `a_registry' (one processor, DR-012).
		require
			fonts_usable: not a_fonts.is_empty
		do
			fonts := a_fonts
			probe := a_probe
			registry := a_registry
		ensure
			policy_kept: fonts = a_fonts
			probe_kept: probe = a_probe
			registry_kept: registry = a_registry
		end

feature -- Access

	fonts: FONT_LIST
			-- The configured policy (G2).

	probe: GLYPH_SHAPER
			-- Coverage probes happen BY SHAPING through this seam.

	registry: FONT_REGISTRY
			-- Where candidate faces are realized (same processor).

feature -- Operations

	font_for (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
			a_requested: SHAPING_FONT): FALLBACK_CHOICE
			-- <Precursor>
		do
			-- Phase 4: requested-first probe via `probe'; on gaps walk
			-- fonts.families_for (script_class_of (item characters)),
			-- realize via `registry' at a_requested's (weight, italic,
			-- pixel_size), write-once verdicts; exhaustion ->
			-- (a_requested, False).
			create Result.make (a_requested, True)
		end

invariant
	policy_usable: not fonts.is_empty

end
