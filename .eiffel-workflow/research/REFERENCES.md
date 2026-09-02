# REFERENCES: simple_shaping

Every URL below was actually searched/fetched during this research (2026-09-01).

## Documentation Consulted — Microsoft Learn

- https://learn.microsoft.com/en-us/windows/win32/intl/uniscribe — Uniscribe portal; scope of the API set (no formal deprecation note on the page itself).
- https://learn.microsoft.com/en-us/windows/win32/intl/displaying-text-with-uniscribe — the canonical pipeline: ScriptItemize → ScriptShape → ScriptPlace → ScriptLayout (uBidiLevel visual reordering) → ScriptTextOut; OpenType variants table; "Uniscribe must be used for an entire paragraph."
- https://learn.microsoft.com/en-us/windows/win32/intl/using-font-fallback — fallback is the application's job; missing-glyph scan via ScriptGetFontProperties (wgDefault); font-list retry strategies; SCRIPT_UNDEFINED.
- https://learn.microsoft.com/en-us/windows/win32/api/usp10/nf-usp10-scriptshape — WORD pwOutGlyphs (glyph ids for the HDC-selected font), pwLogClust cluster map (decreasing for RTL), USP_E_SCRIPT_NOT_IN_FONT, E_PENDING/SCRIPT_CACHE, 1.5n+16 buffer rule, Win8+ link order (Usp10.lib before gdi32.lib), api_location incl. GDI32Full.dll.
- https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritetextanalyzer-getglyphs — full signature: UINT16 glyphIndices/clusterMap out, IDWriteFontFace in, DWRITE_SCRIPT_ANALYSIS from AnalyzeScript; 3n/2+16 estimate; Win7+; dwrite.h/Dwrite.dll.
- https://learn.microsoft.com/en-us/windows/win32/api/dwrite_2/nn-dwrite_2-idwritefontfallback — MapCharacters; Win 8.1+.
- https://learn.microsoft.com/en-us/windows/win32/api/dwrite_2/nf-dwrite_2-idwritefactory2-getsystemfontfallback — system fallback access point.
- https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritegdiinterop-createfontfacefromhdc — "guaranteed to reference the same physical typeface that would be used for drawing glyphs ... using ExtTextOut" (the bridge guarantee).
- https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritegdiinterop-convertfontfacetologfont — reverse direction NOT guaranteed to the same physical font (RISK-006).
- https://learn.microsoft.com/en-us/windows/win32/directwrite/interoperating-with-gdi — GDI↔DWrite interop patterns ("GDI and Uniscribe 1.x for layout ... DirectWrite for final rendering" scenario).
- https://learn.microsoft.com/en-us/windows/win32/directwrite/color-fonts — color glyphs require TranslateColorGlyphRun + D2D/DWrite drawing (DrawColorBitmapGlyphRun/DrawSvgGlyphRun).
- https://learn.microsoft.com/en-us/uwp/api/windows.ui.xaml.documents.glyphs.iscolorfontenabled — "GDI does not support color fonts."
- https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-getcharacterplacementw — GetCharacterPlacement "rendered it obsolete ... superseded by the functionality of the Uniscribe module."
- https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-exttextoutw — ETO_GLYPH_INDEX semantics ("all language processing has been completed").
- https://learn.microsoft.com/en-us/windows/win32/directwrite/getting-started-with-directwrite — factory creation basics.
- https://learn.microsoft.com/en-us/globalization/fonts-layout/font-support — Windows script/font support overview (DirectWrite positioning).

## Documentation Consulted — cairo

- https://www.cairographics.org/manual-1.17.2/cairo-Win32-Fonts.html — the three face constructors; LOGFONT lfHeight/lfWidth/lfOrientation/lfEscapement "are ignored" (size via font matrix).
- https://www.cairographics.org/manual-1.17.2/cairo-text.html — cairo_glyph_t.index = "glyph index in the font. The exact interpretation ... depends on the font technology being used"; toy-API warning.
- https://www.cairographics.org/news/cairo-1.17.8/ — COLRv1/color-font support arrived AFTER 1.17.2 (FreeType side).
- https://www.cairographics.org/news/cairo-1.18.0/ — 1.18 color-font consolidation.
- https://github.com/mozilla/gecko-dev/blob/master/gfx/cairo/cairo/src/cairo-win32-font.c — `_flush_glyphs` → `ExtTextOutW(..., ETO_GLYPH_INDEX, ...)` (also mirrored at https://github.com/servo/cairo/blob/master/src/win32/cairo-win32-font.c).
- https://discourse.gnome.org/t/are-color-glyphs-only-supported-by-the-freetype2-backend/15995 — CAIRO_FONT_TYPE_WIN32 draws Segoe UI Emoji as monochrome outlines; color only via FT backend.

