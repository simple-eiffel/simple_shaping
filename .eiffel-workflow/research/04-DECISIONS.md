# DECISIONS: simple_shaping

Numbered D-S* to avoid colliding with simple_chat's D-*. D-014/D-019 inputs are Larry's; everything below is this research's proposal for the spec phase.

## D-S01: MVP native backend is Uniscribe, not DirectWrite

**Question:** D-014 said "Windows-native backend FIRST" and named DirectWrite. Which native technology actually goes first?
**Options:**
1. DirectWrite (IDWriteTextAnalyzer + IDWriteFontFallback): all four seams, current Unicode — but COM-only, and the analyzer/fallback APIs require the *caller to implement* COM callback interfaces (IDWriteTextAnalysisSource/Sink), i.e. hand-built vtables in C glue; no official or maintained C wrapper found (sources in 02).
2. Uniscribe (ScriptItemize/ScriptShape/ScriptPlace/ScriptLayout): three of four seams, flat C API, shapes directly against HFONTs (zero font-realization gap with the cairo face), missing-glyph probes designed for app-side fallback — but frozen and legacy.
3. HarfBuzz(+SheenBidi): best shaping — but two shipped DLLs and font-file plumbing, against the zero-DLL policy.

**Decision:** Uniscribe backend for BIDI_RESOLVER, SCRIPT_ITEMIZER, GLYPH_SHAPER. FONT_FALLBACK is simple_shaping's own list-based component in every configuration (see D-S05).
**Rationale:** Covers everything the chat pane needs at a fraction of the binding cost; the four-seam architecture makes this choice cheap to revisit (that is what D-014 bought). What breaks first on Uniscribe vs DirectWrite, concretely: (a) no system font-fallback service — mitigated by D-S05, which we need for backend-independence anyway; (b) newest Unicode scripts/emoji-sequence shaping frozen — emoji are intercepted *before* the shaper by D-S04, and Hebrew/Greek/Latin predate Uniscribe; (c) no color glyphs — moot on this render path for DirectWrite too (02-LANDSCAPE). Longevity: usp10.dll ships in Windows 10/11 and its exports are also routed through GDI32/GDI32Full (ScriptShape api_location), so it is load-bearing for GDI itself.
**Implications:** MVP needs zero COM and zero shipped DLLs. Win8+ link-order note (Usp10.lib before gdi32.lib) goes into the build docs.
**Reversible:** YES — that is the point of the seams.

## D-S02: DirectWrite is the stage-2 backend, gated on an actual limit being hit

**Question:** When does the DirectWrite backend get built?
**Decision:** Only when a real deficiency shows up (fallback quality, a script Uniscribe mishandles, or Windows breaking usp10 — none expected). Its first target seam is FONT_FALLBACK (`IDWriteFactory2::GetSystemFontFallback` → `MapCharacters`, Win 8.1+), because that is DirectWrite's only capability the MVP lacks.
**Rationale:** COM-callback binding cost is the highest in the option space; pay it against a demonstrated need, not up front.
**Implications:** The C-glue layer for COM (vtable structs) can be prototyped against a callback-free interface first (WIC per simple_chat D-020 uses factory-style COM without callbacks).
**Reversible:** YES.

## D-S03: The cairo bridge contract (HFONT-first)

**Question:** How do shaper glyph indices map onto cairo's win32 font face? Same font realization? HFONT per run?
**Decision:** One `SHAPING_FONT` per (family, weight, style, pixel size) owning: a LOGFONTW, an HFONT selected into a memory HDC for shaping, a `SCRIPT_CACHE`, and a lazily created `cairo_font_face_t` from `cairo_win32_font_face_create_for_logfontw_hfont (logfont, hfont)`. Shaping and placement run at pixel size N through the HFONT; the cairo side sets font size N on the same face; `GLYPH_RUN` carries glyph ids + absolute positions; painting is `cairo_show_glyphs`. Per-run face switching implements fallback rendering.
**Rationale (all verified, 02-LANDSCAPE):** cairo-win32 draws glyph arrays via `ExtTextOutW(...ETO_GLYPH_INDEX...)`, so `cairo_glyph_t.index` is the HFONT's physical glyph id — exactly what ScriptShape emits for that HFONT; DirectWrite's own GDI-interop guarantee ("same physical typeface ... using ExtTextOut", CreateFontFaceFromHdc) documents the equivalence for stage 2. cairo ignores LOGFONT height fields and sizes via the font matrix, hence the same-N rule.
**Implications:** simple_shaping owns HFONT/HDC lifetime; cairo faces are cached per font, not per run. Positions from the shaper are authoritative; cairo never re-measures.
**Reversible:** YES (a future FT-font backend would swap the face constructor and glyph-id source together behind GLYPH_SHAPER).

