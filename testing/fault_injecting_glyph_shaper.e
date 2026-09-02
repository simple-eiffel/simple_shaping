note
	description: "[
		A GLYPH_SHAPER that FAILS HARD on every native shaping call - the
		fault injector AC-8 needs (Phase 4 Task 12).

		WHY IT DESCENDS FROM DIRECTWRITE_GLYPH_SHAPER RATHER THAN FROM THE
		SEAM. SIMPLE_SHAPING emits `Note_backend_error_recovered' only when
		an OBJECT TEST on DIRECTWRITE_GLYPH_SHAPER succeeds and that shaper's
		`last_shape_was_synthesized' is True (the facade's `append_item_runs',
		Task 11). A double written straight onto GLYPH_SHAPER would therefore
		produce tofu that the facade could not RECOGNIZE as tofu, and AC-8's
		"the degradations are enumerated in `notes'" would be untestable. So
		this class inherits the real backend class and injects the fault at
		the one step that talks to the native surface.

		THE MECHANISM, and why it is the honest one. `shape' - contracts and
		body alike - is inherited UNCHANGED and never redefined. It asks
		`shaped_over_backend' for real glyphs and, on Void, answers with
		`synthesized_tofu' and sets `last_shape_was_synthesized'. This class
		redefines ONLY `shaped_over_backend', to count the attempt and answer
		Void - exactly what the production class does when GetGlyphs refuses,
		when the cluster map comes back in an order no measurement covers, or
		when the DLL is gone. Nothing is faked downstream: the tofu the tests
		see is the SHIPPING R3 synthesis, produced by the shipping code path,
		and the note the facade emits is the shipping note.

		The inherited postcondition (`Result' attached implies a cluster per
		character and the font recorded) holds vacuously on Void, so no
		contract is weakened to make the double possible. The inherited
		PREcondition is kept as-is: `shape' only reaches this feature when
		the font has a backend face and the surface is open, which is exactly
		when a real shaping call would have been made and refused.

		Testing-cluster class: ships with the repo, never with a consumer.
	]"
	author: "Larry Rix"

class
	FAULT_INJECTING_GLYPH_SHAPER

inherit
	DIRECTWRITE_GLYPH_SHAPER
		redefine
			shaped_over_backend
		end

create
	make

feature -- Access

	native_attempts: INTEGER
			-- How many times a real shaping call was reached and refused.
			--
			-- Zero is a MEANINGFUL answer, not a broken double: on a machine
			-- with no live DirectWrite the font realizes without an
			-- IDWriteFontFace, `shape' never gets as far as this feature, and
			-- it degrades to the very same R3 tofu one step earlier. The
			-- tests print this number so the evidence says which of the two
			-- roads to R3 was walked.

feature {NONE} -- Implementation: the injected fault

	shaped_over_backend (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
			a_font: SHAPING_FONT): detachable SHAPED_ITEM
			-- <Precursor>
			-- ALWAYS Void: every native shaping call fails hard, so every
			-- item comes back through `synthesized_tofu' with
			-- `last_shape_was_synthesized' set.
		do
			native_attempts := native_attempts + 1
			Result := Void
		ensure then
			always_refused: Result = Void
			attempt_counted: native_attempts = old native_attempts + 1
		end

end
