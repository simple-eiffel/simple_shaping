# DOMAIN MODEL: simple_shaping

The domain is the Unicode text-rendering pipeline: logical text → bidi levels → segments/items → shaped glyphs or image boxes → wrapped visual lines → painted pixels. Concepts below map 1:1 to classes in 04-CLASS-DESIGN.

## The Pipeline (domain picture)

```
READABLE_STRING_32 (logical order, one paragraph = one chat message)
        │
        ▼
 [Bidi Resolution]      levels per character (UAX #9), paragraph direction (first-strong)
        │
        ▼
 [Emoji Segmentation]   UTS #51: lift emoji sequences OUT as image segments (shaper never sees them)
        │
        ▼
 [Script Itemization]   UAX #24: split plain segments into same-script, same-level items
        │
        ▼
 [Fallback + Shaping]   per item: pick covering font (list+probe), shape → glyph ids/advances/clusters
        │
        ▼
 [Line Layout]          greedy wrap at soft breaks, cluster-safe; per-line visual reorder (UAX #9 L2)
        │
        ▼
 SHAPED_LAYOUT → SHAPED_LINE* → SHAPED_RUN* (GLYPH_RUN | IMAGE_RUN)
        │
        ▼
 [Cairo Bridge]         glyph runs: cairo face (same HFONT) at same pixel size N → show_glyphs
                        image runs: PNG surface blit (CAIRO_SURFACE.make_from_png, cached)
```

Note on order: bidi runs over the FULL paragraph (emoji are bidi-neutral but still need levels so image boxes land correctly inside RTL lines); segmentation lifts emoji AFTER levels are assigned and BEFORE itemization/shaping — this refines D-S04's "before itemization/shaping" without contradicting it (see 03 A-C03).

## Domain Concepts

### Concept: Paragraph Layout
**Definition:** The complete visual arrangement of one logical paragraph (one chat message) at a given wrap width and pixel size.
**Attributes:** source text, wrap width, pixel size, base direction, lines, total width/height, degradation notes.
**Behaviors:** none (immutable value); queried by the painter and by bubble sizing.
**Related to:** contains Lines; produced by the Facade; cached by the Layout Cache.
**Will become:** `SHAPED_LAYOUT`

### Concept: Visual Line
**Definition:** One wrapped line: a contiguous LOGICAL character range of the paragraph whose runs are stored in VISUAL (left-to-right paint) order after UAX #9 L2 reordering.
**Attributes:** runs (visual order), width, height, ascent (baseline offset), logical source range, overflow flag.
**Behaviors:** measurement queries; FUTURE reserved hit-testing (`character_index_at_x`, `x_at_character_index`).
**Related to:** contains Runs; owned by Paragraph Layout.
**Will become:** `SHAPED_LINE`

### Concept: Run (deferred)
**Definition:** A maximal same-kind stretch of a line: either glyphs of one font in one direction, or one emoji image box. The heterogeneity is the domain's own (I-002): color emoji CANNOT travel the glyph path here, so the run model carries the split structurally.
**Attributes:** logical source range, advance width, direction.
**Behaviors:** paint-form queries.
**Will become:** deferred `SHAPED_RUN`; heirs `GLYPH_RUN`, `IMAGE_RUN`

