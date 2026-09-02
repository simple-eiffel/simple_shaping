# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-01 (pre-release: Phase 1 contracts)

Contract skeletons only. Nothing here shapes text yet: `layout` returns a
degenerate one-line, zero-run layout that satisfies every stated contract
(total function, coverage, caching) while the pipeline bodies await Phase 4.
Pure value classes and pure-logic engines already carry real bodies.

### Added
- The four seams as deferred classes with normative contracts (the
  cross-backend equivalence oracle): `BIDI_RESOLVER`, `SCRIPT_ITEMIZER`,
  `GLYPH_SHAPER`, `FONT_FALLBACK`.
- DirectWrite-first MVP effecting slots (G1 final, backed by the
  spikes/dwrite feasibility spike): `DIRECTWRITE_BIDI_RESOLVER`,
  `DIRECTWRITE_SCRIPT_ITEMIZER`, `DIRECTWRITE_GLYPH_SHAPER` - contract-level
  skeletons whose notes bind the proven plain-C COM-shim pattern
  (AnalyzeScript / AnalyzeBidi / GetGlyphs / GetGlyphPlacements).
  Uniscribe classes are named-only alternate slots; they do not exist yet.
- `LIST_FONT_FALLBACK` (G2): the library's own fallback in every configuration.
- Result model: `SHAPED_LAYOUT` -> `SHAPED_LINE` -> `SHAPED_RUN` closed over
  exactly `GLYPH_RUN` | `IMAGE_RUN`; `SHAPING_NOTE` degradation records.
- Emoji subsystem: `EMOJI_SEGMENTER` (runs after bidi, BEFORE itemization -
  spike-confirmed necessity), `EMOJI_ASSET_CATALOG` (Noto `emoji_u1f916`
  naming; disk-free resolution via an injectable existence probe),
  `EMOJI_DATA_TABLES` (generator-owned; UNPINNED until Phase 3 acquisition).
- `SHAPING_FONT` (same-N holder) + `FONT_REGISTRY` (per-processor ownership).
- `LAYOUT_CACHE`: real LRU with full-key verification on hit (R8).
- `FONT_LIST` (real builder + value-based digest), `SHAPING_STATISTICS`
  (R7 counter definitions), `FALLBACK_CHOICE`, pipeline value classes.
- NULL_* doubles for all four seams with real pure-logic bodies (headless).
- `SIMPLE_SHAPING` facade wired DirectWrite-first; degenerate total-function
  `layout` with the full contract already enforced.
- MML model queries on every collection-bearing class (simple_mml).
- Testing: TEST_APP + LIB_TESTS (real tests where logic is real, skeletal
  Phase-5 assault stubs), SCOOP consumer test, BIDI_CONFORMANCE_HARNESS skeleton.

### Deferred (deliberate, recorded)
- `SHAPING_CAIRO_BRIDGE` + `EMOJI_SURFACE_CACHE`: await the gated simple_cairo
  D-S07 glyph API (no cairo dependency in Phase 1).
- `USP10_API` + `UNISCRIBE_*`: the named alternate backend slot (G1 final).
- Native bodies (dwrite/gdi32 externals), real shaping, wrap, probing: Phase 4.
- Noto png/128 assets + pinned Unicode tables: Phase 3 acquisition (R4).
