note
	description: "[
		SCOOP consumer compatibility test (Phase-1 mandatory gate): a
		SCOOP-enabled consumer must be able to declare and use the library's
		main types without VUAR(2) conformance errors. The ECF compiles with
		concurrency support=scoop, so type-checking this class IS the test.

		Confinement discipline on display (DR-012): everything is created and
		used on the one calling processor; nothing separate.
	]"
	author: "Larry Rix"

class
	TEST_SCOOP_CONSUMER

feature -- Test

	test_scoop_compatibility
			-- Verify library types work in a SCOOP-compiled context.
		local
			l_shaping: SIMPLE_SHAPING
			l_fonts: FONT_LIST
			l_layout: SHAPED_LAYOUT
			l_null_bidi: NULL_BIDI_RESOLVER
			l_null_itemizer: NULL_SCRIPT_ITEMIZER
			l_null_shaper: NULL_GLYPH_SHAPER
			l_null_fallback: NULL_FONT_FALLBACK
			l_injected: SIMPLE_SHAPING
		do
			create l_shaping.make ({STRING_32} "assets")
			create l_fonts.make_default
			l_layout := l_shaping.layout ({STRING_32} "abc", 100, 16, l_fonts)
			check layout_paintable: l_layout.covers_all_characters end
			create l_null_bidi
			create l_null_itemizer
			create l_null_shaper
			create l_null_fallback
			create l_injected.make_with_backends (l_null_bidi, l_null_itemizer,
				l_null_shaper, l_null_fallback, {STRING_32} "assets")
			l_layout := l_injected.layout_default ({STRING_32} "headless", 200, 14)
			check headless_paintable: l_layout.covers_all_characters end
		end

end