### Concept: Glyph Run
**Definition:** Positioned glyphs of ONE font at ONE pixel size in ONE direction, ready for `cairo_show_glyphs` (ids are the HFONT's physical glyph indices = `cairo_glyph_t.index` space, per the verified bridge).
**Attributes:** font (Shaping Font), glyph ids, per-glyph x/y positions (run-relative, baseline origin), advance width, cluster map (source char → glyph group; monotone, decreasing for RTL), script code, bidi level.
**Will become:** `GLYPH_RUN`

### Concept: Image Run
**Definition:** One emoji sequence rendered as a pinned PNG asset box — pixel-identical on every machine (G3).
**Attributes:** codepoint sequence, asset key (Noto naming: `emoji_u1f916`, VS16 dropped, ZWJ joined with `_`), resolved asset path, box width/height.
**Domain rule:** an Image Run in a finished layout ALWAYS has a resolved asset — unresolved sequences degrade back to the glyph path BEFORE run construction (FR-007), so consumers never handle a broken image.
**Will become:** `IMAGE_RUN`

### Concept: Shaping Font
**Definition:** The realized font identity shared by shaper and renderer: one per (family, weight, style, pixel size). NOT a value — an identity object owning native resources.
**Attributes:** family, weight/style, pixel size; owns LOGFONTW, HFONT selected in a memory HDC, SCRIPT_CACHE (Uniscribe), lazily created cairo font face from `cairo_win32_font_face_create_for_logfontw_hfont`.
**Domain rule (same-N):** shaping/placement run at pixel size N through the HFONT; cairo sets font size N on the same face; positions from the shaper are authoritative (D-S03; cairo ignores LOGFONT height fields).
**Domain rule (confinement):** a Shaping Font and its SCRIPT_CACHE belong to exactly ONE processor's registry — never shared (OQ-1 resolution).
**Will become:** `SHAPING_FONT` (registry: `FONT_REGISTRY`)

### Concept: Font List (fallback policy)
**Definition:** The ordered, per-script-class font preference list that makes rendering deterministic across machines (G2).
**Attributes:** general ordered family names; per-script-class prepend lists (hebrew, greek, latin, symbol, other).
**Default (resolves OQ-3):** general: [UI font (theme-supplied, e.g. "Archivo"), "Segoe UI", "Arial", "Tahoma"]; hebrew class prepends: ["SBL Hebrew" (kept only if the probe finds it installed), "Segoe UI", "David", "Tahoma"]; greek class prepends: ["Segoe UI", "Palatino Linotype"]. Pointed-Hebrew acceptance test guards quality (RISK-010).
**Will become:** `FONT_LIST`

### Concept: Bidi Resolution
**Definition:** UAX #9 output for a paragraph: one embedding level per character (even=LTR, odd=RTL) + paragraph level; and, per line, the level-driven visual permutation (L2).
**Will become:** `BIDI_RESULT` (value) produced by seam `BIDI_RESOLVER`

### Concept: Script Item
**Definition:** A maximal stretch of same-script, same-bidi-level text that one engine shapes with one font (UAX #24 / ScriptItemize).
**Attributes:** logical start/count, script code, bidi level, RTL flag, native analysis blob (backend-opaque bytes carried to the shaper — Uniscribe's SCRIPT_ANALYSIS).
**Will become:** `SCRIPT_ITEM` (value) produced by seam `SCRIPT_ITEMIZER`

### Concept: Text Segment
**Definition:** Pre-itemization split of the paragraph into PLAIN text spans and EMOJI spans (UTS #51).
**Will become:** `TEXT_SEGMENT` (value) produced by `EMOJI_SEGMENTER`

### Concept: Shaped Item
**Definition:** The shaper's raw output for one item under one font, before line placement: glyph ids, advances, offsets, cluster map, completeness (missing-glyph count for the fallback probe).
**Will become:** `SHAPED_ITEM` (value) produced by seam `GLYPH_SHAPER`

### Concept: Break Opportunities
**Definition:** Per-character soft-break/whitespace flags (ScriptBreak-class) consumed by the wrap; breaking never occurs inside a cluster or emoji sequence regardless of flags.
**Will become:** `ARRAY [BOOLEAN]` query `soft_breaks` on `SCRIPT_ITEMIZER` (itemizer-adjacent in Uniscribe: works on the item's analysis)

### Concept: Degradation Note
**Definition:** The observable record of every never-raises rescue: fallback exhausted, unknown emoji degraded, backend error recovered, buffer retry. The API's honesty channel — `layout` is total, and this is where "what got bent" is reported.
**Will become:** `SHAPING_NOTE` (value)

### Concept: Layout Cache
**Definition:** Bounded memo of finished layouts keyed by (text, width, pixel size, font-config digest); the reason shaping is off the paint path (NFR-002/FR-012).
**Will become:** `LAYOUT_CACHE`

### Concept: Emoji Asset Catalog
**Definition:** The mapping from emoji codepoint sequence → Noto asset name/path, probing the shipped asset directory; the arbiter of "resolved" (FR-006/FR-007).
**Will become:** `EMOJI_ASSET_CATALOG` (+ generated `EMOJI_DATA_TABLES` per D-S08)

### Concept: Cairo Bridge
**Definition:** The painter-side adapter: walks a layout, draws glyph runs via simple_cairo `show_glyphs` (D-S07 API) on the run's font face at size N, blits image runs from a PNG-surface cache (`CAIRO_SURFACE.make_from_png` — resolves OQ-4 without WIC).
**Will become:** `SHAPING_CAIRO_BRIDGE` (+ `EMOJI_SURFACE_CACHE`)

## Concept Relationships

```
SIMPLE_SHAPING (facade) ── owns ──> FONT_REGISTRY ── owns ──> SHAPING_FONT*
SIMPLE_SHAPING ── owns ──> LAYOUT_CACHE ── caches ──> SHAPED_LAYOUT*
SIMPLE_SHAPING ── uses seams ──> BIDI_RESOLVER / SCRIPT_ITEMIZER / GLYPH_SHAPER / FONT_FALLBACK
SIMPLE_SHAPING ── uses ──> EMOJI_SEGMENTER ── consults ──> EMOJI_ASSET_CATALOG ── uses ──> EMOJI_DATA_TABLES
SHAPED_LAYOUT ── has-a* ──> SHAPED_LINE ── has-a* ──> SHAPED_RUN
GLYPH_RUN ── is-a ──> SHAPED_RUN ; IMAGE_RUN ── is-a ──> SHAPED_RUN
GLYPH_RUN ── references ──> SHAPING_FONT
UNISCRIBE_* ── is-a ──> (each seam) ; NULL_* ── is-a ──> (each seam) ; LIST_FONT_FALLBACK ── is-a ──> FONT_FALLBACK
SHAPING_CAIRO_BRIDGE ── reads ──> SHAPED_LAYOUT ; ── uses ──> simple_cairo (CAIRO_CONTEXT.show_glyphs [D-S07], CAIRO_SURFACE.make_from_png)
```

## Domain Rules

| Rule | Description | Enforcement |
|------|-------------|-------------|
| DR-001 | Even bidi level = LTR, odd = RTL; levels ≤ 125; paragraph level ∈ {0,1} | Postconditions on BIDI_RESOLVER.resolve; invariants on BIDI_RESULT, SCRIPT_ITEM, GLYPH_RUN |
| DR-002 | Per-line visual reorder is a permutation of that line's runs | Postcondition on BIDI_RESOLVER.reorder (occurrences of each index = 1) |
| DR-003 | Itemization covers the input exactly once, contiguously, in logical order | Postcondition on SCRIPT_ITEMIZER.itemize (model partition) |
| DR-004 | Cluster maps are monotone: non-decreasing for LTR items, non-increasing for RTL items; every cluster entry indexes a real glyph | Postcondition on GLYPH_SHAPER.shape; invariant on GLYPH_RUN/SHAPED_ITEM |
| DR-005 | Emoji never reach GLYPH_SHAPER; a resolved emoji sequence becomes exactly one IMAGE_RUN | EMOJI_SEGMENTER postcondition + type system (no emoji path into shape) |
| DR-006 | An IMAGE_RUN in a finished layout always has a resolved asset | IMAGE_RUN invariant; segmenter degrades unresolved sequences to PLAIN first |
| DR-007 | No wrap inside a cluster or emoji sequence | LINE_LAYOUT_ENGINE postcondition (break positions ∈ cluster boundaries) |
| DR-008 | Every source character lands in exactly one line | SHAPED_LAYOUT postcondition/invariant (line ranges partition the text) |
| DR-009 | Same-N: a GLYPH_RUN's positions are valid only at its font's pixel size on its font's cairo face | SHAPING_FONT/GLYPH_RUN invariant (run.font.pixel_size = layout.pixel_size); bridge precondition |
| DR-010 | Fallback never returns Void and never silently drops characters; worst case = requested font with missing-glyph boxes + SHAPING_NOTE | FONT_FALLBACK postcondition + facade note accumulation |
| DR-011 | No exception crosses a seam; native failures become retries, fallback runs, or notes | Never-raises notes + total-function postconditions (NFR-011) |
| DR-012 | One facade (fonts, SCRIPT_CACHEs, caches) per SCOOP processor; nothing separate-shared | Class notes + no `separate` types anywhere in the public API (OQ-1) |
| DR-013 | Asset tables and PNG set move in lockstep, pinned to one Unicode version | D-S08 generated tables carry the version constant; catalog invariant checks table/asset version match |

## Glossary

| Term | Definition |
|------|------------|
| Bidi level | UAX #9 embedding depth per character; parity gives direction |
| First-strong | Paragraph direction = direction of the first character with a strong bidi type |
| Cluster | Indivisible grapheme unit for shaping/wrapping (e.g., Hebrew base + niqqud) |
| Cluster map | Per-source-character index into the glyph array marking its cluster's first glyph |
| Item | Same-script, same-level stretch shaped in one call under one font (SCRIPT_ITEM) |
| Itemization | UAX #24 script segmentation (ScriptItemize) |
| Shaping | Character-to-positioned-glyph transformation (ScriptShape/ScriptPlace) |
| RGI | "Recommended for General Interchange" — the UTS #51 emoji sequence set |
| VS16 | U+FE0F variation selector forcing emoji presentation; dropped in Noto asset keys |
| ZWJ sequence | Emoji joined with U+200D forming one picture (family, flags-with-skin-tone, etc.) |
| Tofu | The missing-glyph box (wgDefault in Uniscribe) |
| Same-N rule | Shape at pixel size N and rasterize at font size N on the same face (D-S03) |
| Soft break | A legal wrap opportunity between clusters (ScriptBreak) |
| Logical order | Character storage order (as typed); visual order = paint order after reordering |
| Seam | One of the four deferred classes of D-014 behind which backends swap |
| Effecting | An implementation (non-deferred heir) of a seam |
| Note | SHAPING_NOTE degradation/diagnostic record (the never-raises audit trail) |
