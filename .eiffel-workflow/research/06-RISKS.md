# RISKS: simple_shaping

## Risk Register

| ID | Risk | Likelihood | Impact | Mitigation |
|----|------|------------|--------|------------|
| RISK-001 | COM-from-Eiffel cost explodes (DirectWrite stage 2: callback vtables) | HIGH (if attempted) | MED | MVP needs zero COM (D-S01); prototype COM glue on callback-free WIC first (D-020); build DWrite only against a demonstrated limit (D-S02) |
| RISK-002 | Deprecated-API longevity: Uniscribe frozen/removed | LOW | HIGH | usp10.dll ships in Win 10/11; exports routed through GDI32/GDI32Full (load-bearing for GDI); seams make DWrite a backend swap, not a rewrite; conformance harness verifies the swap |
| RISK-003 | Color-emoji dead end mis-handled (someone later "fixes" emoji via fonts) | MED | MED | Settled as a constraint, not an option: 02-LANDSCAPE documents why no glyph path can be color here; D-S04 records the decision; contracts route emoji to IMAGE_RUNs |
| RISK-004 | Bidi correctness bugs (the classic mixed-digit/punctuation cases) | HIGH (without testing) | HIGH | BidiTest.txt (513,494 cases) + BidiCharacterTest.txt harness in MVP; OS backend spot-checked against it; pure-Eiffel resolver gated on full pass; the D-015 acceptance string is a standing smoke test |
| RISK-005 | Emoji asset/table drift: new Unicode emoji → tofu or split sequences | MED | LOW | Pin one Unicode version for tables+assets (D-S08); FR-007 graceful degradation (per-codepoint images → monochrome glyphs); refresh is a data regeneration, not code |
| RISK-006 | Font-realization mismatch (stage 2): DWrite-fallback font → LOGFONT not guaranteed same physical font | MED (stage 2 only) | MED | HFONT-first pipeline (D-S03); `CreateFontFaceFromHdc` guarantee in the DWrite→GDI direction; startup probe compares glyph ids (GDI GetGlyphIndices vs DWrite) per fallback face; MVP (Uniscribe) is HFONT-native and immune |
| RISK-007 | Size mismatch between shaper metrics and cairo rasterization (cairo ignores LOGFONT height; sizes via font matrix) | MED | MED | Same-N rule in D-S03 (shape at pixel size N, cairo set_font_size N, same face); round-trip pixel test in FR-010 |
| RISK-008 | simple_cairo gated addition slips (no glyph API yet in cairo_context.e) | MED | HIGH (blocks painting) | D-S07 is small and additive (4-ish externals; headers already in Clib); raise the gate with Larry at spec phase; fallback: temporary externals inside simple_shaping's own Clib, migrated later |
| RISK-009 | SCOOP/threading: SCRIPT_CACHE concurrency semantics unverified | MED | MED | OQ-1 blocks contract freeze until settled; conservative default: confine all shaping to one processor (chat pane shapes on the UI processor anyway) |
| RISK-010 | Hebrew niqqud/cantillation positioning quality varies by font under Uniscribe | LOW-MED | MED | Acceptance tests with pointed Hebrew in the default font list (OQ-3); contingency ladder: different font → DWrite backend → HarfBuzz DLL (D-S02, 02-LANDSCAPE Solution 3) |
| RISK-011 | Scope creep toward a text editor | MED | MED | C-007: chat-pane display only; hit-testing is a reserved API (FR-013), not MVP work |

## Technical Risks — detail

### RISK-001: COM from Eiffel
**Description:** DirectWrite has no C API; `AnalyzeScript`/`AnalyzeBidi`/`MapCharacters` require implementing `IDWriteTextAnalysisSource`/`Sink` — building COM objects (vtable structs + IUnknown) in C glue that call back into Eiffel.
**Indicators:** glue file growth, refcount crashes, SCOOP/callback re-entrancy pain.
**Mitigation/Contingency:** as in register; the MVP never touches it.

### RISK-002: Uniscribe longevity
**Description:** Microsoft steers new code to DirectWrite (Learn portal pages; Wikipedia notes DirectWrite as intended replacement while Uniscribe remained maintained as of 2021). No removal signal exists; GDI itself still routes through this code (`api_location: GDI32.dll, GDI32Full.dll` on ScriptShape).
**Indicators:** a Windows release note deprecating usp10 exports.
**Contingency:** DirectWrite backend (D-S02) — the seams were built for exactly this.

### RISK-004: Bidi correctness
**Description:** Mixed Hebrew/digits/punctuation ordering is where every ad-hoc bidi breaks; Larry's real content (Hebrew + English + verse references) is the hard case.
**Indicators:** harness divergence; misordered punctuation at run boundaries in the demo.
**Mitigation:** harness from day one; never hand-roll reordering outside BIDI_RESOLVER (the vault's own bidi lesson: wrap runs, don't reword).

## Ecosystem Risks
- simple_widgets integration: SW_PAINTER grows a `draw_shaped_line`; SW_CHAT_THREAD's greedy wrap (sw_chat_thread.e:192) is replaced by SHAPED_LINE layout — coordinate with simple_widgets' owner (same author, but it is a second gated repo change besides D-S07).
- Asset licensing hygiene: Noto Apache-2.0 (or Twemoji CC-BY attribution) must ship in the runnable folder (NFR-009) — a release-checklist item, not code.

## Resource Risks
- Single developer + AI chain; the long pole (pure-Eiffel GLYPH_SHAPER) is explicitly deferred indefinitely (D-S06) to keep MVP inside a few working sessions of binding + layout code.
- Unicode data generation (D-S08) is scripted work; budget it in tasks phase rather than hand-typing tables.
