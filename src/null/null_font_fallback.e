note
	description: "[
		Headless test double for seam 4 (UC-005/AC-7): always the requested
		font, always claimed complete - fallback logic disappears from the
		picture so layout tests isolate wrap/measurement behavior.

		WEAKENED require (lawful for a double): the font need not be
		realized (headless).
	]"
	author: "Larry Rix"

class
	NULL_FONT_FALLBACK

inherit
	FONT_FALLBACK

feature -- Operations

	font_for (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
			a_requested: SHAPING_FONT): FALLBACK_CHOICE
			-- <Precursor>
		require else
			headless_fonts_allowed: a_item.start_index + a_item.count - 1 <= a_text.count
		do
			create Result.make (a_requested, True)
		ensure then
			requested_kept: Result.font = a_requested
			complete_claimed: Result.is_complete_coverage
		end

end
