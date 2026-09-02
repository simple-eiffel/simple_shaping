# CLASS DESIGN: simple_shaping

OOSC2 design from the parsed requirements (01), domain model (02), and challenge verdicts (03). Contract-level only — no code this phase.

## Class Inventory

### Facade and configuration
| Class | Role | Single Responsibility |
|-------|------|----------------------|
| `SIMPLE_SHAPING` | Facade | One entry point: text + width + size + fonts → cached SHAPED_LAYOUT; owns registry, caches, seam wiring; one instance per SCOOP processor |
| `FONT_LIST` | Config value | Ordered fallback font policy (general + per-script-class prepends); value-comparable, digestable (cache key part) |
| `SHAPING_STATISTICS` | Data value | Observability counters (shape calls, cache hits/misses, fallback probes, notes emitted) — FR-N02/FR-012 acceptance |

### Result value classes (immutable after creation)
| Class | Role | Single Responsibility |
|-------|------|----------------------|
| `SHAPED_LAYOUT` | Data | One paragraph's finished layout: lines, total size, base direction, notes |
| `SHAPED_LINE` | Data | One visual line: runs in visual order, metrics, logical source range; reserved hit-testing home |
| `SHAPED_RUN` | Deferred data | What every run is: logical range, advance width, direction, height |
| `GLYPH_RUN` | Data (heir) | Positioned glyphs of one font/one direction, cairo-ready (ids + x/y + cluster map) |
| `IMAGE_RUN` | Data (heir) | One resolved emoji sequence as a fixed image box (asset key + path + box) |
| `SHAPING_NOTE` | Data | One degradation/diagnostic record (code, message, logical range) |

### Pipeline value classes (internal currency, exported to seams and tests)
| Class | Role | Single Responsibility |
|-------|------|----------------------|
| `BIDI_RESULT` | Data | Levels per character + paragraph level + resolved base direction |
| `TEXT_SEGMENT` | Data | One PLAIN or EMOJI span from segmentation (emoji: codepoints + asset key/path) |
| `SCRIPT_ITEM` | Data | One same-script same-level stretch + backend-opaque analysis bytes |
| `SHAPED_ITEM` | Data | Shaper raw output for one item: glyphs, advances, offsets, cluster map, missing-glyph count |

### The four seams (C-006/D-014) and their effectings
| Class | Role | Single Responsibility |
|-------|------|----------------------|
| `BIDI_RESOLVER` | Deferred seam | UAX #9: `resolve` (levels) + `reorder` (per-line visual permutation) |
| `SCRIPT_ITEMIZER` | Deferred seam | UAX #24: `itemize` (+ `soft_breaks` per item — A-C07) |
| `GLYPH_SHAPER` | Deferred seam | Characters of one item + one font → SHAPED_ITEM (never raises; reports missing glyphs) |
| `FONT_FALLBACK` | Deferred seam | Pick the rendering font for an item (never Void, never silent drops) |
| `UNISCRIBE_BIDI_RESOLVER` | Effecting | ScriptItemize levels + ScriptLayout reorder (MVP, G1) |
| `UNISCRIBE_SCRIPT_ITEMIZER` | Effecting | ScriptItemize items + ScriptBreak soft breaks (MVP, G1) |
| `UNISCRIBE_GLYPH_SHAPER` | Effecting | ScriptShape + ScriptPlace against SHAPING_FONT's HDC/SCRIPT_CACHE (MVP, G1) |
| `LIST_FONT_FALLBACK` | Effecting | G2: configured FONT_LIST walk + shaper-probe + per-(script,font) coverage cache |
| `NULL_BIDI_RESOLVER` | Test double | All-LTR level 0; identity reorder — headless layout tests |
| `NULL_SCRIPT_ITEMIZER` | Test double | One Latin item per segment; breaks at ASCII spaces — deterministic wrap tests |
| `NULL_GLYPH_SHAPER` | Test double | 1 glyph/char, id = codepoint, fixed advance = pixel_size/2 — metric-predictable |
| `NULL_FONT_FALLBACK` | Test double | Always the requested font |
| `FALLBACK_CHOICE` | Data value | Seam-4 result pair: chosen font + coverage-completeness flag (keeps the seam CQS-clean; see 05) |
| *(stage 2, named now, NOT designed now)* `DIRECTWRITE_BIDI_RESOLVER`, `DIRECTWRITE_SCRIPT_ITEMIZER`, `DIRECTWRITE_GLYPH_SHAPER`, `DIRECTWRITE_FONT_FALLBACK`, `EIFFEL_BIDI_RESOLVER`, `EIFFEL_SCRIPT_ITEMIZER` | Future effectings | Slots proving the seams are seams (D-S02/D-S06); zero MVP code |

