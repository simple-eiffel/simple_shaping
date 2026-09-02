# Approach: simple_shaping implementation sketch (Phase 2, Step 1)

Reviewed at main 94242d8 (Phase 1m). 37 src classes + 4 testing classes.

## Architecture overview

```
SIMPLE_SHAPING (facade; one per SCOOP processor; SHAPING_CONSTANTS mixin)
 |-- seams (deferred; contracts = cross-backend oracle, I-001)
 |    BIDI_RESOLVER      <- DIRECTWRITE_BIDI_RESOLVER (G1 final) | NULL_
 |    SCRIPT_ITEMIZER    <- DIRECTWRITE_SCRIPT_ITEMIZER          | NULL_
 |    GLYPH_SHAPER       <- DIRECTWRITE_GLYPH_SHAPER             | NULL_
 |    FONT_FALLBACK      <- LIST_FONT_FALLBACK (G2, ours always) | NULL_
 |-- engines/state (per facade, confined - OQ-1/DR-012)
 |    EMOJI_SEGMENTER (FR-007 ladder) + EMOJI_ASSET_CATALOG (+ EMOJI_DATA_TABLES, D-S08)
 |    FONT_REGISTRY -> SHAPING_FONT (identity objects; native handles Phase 4)
 |    LAYOUT_CACHE (bounded LRU, R8 verified hits) + SHAPING_STATISTICS (R7)
 |    LINE_LAYOUT_ENGINE (stateless wrap/reorder/metrics; headless-capable)
 |-- native shims (implementation layer; inert in Phase 1)
 |    DWRITE_API (single-translation-unit COM shim, spike-proven) + GDI32_API
 |-- values (immutable; invariant = frame)
      BIDI_RESULT, SCRIPT_ITEM, SHAPED_ITEM, TEXT_SEGMENT, FALLBACK_CHOICE,
      SHAPED_RUN (closed: GLYPH_RUN | IMAGE_RUN), SHAPED_LINE, SHAPED_LAYOUT,
      SHAPING_NOTE, FONT_LIST (value-comparable config)
```

## Data flow (layout, A-C03/DR-005)

1. `cache_key` (fonts digest | width | size | asset dir | text) -> `LAYOUT_CACHE.item_verified` (R8: hit verified against stored text/width/size; mismatch demoted to miss). Hit: record_cache_hit, return shared immutable layout - zero shaping (FR-012).
2. Miss: bidi over FULL text (seam 1) -> emoji segmentation (spans inherit levels; ladder resolves against catalog) -> itemize PLAIN spans (seam 2, script x bidi intersection) -> per item: fallback choice (seam 4, probe-by-shaping) then shape (seam 3, same-N at font.pixel_size) -> greedy cluster-safe wrap (engine; R2 hanging whitespace via `fits_within`; DR-007 no breaks inside clusters/emoji) -> per-line visual reorder (seam 1 `reorder`) -> SHAPED_LINEs -> SHAPED_LAYOUT (+ SHAPING_NOTEs) -> `cache.put`.
3. Degradations: fallback exhaustion -> requested font's boxes + note; hard native failure -> R3 tofu-but-valid synthesis; unresolvable emoji -> PLAIN + note. `layout` is total (NFR-011).

## Implementation order (Phase 4)

1. Clib shim (grow spikes/dwrite pattern into Clib/simple_shaping_dwrite.h) + DWRITE_API/GDI32_API externals.
2. SHAPING_FONT realization + FONT_REGISTRY disposal + R1 existence probe (realized_face_name comparator); effective list + R5 effective digest.
3. DIRECTWRITE_BIDI_RESOLVER (AnalyzeBidi + UTF-16<->codepoint mapping; L2 reorder), DIRECTWRITE_SCRIPT_ITEMIZER (intersection + AnalyzeLineBreakpoints), DIRECTWRITE_GLYPH_SHAPER (GetGlyphs/GetGlyphPlacements + R3 synthesis).
4. EMOJI_SEGMENTER RGI longest-match (needs Phase-3 generated tables + assets) + LIST_FONT_FALLBACK walk (script-class bucketing by codepoint range).
5. LINE_LAYOUT_ENGINE real wrap; facade pipeline + R7 counting; then D-S07 bridge (gated, simple_cairo).

## Key design decisions honored (bound; verified present)

DirectWrite-first G1 (facade wires DIRECTWRITE_*; UNISCRIBE_* named-only); G2 LIST_FONT_FALLBACK in every config; G3 Noto PNG + structural SHAPED_RUN split; D-S03 same-N holder; OQ-1 confinement (no `separate` in any public signature - verified across all 41 files); R3 tofu-but-valid; R8 verified hits; MML models on all 24 collection surfaces (Phase 1m). Pure-TrueType endgame: no contract references it (verified absent).

## Dependencies

simple_mml (in ECF), simple_testing (tests target); simple_cairo arrives Phase 4 behind Larry's D-S07 gate; OS dwrite/gdi32 at Phase 4; Noto assets + generated tables at Phase 3 (R4 pinning).

## Risk areas (feeds the review)

- The emoji-free precondition network between segmenter and itemizer (FR-007 rung 3 vs `plain_span_only`).
- Cache-key/digest injectivity (family names may contain separator characters).
- Seam 4 signature vs per-call `a_fonts` policy; R7 probe-count observability.
- Same-N closure across facade -> registry -> runs; Noto filename padding; UTF-16<->codepoint mapping correctness (Phase 4).
