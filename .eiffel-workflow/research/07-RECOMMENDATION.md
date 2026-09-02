# RECOMMENDATION: simple_shaping

## Executive Summary

BUILD simple_shaping as the D-014 four-seam library, ADOPTING OS-provided Uniscribe behind three of the seams for MVP and owning FONT_FALLBACK ourselves; emoji ship as inline PNGs (D-019 is now *forced*, not optional — no color-font path exists through cairo 1.17.2's win32 font backend). The shaper→`cairo_show_glyphs` bridge is confirmed viable from real documentation and cairo source: cairo-win32 draws glyph indices via `ExtTextOutW(ETO_GLYPH_INDEX)`, exactly the space Uniscribe/DirectWrite emit for the same HFONT.

## Recommendation

**Action:** BUILD (library) + ADOPT (OS Uniscribe backend MVP; DirectWrite stage-2; pure-Eiffel bidi/itemizer staged behind conformance gates)
**Confidence:** HIGH — every load-bearing claim traces to fetched primary documentation or locally verified headers/source (REFERENCES.md); the two genuinely open items (SCRIPT_CACHE threading, asset-set choice) are flagged as OQ-1/OQ-2, not assumed.

## Rationale

1. Uniscribe delivers correct Hebrew bidi + shaping through a flat C API with zero shipped DLLs and zero COM — the cheapest correct MVP by a wide margin (04 D-S01).
2. Font fallback must be ours regardless of backend (Uniscribe mandates it; determinism across members' machines wants it) — so Uniscribe's one gap costs nothing extra (D-S05).
3. Color emoji cannot render through this pipeline under ANY shaper (GDI/cairo-win32 monochrome-only; cairo color work is FT-side and post-1.17.2; DWrite color needs D2D). PNG image runs are the only color path and give pixel-identical 🤖 everywhere (D-S04).
4. The pattern is industry-standard: hb-cairo, cosmic-text, and Pango all separate shaping from cairo/renderer exactly this way (02).
5. Nothing exists in Eiffel to adopt or adapt (02, ecosystem check).

## Proposed Approach

### Phase 1 (MVP — what SW_CHAT_THREAD needs)
- `SHAPED_PARAGRAPH` API: STRING_32 + width + font config → cached `SHAPED_LINE`s of `GLYPH_RUN | IMAGE_RUN`.
- `UNISCRIBE_BIDI_RESOLVER`, `UNISCRIBE_ITEMIZER`, `UNISCRIBE_SHAPER` (ScriptItemize/Shape/Place/Layout externals; SCRIPT_CACHE per font).
- `LIST_FONT_FALLBACK` (configurable list + missing-glyph probe).
- `EMOJI_SEGMENTER` (UTS #51 pinned tables) + PNG asset resolver (Noto Emoji recommended; OQ-2).
- Cairo bridge per D-S03 (`cairo_win32_font_face_create_for_logfontw_hfont` + `cairo_show_glyphs`; simple_cairo gated addition D-S07).
- Line layout: cluster-safe greedy wrap (ScriptBreak), measurement API, layout cache.
- Conformance harness (BidiCharacterTest.txt sampling) + the `שלום 🤖 Χριστός` acceptance demo.

### Phase 2 (Full)
- `EIFFEL_BIDI_RESOLVER` (UAX #9) gated on full BidiTest.txt + BidiCharacterTest.txt pass; then `EIFFEL_SCRIPT_ITEMIZER` (UAX #24).
- Hit-testing/caret API on SHAPED_LINE for SW_TEXT_BOX (ScriptXtoCP/CPtoX-class).
- `DIRECTWRITE_*` backends only against a demonstrated limit (D-S02), starting with MapCharacters fallback.
- Optional HarfBuzz shaper contingency if a Hebrew-marks font defect appears (RISK-010).

## Key Features
1. Four swappable contract seams (D-014 honored): backend equivalence enforced by shared postconditions + conformance harness.
2. Mixed-script chat text correct: Hebrew RTL with niqqud, Greek, Latin, one line.
3. Deterministic emoji: sequence-keyed PNG runs, identical on every machine.
4. Zero new DLLs; runnable folder + PNG assets + license files.
5. Paint-path-free shaping: cached SHAPED_LINEs; hundreds of visible lines at chat pace.

## Success Criteria
- D-015 acceptance string renders correctly in the simple_widgets client with no browser process.
- BidiCharacterTest samples pass on MVP; full-suite pass gates the pure-Eiffel resolver.
- Re-paint of an unchanged pane performs zero shaping calls.
- Fresh-machine run from the copied folder: no installer, no missing DLLs.

## Dependencies

| Library | Purpose | simple_* Preferred |
|---------|---------|-------------------|
| simple_cairo | glyph drawing (needs gated additive glyph API, D-S07) | YES (exists, D:\prod\simple_cairo) |
| simple_widgets | consumer (SW_PAINTER/SW_CHAT_THREAD integration) | YES (exists) |
| OS: usp10 / gdi32 | MVP backends | n/a (OS-provided) |
| Noto Emoji or Twemoji PNGs | emoji assets (Apache-2.0 / CC-BY 4.0) | asset, license section required |
| Unicode data (pinned) | UTS #51 tables, BidiTest oracles | data, generated into Eiffel |

## Next Steps
1. Larry's gates: D-S01 (Uniscribe-first, amending D-014's "DirectWrite first" naming), D-S04 asset set, D-S07 simple_cairo addition.
2. Run `/eiffel.spec D:\prod\simple_shaping` to transform this research into the specification.
3. Then `/eiffel.intent` and the Spec Kit chain.

## Open Questions (for spec phase)
- OQ-1 SCRIPT_CACHE threading model under SCOOP (blocks contract freeze).
- OQ-2 Noto vs Twemoji (license/style; recommendation: Noto).
- OQ-3 Hebrew fallback list for pointed text.
- OQ-4 Emoji PNG decode/cache shared with the D-020 WIC image pipeline?
