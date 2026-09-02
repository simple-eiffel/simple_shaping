note
	description: "[
		Seam 4 of four (C-006/D-014): pick the rendering font for one item.

		G2: LIST_FONT_FALLBACK - the library's own configured FONT_LIST walk
		with shaper probes - is the effecting in EVERY MVP configuration.
		DIRECTWRITE_FONT_FALLBACK (IDWriteFontFallback-based) is a named-only
		future slot; NULL_ is the headless double.

		DR-010 (no silent drops): the answer is `a_requested' if it covers
		the item, else the first covering font from the configured policy,
		else `a_requested' AGAIN with is_complete_coverage = False - the item
		then renders as the requested font's missing-glyph boxes plus a
		Note_fallback_exhausted upstream. Something ALWAYS renders.

		PER-CALL POLICY (R11, Phase 2 / ISSUE 4): `font_for' takes the
		FONT_LIST to walk as an ARGUMENT. It used to have none, so
		LIST_FONT_FALLBACK walked the list captured when the facade was
		created - forever: `layout (text, w, n, my_fonts)' claimed a layout
		"under policy my_fonts" and keyed the cache by its digest while the
		fallback walk ignored it, and `set_default_fonts' left the fallback
		pointing at a list the consumer no longer held. The policy now
		travels with the call, so AC-4's "first covering FONT_LIST font"
		names the list the caller actually passed.

		R7 AMENDED (Phase 2 / ISSUE 7): probe shapes are counted as
		statistics.fallback_probes by the CALLING engine FROM
		FALLBACK_CHOICE.probes_performed; never inside seam doubles. Only
		the walk knows how many probes it ran, so the value rides home on
		the choice - the seam stays pure, doubles simply return 0, and the
		probe count remains disjoint from shape_calls.
	]"
	author: "Larry Rix"
	never_raises: "No exception propagates from any seam feature; failures degrade per NFR-011."

deferred class
	FONT_FALLBACK

inherit
	SHAPING_CONSTANTS

feature -- Operations

	font_for (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
			a_requested: SHAPING_FONT; a_policy: FONT_LIST): FALLBACK_CHOICE
			-- The font `a_item' should render with, walking `a_policy'
			-- (R11: the CALLER's per-call policy, not a captured one).
			-- Style and size are PRESERVED across fallback: a fallback face
			-- is realized at the same (weight, italic, pixel_size) as
			-- `a_requested'. The answer also reports how many coverage
			-- probes it cost (R7 amended).
		require
			item_in_text: a_item.start_index + a_item.count - 1 <= a_text.count
			font_ready: a_requested.is_ready
			policy_usable: not a_policy.is_empty
		deferred
		ensure
			never_void: Result /= Void
			same_pixel_size: Result.font.pixel_size = a_requested.pixel_size
			same_style: Result.font.weight = a_requested.weight
				and Result.font.is_italic = a_requested.is_italic
			no_silent_drop: Result.is_complete_coverage or Result.font = a_requested
			probes_counted: Result.probes_performed >= 0
		end

end