### Emoji subsystem (pure Eiffel from day one)
| Class | Role | Single Responsibility |
|-------|------|----------------------|
| `EMOJI_SEGMENTER` | Engine | UTS #51 scan: text + levels → TEXT_SEGMENTs; owns the FR-007 degradation ladder (A-C06) |
| `EMOJI_ASSET_CATALOG` | Engine | Codepoint sequence → Noto asset name/path; probes asset directory; caches resolution |
| `EMOJI_DATA_TABLES` | Generated data | Pinned UTS #51 tables (RGI sequences, Extended_Pictographic, VS16/ZWJ properties) + Unicode version constant (D-S08) |

### Fonts, layout, cache
| Class | Role | Single Responsibility |
|-------|------|----------------------|
| `SHAPING_FONT` | Resource handle | One (family, weight, style, pixel size) realization: LOGFONTW + HFONT + memory HDC + SCRIPT_CACHE + lazy cairo face; enforces same-N (DR-009) |
| `FONT_REGISTRY` | Engine | Creates/caches/disposes SHAPING_FONTs for one facade (one processor — DR-012) |
| `LINE_LAYOUT_ENGINE` | Engine | Greedy cluster-safe wrap + per-line reorder + metrics → SHAPED_LINEs (testable headless via NULL doubles) |
| `LAYOUT_CACHE` | Engine | Bounded LRU of SHAPED_LAYOUTs keyed by (text, width, size, font digest) |

### Paint bridge (distinct cluster; only part that touches simple_cairo)
| Class | Role | Single Responsibility |
|-------|------|----------------------|
| `SHAPING_CAIRO_BRIDGE` | Adapter | Walk a layout: glyph runs → `CAIRO_CONTEXT.show_glyphs` (D-S07) on the run's face at size N; image runs → surface blit |
| `EMOJI_SURFACE_CACHE` | Engine | Asset path → cached CAIRO_SURFACE (`make_from_png`) — OQ-4 resolution, zero WIC |

### Native boundary (implementation layer, {NONE}-ish exposure)
| Class | Role | Single Responsibility |
|-------|------|----------------------|
| `USP10_API` | Externals | ScriptItemize/Shape/Place/Layout/Break/GetFontProperties/FreeCache externals + struct marshalling; every call checked, never raises (NFR-011) |
| `GDI32_API` | Externals | CreateFontIndirectW/SelectObject/CreateCompatibleDC/DeleteObject/DeleteDC + LOGFONTW marshalling; checked, never raises |
| `SHAPING_CONSTANTS` | Constants mixin | Direction codes, script-class codes, note codes, limits (Max_bidi_level = 125), No_wrap = 0 |

### Testing cluster (not shipped)
| Class | Role | Single Responsibility |
|-------|------|----------------------|
| `BIDI_CONFORMANCE_HARNESS` | Test engine | Parse/run BidiCharacterTest.txt (+BidiTest.txt) against any BIDI_RESOLVER; MVP samples, Phase-5 full run, pure-Eiffel promotion gate (I-003/NFR-008) |

**Count: 39 designed classes** — 38 in src/ (37 written + 1 generated `EMOJI_DATA_TABLES`) + 1 testing-cluster harness; plus 6 future effectings named only (zero MVP design).

## Facade Design: SIMPLE_SHAPING

**Purpose:** The single entry point (Single Choice: seam wiring, font realization, caching decided here and nowhere else).
**Hides:** all engines, the registry, the cache, the native layer. Consumers see: FONT_LIST in, SHAPED_LAYOUT out, bridge to paint.

```eiffel
class SIMPLE_SHAPING

create
    make,                    -- Uniscribe effectings (G1) + LIST_FONT_FALLBACK (G2): the production wiring
    make_with_backends       -- injected seams (tests, stage-2 swaps)

feature -- Core Operations

    layout (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER;
            a_fonts: FONT_LIST): SHAPED_LAYOUT
            -- Complete layout of paragraph `a_text` wrapped to `a_width_pixels`
            -- (No_wrap = 0 means single unbounded line) at `a_pixel_size`,
            -- under fallback policy `a_fonts`. Total function: always paintable;
            -- degradations surface as Result.notes. Cached (benign memo effect).

    layout_default (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER): SHAPED_LAYOUT
            -- `layout` under `default_fonts`.

feature -- Measurement (FR-011 conveniences)

    measured_width (a_text: READABLE_STRING_32; a_pixel_size: INTEGER; a_fonts: FONT_LIST): REAL_64
            -- Unwrapped advance width of `a_text` (layout at No_wrap, first line's width).

    line_height (a_pixel_size: INTEGER; a_fonts: FONT_LIST): REAL_64
            -- Height of one line of `a_fonts`'s primary face at `a_pixel_size`.

feature -- Configuration

    default_fonts: FONT_LIST
    set_default_fonts (a_fonts: FONT_LIST): like Current
    set_asset_directory (a_path: READABLE_STRING_32): like Current
            -- Where the Noto png/128 assets live (G3).
    set_cache_capacity (a_capacity: INTEGER): like Current

feature -- Status

    statistics: SHAPING_STATISTICS      -- shape calls, cache hits/misses, probes, notes (FR-N02)
    cache_count: INTEGER
    asset_directory: IMMUTABLE_STRING_32

feature -- Commands

    clear_cache
    wipe_statistics
```

