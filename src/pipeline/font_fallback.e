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

		R7: probe shapes are counted as statistics.fallback_probes by the
		CALLING engine, never inside effectings (doubles stay dumb); the
		probe count is disjoint from shape_calls.
	]"
	author: "Larry Rix"
	never_raises: "No exception propagates from any seam feature; failures degrade per NFR-011."

deferred class
	FONT_FALLBACK

inherit
	SHAPING_CONSTANTS

feature -- Operations

	font_for (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
			a_requested: SHAPING_FONT): FALLBACK_CHOICE
			-- The font `a_item' should render with, under the class-note
			-- policy. Style and size are PRESERVED across fallback: a
			-- fallback face is realized at the same (weight, italic,
			-- pixel_size) as `a_requested'.
		require
			item_in_text: a_item.start_index + a_item.count - 1 <= a_text.count
			font_ready: a_requested.is_ready
		deferred
		ensure
			never_void: Result /= Void
			same_pixel_size: Result.font.pixel_size = a_requested.pixel_size
			same_style: Result.font.weight = a_requested.weight
				and Result.font.is_italic = a_requested.is_italic
			no_silent_drop: Result.is_complete_coverage or Result.font = a_requested
		end

end
