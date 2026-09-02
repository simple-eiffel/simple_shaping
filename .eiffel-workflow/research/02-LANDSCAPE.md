# LANDSCAPE: simple_shaping

All claims below are from fetched documentation (URLs inline; full list in REFERENCES.md) or from files verified locally at D:\prod.

## The cairo bridge (the KNOWN HARD FACT, confirmed and sharpened)

- The cairo 1.17.2 DLL simple_widgets ships has `CAIRO_HAS_WIN32_FONT 1`, `CAIRO_HAS_FT_FONT 1`, and **no DirectWrite font backend** — verified in the local header D:\prod\cairo-windows-1.17.2\include\cairo-features.h. (cairo's DWrite font backend arrived later; the 1.17.2 manual lists only the win32/FT/user backends: https://www.cairographics.org/manual-1.17.2/cairo-Win32-Fonts.html)
- `cairo_win32_font_face_create_for_logfontw (LOGFONTW*)` and `..._for_logfontw_hfont (LOGFONTW*, HFONT)` exist in the shipped header (D:\prod\cairo-windows-1.17.2\include\cairo-win32.h lines 82/88 — locally verified). Manual note: LOGFONT's `lfHeight, lfWidth, lfOrientation, lfEscapement` "are ignored" — **cairo controls size via the font matrix**, so the shaper must shape/place at pixel size N and the cairo side must `set_font_size (N)` on the same face for rasterization to match the shaper's positions.
- `cairo_glyph_t.index` is defined as "glyph index in the font. The exact interpretation of the glyph index depends on the font technology being used" (https://www.cairographics.org/manual-1.17.2/cairo-text.html).
- cairo's win32 font backend renders glyph arrays by calling **`ExtTextOutW` with `ETO_GLYPH_INDEX`** (`_flush_glyphs` in cairo-win32-font.c; source mirror: https://github.com/mozilla/gecko-dev/blob/master/gfx/cairo/cairo/src/cairo-win32-font.c). ETO_GLYPH_INDEX means GDI treats the values as **physical font glyph indices** with "all language processing ... completed" (https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-exttextoutw).
- Closing the loop from the shaper side: `IDWriteGdiInterop::CreateFontFaceFromHdc` "creates an IDWriteFontFace object that corresponds to the currently selected HFONT of the specified HDC. The font face returned is guaranteed to reference the same physical typeface that would be used for drawing glyphs (but not necessarily characters) using ExtTextOut" (https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritegdiinterop-createfontfacefromhdc). Uniscribe's `ScriptShape` shapes against the HFONT selected in the HDC directly, so its `WORD pwOutGlyphs` are that same font's glyph ids by construction (https://learn.microsoft.com/en-us/windows/win32/api/usp10/nf-usp10-scriptshape).

**Verdict: the bridge is VIABLE.** Shaper (Uniscribe or DirectWrite) produces font glyph indices + positions for an HFONT; cairo draws them through a win32 font face created from the same LOGFONTW/HFONT via `cairo_show_glyphs`. One HFONT/face per run; per-run face switching is how fallback fonts render. Limits: monochrome only (next section); positions must be computed at the same pixel size on both sides.

## Color emoji (decides D-019)

| Fact | Source |
|------|--------|
| "GDI does not support color fonts. DirectWrite is recommended" | https://learn.microsoft.com/en-us/uwp/api/windows.ui.xaml.documents.glyphs.iscolorfontenabled |
| "Color glyphs cannot be rendered using the Windows font backend (CAIRO_FONT_TYPE_WIN32) ... 'Segoe UI Emoji' emojis are drawn as black & white outlines"; FT backend is the one with color support | https://discourse.gnome.org/t/are-color-glyphs-only-supported-by-the-freetype2-backend/15995 |
| cairo's COLRv1/color-font work landed in 1.17.8/1.18 — **after** the shipped 1.17.2 — and on the FreeType side | https://www.cairographics.org/news/cairo-1.17.8/ ; https://www.cairographics.org/news/cairo-1.18.0/ |
| DirectWrite color emoji requires `TranslateColorGlyphRun` + Direct2D/DWrite bitmap targets to draw the color runs — a rendering path, not a glyph-index array | https://learn.microsoft.com/en-us/windows/win32/directwrite/color-fonts |

**Verdict: color emoji is a dead end on every "shaper → cairo_show_glyphs → cairo-win32" path, with either shaper.** Emoji through the glyph pipeline can only be Segoe UI Emoji's monochrome outlines. D-019's inline-PNG proposal is therefore the only way to get color emoji at all here — and it also gives the wanted property that 🤖 is pixel-identical on every machine. Asset options verified:

| Asset set | License | Format | Naming |
|-----------|---------|--------|--------|
| Noto Emoji (googlefonts/noto-emoji) | "Tools and most image resources are under the Apache license, version 2.0" (fonts are OFL 1.1 — not needed) | PNG, `png/128/` etc. | `emoji_u1f916.png` (🤖 = U+1F916) — https://github.com/googlefonts/noto-emoji |
| Twemoji (jdecked/twemoji, maintained fork) | Code MIT; "Graphics licensed under CC-BY 4.0" (attribution required) | PNG 72x72 (SVG available) | codepoint filenames, e.g. `2764.png` — https://github.com/jdecked/twemoji |

Emoji-sequence detection (what counts as one emoji): UTS #51 defines emoji ZWJ sequences and VS16 (U+FE0F) presentation; machine-readable data ships as `emoji-zwj-sequences.txt` / `emoji-test.txt` (RGI set) — https://unicode-org.github.io/unicode-reports/tr51/tr51.html.

## Existing Solutions (the backend candidates)

### Solution 1: Uniscribe (usp10)
| Aspect | Assessment |
|--------|------------|
| Type | OS API (flat C, exported from usp10.dll) |
| Platform | Every Windows since 2000; still ships in Windows 10/11 |
| URL | https://learn.microsoft.com/en-us/windows/win32/intl/uniscribe |
| Maturity | MATURE (frozen; Wikipedia: maintained as of 2021, DirectWrite is the intended replacement — https://en.wikipedia.org/wiki/Uniscribe) |
| License | None needed (OS component) |

Pipeline (per https://learn.microsoft.com/en-us/windows/win32/intl/displaying-text-with-uniscribe): `ScriptItemize` (items by script + direction, with bidi embedding levels in `SCRIPT_STATE.uBidiLevel`) → `ScriptShape` (clusters + `WORD` glyph indices + cluster map, per HDC-selected HFONT) → `ScriptPlace` (advances + x,y offsets) → `ScriptLayout` (visual reordering from the levels array) → normally `ScriptTextOut`, which we replace with `cairo_show_glyphs`.

**Strengths:** covers three of the four seams with a flat C API — no COM, no DLLs to ship, trivially bindable as Eiffel externals; shapes directly against HFONTs (no font-realization gap with the cairo face); `USP_E_SCRIPT_NOT_IN_FONT` + missing-glyph scan give exactly the probe FONT_FALLBACK needs (https://learn.microsoft.com/en-us/windows/win32/intl/using-font-fallback); `ScriptBreak` supplies wrap points, `ScriptCPtoX`/`ScriptXtoCP` supply future hit-testing.
**Weaknesses:** font fallback is explicitly the application's job ("the application must assign a fallback font" — Using Font Fallback, ibid.); frozen — new Unicode scripts/emoji sequence shaping won't improve (Hebrew/Greek/Latin are unaffected); no color output (moot: see above); docs note Win8+ link order (`Usp10.lib` before `gdi32.lib`, ScriptShape page). ScriptShape's own doc page lists `api_location: usp10.dll, GDI32.dll, GDI32Full.dll` — the exports are now also routed through gdi32full, i.e. GDI itself still depends on this code path (longevity signal).
**Relevance:** 90% (MVP backend for BIDI/ITEMIZE/SHAPE).

### Solution 2: DirectWrite (IDWriteTextAnalyzer + IDWriteFontFallback)
| Aspect | Assessment |
|--------|------------|
| Type | OS API (COM, dwrite.dll) |
| Platform | Win7+ (analyzer); Win8.1+ (IDWriteFontFallback via IDWriteFactory2) |
| URL | https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritetextanalyzer-getglyphs |
| Maturity | MATURE, actively developed |
| License | None needed (OS component) |

`GetGlyphs` outputs `UINT16 glyphIndices` + `UINT16 clusterMap` for an `IDWriteFontFace` (fetched signature; buffer estimate "3 * textLength / 2 + 16"). System font fallback: `IDWriteFactory2::GetSystemFontFallback` → `IDWriteFontFallback::MapCharacters` (https://learn.microsoft.com/en-us/windows/win32/api/dwrite_2/nn-dwrite_2-idwritefontfallback).
**Strengths:** all four seams from one OS component, including the system fallback list; current Unicode; GDI interop guarantees the physical-typeface bridge (CreateFontFaceFromHdc, above).
**Weaknesses:** COM only — **no C API exists**; worse, `AnalyzeScript`/`AnalyzeBidi`/`MapCharacters` require the *caller to implement* COM callback interfaces (`IDWriteTextAnalysisSource`/`Sink`), meaning hand-built vtables in C glue callable from Eiffel — the single most expensive binding in this option space (COM-in-C layout: https://devblogs.microsoft.com/oldnewthing/20040205-00/?p=40733; no maintained C wrapper was found in this research). Fallback-font → LOGFONT round trip is "not guaranteed" to hit the same physical font (`ConvertFontFaceToLOGFONT` caveat — https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritegdiinterop-convertfontfacetologfont). Color output needs D2D (moot here).
**Relevance:** 70% (stage-2 backend; its unique MVP-relevant gain is system font fallback).

### Solution 3: HarfBuzz (+ SheenBidi)
| Aspect | Assessment |
|--------|------------|
| Type | Shipped C libraries (DLLs) |
| Platform | Cross-platform |
| URL | https://github.com/harfbuzz/harfbuzz ; https://github.com/Tehreer/SheenBidi |
| Maturity | MATURE (the industry shaper: Chrome, GTK, Qt, Android) |
| License | HarfBuzz "Old MIT"; SheenBidi Apache-2.0 (FriBidi is LGPL — avoid) |

**Strengths:** best shaping quality and current Unicode; `hb-cairo` (HarfBuzz ≥ 7.0) is a first-party precedent of exactly our bridge — "use hb_cairo_glyphs_from_buffer() to obtain the glyphs in a form that can be passed to cairo_show_text_glyphs() or cairo_show_glyphs()" (https://harfbuzz.github.io/integration-cairo.html).
**Weaknesses:** violates the zero-DLL preference (ship + update harfbuzz.dll, sheenbidi.dll); needs raw font bytes (`GetFontData` from GDI, or file paths) rather than HFONTs; covers only GLYPH_SHAPER (+bidi via SheenBidi) — itemization and fallback stay ours anyway.
**Relevance:** 40% (contingency if a font's Hebrew mark positioning misbehaves under Uniscribe; not MVP).

### Solution 4: Pure-Eiffel backends (UAX #9 / UAX #24)
| Aspect | Assessment |
|--------|------------|
| Type | To-build library code |
| URL (specs) | https://www.unicode.org/reports/tr9/ ; UAX #24 script property |
| Test oracles | BidiTest.txt (513,494 cases) + BidiCharacterTest.txt in the UCD; C reference impl: https://www.unicode.org/Public/PROGRAMS/BidiReferenceC/12.0.0/ReadMe.txt |

Bidi and script itemization are fully specified, conformance-testable, and tractable pure Eiffel — the designed staged replacements for seams 1–2. OpenType shaping (GSUB/GPOS) is NOT tractable short-term: the complete Rust port of HarfBuzz's shaper (rustybuzz) is a multi-year community effort that still runs 1.5–2x slower than HarfBuzz (https://github.com/harfbuzz/rustybuzz) — evidence for keeping GLYPH_SHAPER on the OS backend.

### Solution 5: GDI GetCharacterPlacement / ExtTextOut (the poor-man's path) — ELIMINATED
Microsoft's own documentation: "a need to work with an increasing number of languages and scripts has rendered it obsolete, and it has been superseded by the functionality of the Uniscribe module" (https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-getcharacterplacementw). Dead on arrival.

## Eiffel Ecosystem Check

### simple_* libraries (verified locally at D:\prod)
- **No text shaping, bidi, Uniscribe, or DirectWrite code exists anywhere in the ecosystem** — a full-tree grep of D:\prod *.e/*.ecf (plus targeted greps of the simple_widgets, simple_cairo, simple_speech, simple_vision, simple_clipboard, simple_chat, simple_reel, simple_scholar sources and gobo string library): zero real hits. The only matches were substring false positives ("dwrite" inside SQLITE_OPEN_READWRITE) in eiffel_sqlite_2025 — verified by inspection.
- `simple_cairo` — the renderer wrapper; ships the full cairo headers *including cairo-win32.h* in its Clib (so the two win32 font externals compile against in-tree headers), but **does not yet bind `cairo_show_glyphs`/`cairo_glyph_t`** (grep of src/cairo_context.e). A small gated addition is a dependency (see 04 D-S07).
- `simple_widgets` — the consumer; draws text via toy `show_text` today (sw_painter.e:74); `SW_CHAT_THREAD` exists with greedy word wrap to replace.

### ISE / Gobo
- Gobo 26.06 string library: no bidi implementation (local grep). ISE docs mention bidi *control characters* only lexically (https://dev.eiffel.com/Unicode_Free_Operator). EiffelVision2 delegates text to GDI — no shaping abstraction to reuse.

### Gap Analysis
Not available in Eiffel: everything this library is. simple_shaping would be the first Eiffel text-shaping library found by this research.

## Cross-language patterns (pango-less shaper→renderer stacks)

| Stack | Pattern | Source |
|-------|---------|--------|
| hb-cairo (C) | shaper buffer → `cairo_show_glyphs` — first-party since HarfBuzz 7.0 | https://harfbuzz.github.io/integration-cairo.html |
| cosmic-text (Rust) | Four separable pieces: shaping (HarfRust/rustybuzz), custom bidi layout, **custom font fallback "reusing some of the static fallback lists in browsers"**, raster (swash) | https://github.com/pop-os/cosmic-text |
| Pango (C) | Split itemization/segmentation (Pango) from shaping (HarfBuzz); dropped its per-script native modules at 1.31.0 | https://en.wikipedia.org/wiki/Pango ; https://fossies.org/linux/pango/NEWS |

The "external shaper feeding cairo_show_glyphs" pattern is well-trodden, and cosmic-text independently validates the D-014 four-seam decomposition — including app-owned static-list font fallback.

## Comparison Matrix (per D-014 seam)

| Seam | Uniscribe | DirectWrite | HarfBuzz stack | Pure Eiffel | GDI GCP |
|------|-----------|-------------|----------------|-------------|---------|
| BIDI_RESOLVER | ✓ ScriptItemize levels + ScriptLayout | ✓ AnalyzeBidi (COM callbacks) | ✓ SheenBidi | ✓ UAX #9 (testable) | ✗ obsolete |
| SCRIPT_ITEMIZER | ✓ ScriptItemize | ✓ AnalyzeScript (COM callbacks) | ✗ caller's job | ✓ UAX #24 | ✗ |
| GLYPH_SHAPER | ✓ ScriptShape/ScriptPlace | ✓ GetGlyphs/GetGlyphPlacements | ✓ hb_shape | ✗ long pole | ✗ broken |
| FONT_FALLBACK | ✗ app's job by design | ✓ MapCharacters (8.1+) | ✗ | ✓ static list + probe | ✗ |
| Binding cost | LOW (flat C) | HIGH (COM + callback vtables) | MED (C API, but ship DLLs + font bytes) | HIGH (algorithm work) | — |
| New DLLs shipped | 0 | 0 | 2 | 0 | 0 |

## Build vs Buy vs Adapt

| Option | Effort | Risk | Fit |
|--------|--------|------|-----|
| Build (library + pure-Eiffel everything) | HIGH | HIGH (shaper) | 40% |
| Adopt (an existing stack wholesale — none exists for Eiffel) | — | — | 0% |
| **Build library, Adopt OS backends per seam (Uniscribe MVP)** | MED | LOW | 95% |

**Initial Recommendation:** BUILD the library; ADOPT OS-provided Uniscribe behind the D-014 seams for MVP; PNG emoji per D-019 (now confirmed necessary).