**SCOOP note (DR-012, OQ-1):** class note reads: "One instance per processor. This facade, its fonts, its SCRIPT_CACHEs, and its layout cache are confined to the creating processor; no feature accepts or returns `separate` types. Create one facade per processor that shapes."

## Engine Designs (responsibilities and collaborations)

### LINE_LAYOUT_ENGINE
Input: text, BIDI_RESULT, TEXT_SEGMENTs, per-item SHAPED_ITEMs + soft breaks, width, pixel size. Output: SHAPED_LINEs.
Algorithm (contract-level): greedy accumulate runs; break only at soft-break positions that are also cluster boundaries and never inside an emoji segment (DR-007); a single unbreakable cluster/image wider than the width overflows its own line (flagged); per finished line call `BIDI_RESOLVER.reorder` on the line's run levels to fix visual order (DR-002); compute line ascent/height as max over runs' fonts (glyph) and boxes (image).
Testable headless with NULL doubles (UC-005) — the reason it is a class, not facade-private code.

### FONT_REGISTRY
`font (a_family; a_weight, a_style_flags, a_pixel_size): SHAPING_FONT` — create-on-first-use, cache by key, dispose all on facade disposal. Owns native lifetime (D-S03 implication: HFONT/HDC lifetime lives here, not in value classes).

### LIST_FONT_FALLBACK (G2)
Collaborates with a GLYPH_SHAPER probe (constructor-injected) implementing the Learn "Using Font Fallback" procedure: try requested font; on missing glyphs walk `FONT_LIST.families_for (script_class)`; cache verdicts per (script_class \| codepoint-range, family). Last resort: requested font + note (DR-010, UC-002).

### EMOJI_SEGMENTER + EMOJI_ASSET_CATALOG (G3)
Segmenter scans codepoints with EMOJI_DATA_TABLES (RGI longest-match, VS16, ZWJ); candidate sequence → catalog probe: full-sequence asset (`emoji_u1f469_200d_1f4bb.png` style, VS16 dropped) else per-codepoint assets else DEGRADE to PLAIN (A-C06) + note. Output segments carry resolved keys/paths only.

### LAYOUT_CACHE
Key = digest of (text, width_pixels, pixel_size, fonts.digest, asset_directory). Value = SHAPED_LAYOUT (immutable → safely shared within the processor). Bounded LRU (`capacity`, default 512 — a few MB at chat sizes, NFR-003).

### SHAPING_CAIRO_BRIDGE + EMOJI_SURFACE_CACHE
`draw_layout (a_context: CAIRO_CONTEXT; a_layout: SHAPED_LAYOUT; a_x, a_y: REAL_64)` and `draw_line (...)`: glyph runs — `a_context.set_font_face (run.font.cairo_face)` + `set_font_size (run.font.pixel_size)` (same-N, DR-009) + `show_glyphs (ids, xs, ys)` [all three context features are the D-S07 gated additions]; image runs — `EMOJI_SURFACE_CACHE.surface (run.asset_path)` + `set_source_surface` + `paint` (existing simple_cairo API). Consumer never touches glyph arrays.

## Inheritance Hierarchies

```
                SHAPED_RUN (deferred)                    each seam (deferred), e.g.:
                     │                                        BIDI_RESOLVER
              ┌──────┴──────┐                          ┌──────────┼─────────────┐
          GLYPH_RUN     IMAGE_RUN                UNISCRIBE_   NULL_        [EIFFEL_ / DIRECTWRITE_]
                                                 BIDI_RESOLVER BIDI_RESOLVER   (future)
```