## D-S04: D-019 DECIDED — emoji are inline PNG images; recommended set: Noto Emoji

**Question:** Emoji as inline PNGs vs COLR/CBDT color-font rendering through the pipeline.
**Decision:** Inline PNGs. Color-font rendering is **not possible** on this render path: GDI has no color-font support, cairo-win32 draws Segoe UI Emoji as monochrome outlines, cairo's color-font work is FreeType-side and post-1.17.2, and DirectWrite's color output requires TranslateColorGlyphRun + D2D drawing — a different renderer (citations in 02-LANDSCAPE). So the image path is the only color path, and it also delivers the product requirement that 🤖 is identical on every machine.
**Asset recommendation:** Noto Emoji PNGs (`png/128/emoji_u1f916.png`), Apache-2.0 — no attribution UI requirement, larger masters that downscale cleanly. Twemoji (CC-BY 4.0, 72px) remains acceptable if Larry prefers the style; attribution then ships in LICENSE-ASSETS.md + About. Larry's call at spec (OQ-2); the code is asset-set-agnostic (keyed by codepoint sequence).
**Mechanism:** an EMOJI_SEGMENTER (UTS #51 data: emoji-test.txt RGI set, emoji-zwj-sequences.txt, VS16) runs BEFORE itemization/shaping and lifts emoji sequences out as `IMAGE_RUN`s; the shaper never sees them. Unknown/future sequences degrade per FR-007.
**Reversible:** The seam is; the 1.17.2 constraint is not ours to lift here.

## D-S05: FONT_FALLBACK is always simple_shaping's own component (list + probe)

**Question:** Whose fallback?
**Decision:** A configurable ordered font list per script class (default: UI font → Segoe UI → per-script additions), probed by shaping (missing-glyph scan / USP_E_SCRIPT_NOT_IN_FONT per the Learn "Using Font Fallback" procedure), cached per (codepoint-range, font).
**Rationale:** Uniscribe *requires* the app to do this; cosmic-text independently chose the same design (static browser-derived lists) on every platform; and owning the list makes rendering deterministic across members' machines — a chat-product value the system fallback cannot give. A DirectWrite MapCharacters adapter can slot in later (D-S02) as an alternative provider behind the same deferred class.
**Reversible:** YES.

## D-S06: Staged pure-Eiffel replacement order

**Decision:** (1) EIFFEL_BIDI_RESOLVER — UAX #9, gated on passing the full BidiTest.txt (513,494 cases) + BidiCharacterTest.txt harness; (2) EIFFEL_SCRIPT_ITEMIZER — UAX #24 Scripts.txt tables (+ the emoji segmenter is already pure Eiffel from day one); (3) FONT_FALLBACK is pure Eiffel from day one (D-S05); (4) GLYPH_SHAPER stays native indefinitely — rustybuzz's multi-year, still-slower port of HarfBuzz's shaper is the measured cost of going native there; revisit only if the ecosystem ever needs non-Windows rendering, and then prefer binding HarfBuzz (hb-cairo precedent) over porting it.
**Implications:** the conformance harness ships in MVP so every swap is verifiable; the harness also spot-checks the Uniscribe backend (levels from ScriptItemize) to catch divergence early.
**Reversible:** YES.

## D-S07: simple_cairo needs a small gated addition (glyph API)

**Question:** simple_cairo today binds no glyph-level drawing (verified: no `show_glyphs` in src/cairo_context.e).
**Decision (proposed, needs Larry's gate — separate repo):** add to simple_cairo: `cairo_glyph_t` array marshalling, `show_glyphs`, `glyph_extents`, and the two win32 face constructors (headers already in its Clib). simple_shaping consumes them; no cairo internals leak above simple_cairo.
**Rationale:** keeps the ecosystem layering (simple_widgets → simple_shaping → simple_cairo → cairo.dll); avoids simple_shaping linking cairo directly.
**Reversible:** YES (small, additive).

## D-S08: Emoji segmentation data are compiled-in tables, version-pinned

**Decision:** Generate Eiffel tables from pinned Unicode data files (emoji-test.txt RGI set + emoji-zwj-sequences.txt, one Unicode version matching the shipped asset set), with the generator script and data version recorded in the repo. No runtime parsing of UCD files.
**Rationale:** deterministic, runnable-folder friendly; asset set and detection tables must move in lockstep (RISK-005).
**Reversible:** YES.