## Repositories / Libraries Examined

- https://github.com/harfbuzz/harfbuzz + https://github.com/harfbuzz/harfbuzz/releases/tag/7.0.0 — HarfBuzz ("Old MIT"); 7.0 added hb-cairo.
- https://harfbuzz.github.io/integration-cairo.html — "use hb_cairo_glyphs_from_buffer() to obtain the glyphs in a form that can be passed to ... cairo_show_glyphs()" (the pattern precedent).
- https://github.com/Tehreer/SheenBidi — Apache-2.0 UAX #9 implementation in C (thread-safe, stdlib-only).
- https://github.com/harfbuzz/rustybuzz — complete Rust port of HarfBuzz shaping; scale evidence for the "GLYPH_SHAPER long pole" judgment (1.5–2x slower; shaping-only scope).
- https://github.com/pop-os/cosmic-text — Rust text stack without Pango: shaping (HarfRust), custom bidi layout, custom static-list font fallback, swash raster.
- https://github.com/jdecked/twemoji — Twemoji maintained fork; code MIT, "Graphics licensed under CC-BY 4.0"; 72x72 PNGs, codepoint filenames.
- https://github.com/googlefonts/noto-emoji — Noto Emoji; "Tools and most image resources are under the Apache license, version 2.0"; fonts OFL 1.1; `png/128/emoji_u1f916.png` naming.

## Unicode Standards and Data

- https://www.unicode.org/reports/tr9/ — UAX #9, the Bidirectional Algorithm.
- https://unicode-org.github.io/unicode-reports/tr51/tr51.html — UTS #51 Unicode Emoji: VS16, ZWJ sequences, RGI; data files emoji-zwj-sequences.txt / emoji-test.txt.
- https://www.unicode.org/Public/PROGRAMS/BidiReferenceC/12.0.0/ReadMe.txt — C reference implementation; BidiTest.txt/BidiCharacterTest.txt as the conformance oracles.
- https://deepwiki.com/servo/unicode-bidi/7.1-conformance-testing — BidiTest.txt scale (513,494 cases) as used by a production implementation (third-party count; the files themselves are the authority).

## Articles / Discussions

- https://en.wikipedia.org/wiki/Uniscribe — history; DirectWrite as intended replacement; maintained as of 2021; ships in current Windows.
- https://en.wikipedia.org/wiki/Pango + https://fossies.org/linux/pango/NEWS — Pango 1.31.0 moved to HarfBuzz, dropping native per-script modules (itemization/shaping split precedent).
- https://devblogs.microsoft.com/oldnewthing/20040205-00/?p=40733 — COM object layout (lpVtbl) for the from-C (hence from-Eiffel-glue) binding cost assessment.
- https://learn.microsoft.com/en-us/answers/questions/1538645/how-to-know-which-font-gdi-use-when-a-font-doesnt — GDI-level fallback opacity (why fallback must be explicit).

## Local Evidence (D:\prod)

- D:\prod\cairo-windows-1.17.2\include\cairo-features.h — `CAIRO_HAS_WIN32_FONT 1`, `CAIRO_HAS_FT_FONT 1`, no DWrite backend; cairo-version.h = 1.17.2.
- D:\prod\cairo-windows-1.17.2\include\cairo-win32.h lines 82/88 — `cairo_win32_font_face_create_for_logfontw` / `_for_logfontw_hfont` present as shipped.
- D:\prod\simple_cairo\ — wrapper exists; Clib ships cairo-win32.h; src/cairo_context.e has NO glyph-level API yet (D-S07).
- D:\prod\simple_widgets\src\sw_painter.e:74 — toy `show_text` is the current text path; src/sw_chat_thread.e:192 — greedy wrap to be replaced.
- D:\prod\simple_chat\.eiffel-workflow\research\04-DECISIONS.md — D-014 (four seams), D-015 (thick client + acceptance string), D-019 (emoji-as-pictures proposal), D-020 (WIC).
- Ecosystem greps — full D:\prod tree (*.e/*.ecf) plus targeted src greps (simple_widgets/simple_cairo/simple_speech/simple_vision/simple_clipboard/simple_chat/simple_reel/simple_scholar; gobo-26.06/library/string) — zero existing usp10/dwrite/bidi code; sole matches were SQLITE_OPEN_READWRITE substring false positives in eiffel_sqlite_2025.
- https://dev.eiffel.com/Unicode_Free_Operator — the only Eiffel-adjacent bidi mention found publicly (lexical control characters, not shaping).