**Inheritance Justification:**
| Child | Parent | IS-A Valid? | Liskov OK? |
|-------|--------|-------------|------------|
| GLYPH_RUN | SHAPED_RUN | A glyph run IS a paintable run of the line | YES — satisfies all SHAPED_RUN queries; adds glyph data |
| IMAGE_RUN | SHAPED_RUN | An emoji image box IS a paintable run of the line | YES — same |
| UNISCRIBE_* / NULL_* / future * | each seam | Each IS a resolver/itemizer/shaper/fallback | YES — effectings may only KEEP or STRENGTHEN ensure, KEEP or WEAKEN require (contracts are the cross-backend oracle, I-001) |
| SIMPLE_SHAPING, engines | SHAPING_CONSTANTS (mixin) | Constants access | Conventional Eiffel constants mixin (non-conforming use acceptable) |

Emoji segmentation in the type system: `SHAPED_RUN` is closed over exactly two heirs by design intent (documented in its note); consumers dispatch via `attached {GLYPH_RUN}`/`attached {IMAGE_RUN}` object tests or use the bridge which does it for them. Emoji CANNOT leak into GLYPH_SHAPER because segmentation happens before itemization and only TEXT_SEGMENTs with `is_plain` reach the itemizer (DR-005 — enforced by the itemizer call's precondition).

## Generic Classes

| Class | Type Parameter | Constraint | Purpose |
|-------|----------------|------------|---------|
| — | — | — | No genericity needed: every collection is concretely typed (runs, lines, notes, items). LAYOUT_CACHE is concrete (STRING_8 digest → SHAPED_LAYOUT); generalizing it would duplicate simple_* cache work without a second client. Recorded deliberately (OOSC2 rule 7 considered and declined). |

## Class Diagram (principal collaboration)

```
┌────────────────────────────────────────────────────────────────────┐
│                        SIMPLE_SHAPING  (facade)                    │
│  layout / layout_default / measured_width / config / statistics    │
├──────┬──────────────┬──────────────┬──────────────┬────────────────┤
       │              │              │              │
       ▼              ▼              ▼              ▼
 BIDI_RESOLVER  EMOJI_SEGMENTER  SCRIPT_ITEMIZER  GLYPH_SHAPER ◄── FONT_FALLBACK
 (seam 1)        │ EMOJI_ASSET_  (seam 2)         (seam 3)          (seam 4, probes via shaper)
       │         │ CATALOG            │              │                   │
       │         ▼                    │              │                   ▼
       │    EMOJI_DATA_TABLES        │              │              FONT_LIST
       └────────────┬────────────────┴──────────────┘
                    ▼
           LINE_LAYOUT_ENGINE ──────► SHAPED_LAYOUT ─► SHAPED_LINE ─► SHAPED_RUN
                    │                      ▲                            (GLYPH_RUN │ IMAGE_RUN)
                    │                      │ cached by                        │ font
              FONT_REGISTRY          LAYOUT_CACHE                             ▼
                    │                                                  SHAPING_FONT
                    ▼                                                  (HFONT+SCRIPT_CACHE
              USP10_API / GDI32_API  (never-raises native boundary)     +cairo face, same-N)

  paint side:  SHAPING_CAIRO_BRIDGE + EMOJI_SURFACE_CACHE ──► simple_cairo
               (show_glyphs [D-S07] / make_from_png [exists])
```

## File Structure (design intent; final in 07)

```
src/
├── simple_shaping.e                 (facade)
├── shaping_constants.e
├── config/    font_list.e  shaping_statistics.e
├── result/    shaped_layout.e  shaped_line.e  shaped_run.e  glyph_run.e  image_run.e  shaping_note.e
├── pipeline/  bidi_result.e  text_segment.e  script_item.e  shaped_item.e
│              bidi_resolver.e  script_itemizer.e  glyph_shaper.e  font_fallback.e   (the four seams)
│              line_layout_engine.e  layout_cache.e
├── fonts/     shaping_font.e  font_registry.e
├── emoji/     emoji_segmenter.e  emoji_asset_catalog.e
│   └── generated/  emoji_data_tables.e        (D-S08 generator output; generator script in tools/)
├── uniscribe/ uniscribe_bidi_resolver.e  uniscribe_script_itemizer.e  uniscribe_glyph_shaper.e
│              usp10_api.e  gdi32_api.e
├── fallback/  list_font_fallback.e
├── null/      null_bidi_resolver.e  null_script_itemizer.e  null_glyph_shaper.e  null_font_fallback.e
└── bridge/    shaping_cairo_bridge.e  emoji_surface_cache.e
testing/       bidi_conformance_harness.e  + test sets (Phase 1 skeletons)
assets/        noto-emoji/png/128/*.png  LICENSE-ASSETS.md   (G3)
tools/         generate_emoji_tables (script; pinned Unicode version)
```
