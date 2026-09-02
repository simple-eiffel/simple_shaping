# SPECIFICATION: simple_shaping

## Overview

simple_shaping is the first Eiffel text-shaping library: mixed-script paragraph text (Hebrew with niqqud, Greek, Latin, emoji) in; cached, contracted, paintable layouts out — glyph runs drawn by simple_cairo via `cairo_show_glyphs` on win32 font faces, emoji as pixel-identical inline Noto PNG boxes. Four deferred seams (D-014) carry Design-by-Contract postconditions that double as the cross-backend equivalence oracle; the MVP effects three seams with OS Uniscribe (G1, flat C, zero COM, zero shipped DLLs) and owns FONT_FALLBACK as a deterministic list+probe (G2). Consumer: simple_chat's SW_CHAT_VIEW message pane (hundreds of visible lines, SCOOP, runnable folder).

This file freezes the load-bearing class texts at contract level. Bodies are Phase-4 work; `-- Phase 4` marks deliberate stubs-to-be.

## Class Specifications (principal classes in full; the rest are bound by 04/05)

### SIMPLE_SHAPING (Facade)

```eiffel
note
    description: "Facade: mixed-script paragraph text to cached, paintable SHAPED_LAYOUTs"
    author: "Larry Rix"
    design: "One instance per SCOOP processor. This facade, its FONT_REGISTRY, all %
            %SHAPING_FONTs, every SCRIPT_CACHE and HDC, and the LAYOUT_CACHE are confined %
            %to the creating processor; no feature accepts or returns separate types (OQ-1 %
            %resolved by confinement — usp10 SCRIPT_CACHE concurrency is UNVERIFIED upstream)."
    never_raises: "layout is a total function: native failures degrade to fallback runs, %
                  %missing-glyph boxes, or SHAPING_NOTEs (NFR-011). No exception escapes."
    backends: "make wires Uniscribe (G1) + LIST_FONT_FALLBACK (G2); make_with_backends injects."

class
    SIMPLE_SHAPING

inherit
    SHAPING_CONSTANTS

create
    make, make_with_backends

feature {NONE} -- Initialization

    make (a_asset_directory: READABLE_STRING_32)
            -- Production wiring: Uniscribe seams, own fallback, default fonts, empty cache.
        require
            directory_not_empty: not a_asset_directory.is_empty
        ensure
            uniscribe_wired: attached {UNISCRIBE_BIDI_RESOLVER} bidi_resolver
            own_fallback: attached {LIST_FONT_FALLBACK} font_fallback
            asset_directory_set: asset_directory.same_string_general (a_asset_directory)
            cache_empty: cache_count = 0
            defaults_present: not default_fonts.is_empty
            statistics_zero: statistics.shape_calls = 0

    make_with_backends (a_bidi: BIDI_RESOLVER; a_itemizer: SCRIPT_ITEMIZER;
                        a_shaper: GLYPH_SHAPER; a_fallback: FONT_FALLBACK;
                        a_asset_directory: READABLE_STRING_32)
            -- Injected seams (tests, stage-2 swaps).
        require
            directory_not_empty: not a_asset_directory.is_empty
        ensure
            wired: bidi_resolver = a_bidi and script_itemizer = a_itemizer and
                   glyph_shaper = a_shaper and font_fallback = a_fallback
            cache_empty: cache_count = 0

feature -- Core Operations

    layout (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER;
            a_fonts: FONT_LIST): SHAPED_LAYOUT
            -- Layout of paragraph `a_text` wrapped to `a_width_pixels` (No_wrap = 0:
            -- one unbounded line) at `a_pixel_size` under policy `a_fonts`.
            -- Pipeline: bidi (full text) -> emoji segmentation -> itemize plain spans ->
            -- fallback+shape per item -> cluster-safe greedy wrap -> per-line visual reorder.
            -- Cached by (text, width, size, fonts.digest, asset_directory): a repeat call
            -- performs zero shaping (FR-012). Benign memo effect only (CQS-declared).
        require
            width_non_negative: a_width_pixels >= 0
            size_positive: a_pixel_size > 0
            fonts_usable: not a_fonts.is_empty
        do
            -- Phase 4
        ensure
            total_function: Result /= Void
            source_kept: Result.source_text.same_string (a_text)
            parameters_kept: Result.width_pixels = a_width_pixels and Result.pixel_size = a_pixel_size
            at_least_one_line: not Result.lines_model.is_empty
            coverage: Result.covers_all_characters
            width_respected: a_width_pixels > 0 implies Result.respects_width
            cached_now: is_cached (a_text, a_width_pixels, a_pixel_size, a_fonts)
            cache_bounded_growth: cache_count <= old cache_count + 1
            hit_shapes_nothing: (old is_cached (a_text, a_width_pixels, a_pixel_size, a_fonts))
                                implies statistics.shape_calls = old statistics.shape_calls
        end

    layout_default (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER): SHAPED_LAYOUT
            -- `layout` under `default_fonts`.
        require
            width_non_negative: a_width_pixels >= 0
            size_positive: a_pixel_size > 0
        do
            -- Phase 4: Result := layout (a_text, a_width_pixels, a_pixel_size, default_fonts)
        ensure
            definition: Result /= Void
        end

feature -- Measurement

    measured_width (a_text: READABLE_STRING_32; a_pixel_size: INTEGER; a_fonts: FONT_LIST): REAL_64
            -- Unwrapped advance width of `a_text`.
        require
            size_positive: a_pixel_size > 0
            fonts_usable: not a_fonts.is_empty
        do
            -- Phase 4: first line width of layout (a_text, No_wrap, ...)
        ensure
            non_negative: Result >= 0.0
            empty_is_zero: a_text.is_empty implies Result = 0.0
        end

    line_height (a_pixel_size: INTEGER; a_fonts: FONT_LIST): REAL_64
            -- Height of one line of the primary face at `a_pixel_size` (FR-N01 sizing).
        require
            size_positive: a_pixel_size > 0
            fonts_usable: not a_fonts.is_empty
        do
            -- Phase 4
        ensure
            positive: Result > 0.0
        end

feature -- Configuration

    default_fonts: FONT_LIST
    asset_directory: IMMUTABLE_STRING_32

    set_default_fonts (a_fonts: FONT_LIST): like Current
        require fonts_usable: not a_fonts.is_empty
        do  -- Phase 4
        ensure set: default_fonts ~ a_fonts
               chaining: Result = Current
        end

    set_asset_directory (a_path: READABLE_STRING_32): like Current
        require path_not_empty: not a_path.is_empty
        do  -- Phase 4
        ensure set: asset_directory.same_string_general (a_path)
               chaining: Result = Current
               cache_cleared: cache_count = 0
        end

    set_cache_capacity (a_capacity: INTEGER): like Current
        require positive: a_capacity > 0
        do  -- Phase 4
        ensure set: cache_capacity = a_capacity
               chaining: Result = Current
        end

feature -- Status

    statistics: SHAPING_STATISTICS
    cache_count: INTEGER
        do  -- Phase 4
        ensure non_negative: Result >= 0
        end
    cache_capacity: INTEGER

    is_cached (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER;
               a_fonts: FONT_LIST): BOOLEAN
        do  -- Phase 4
        end

feature -- Commands

    clear_cache
        do  -- Phase 4
        ensure emptied: cache_count = 0
               statistics_kept: statistics.shape_calls = old statistics.shape_calls
        end

    wipe_statistics
        do  -- Phase 4
        ensure zeroed: statistics.shape_calls = 0 and statistics.cache_hits = 0
        end

feature {NONE} -- Implementation (wiring; Phase 4)

    bidi_resolver: BIDI_RESOLVER
    script_itemizer: SCRIPT_ITEMIZER
    glyph_shaper: GLYPH_SHAPER
    font_fallback: FONT_FALLBACK
    segmenter: EMOJI_SEGMENTER
    catalog: EMOJI_ASSET_CATALOG
    registry: FONT_REGISTRY
    cache: LAYOUT_CACHE
    layout_engine: LINE_LAYOUT_ENGINE

invariant
    seams_attached: bidi_resolver /= Void and script_itemizer /= Void and
                    glyph_shaper /= Void and font_fallback /= Void
    cache_bounded: cache_count <= cache_capacity
    capacity_positive: cache_capacity > 0
    defaults_usable: not default_fonts.is_empty

end
```

### The four seams (deferred; contract texts are NORMATIVE — effectings may not weaken)

```eiffel
deferred class BIDI_RESOLVER
    -- UAX #9 embedding levels + per-line visual reorder. Backends: UNISCRIBE_ (MVP, G1),
    -- NULL_ (tests), EIFFEL_ (future; promotion gate = FULL BidiTest.txt + BidiCharacterTest.txt).
feature -- Operations
    resolve (a_text: READABLE_STRING_32; a_base_direction: INTEGER): BIDI_RESULT
        require base_valid: is_valid_base_direction (a_base_direction)
        deferred
        ensure
            never_void: Result /= Void
            one_level_per_character: Result.levels_model.count = a_text.count
            paragraph_level_binary: Result.paragraph_level <= 1
            forced_ltr: a_base_direction = Direction_ltr implies Result.paragraph_level = 0
            forced_rtl: a_base_direction = Direction_rtl implies Result.paragraph_level = 1
        end
    reorder (a_levels: ARRAY [NATURAL_8]): ARRAY [INTEGER]
            -- Visual permutation of one line's positions (UAX #9 L2).
        deferred
        ensure
            same_count: Result.count = a_levels.count
            is_permutation: across 1 |..| Result.count as i all occurrences_in (Result, @i) = 1 end
            in_range: across Result as r all @r >= 1 and @r <= a_levels.count end
            ltr_identity: is_all_even (a_levels) implies is_identity (Result)
        end
end

deferred class SCRIPT_ITEMIZER
    -- UAX #24 same-script same-level items + soft-break flags. Emoji spans never arrive
    -- here (DR-005): callers pass only PLAIN segments.
feature -- Operations
    itemize (a_text: READABLE_STRING_32; a_start, a_count: INTEGER;
             a_bidi: BIDI_RESULT): ARRAYED_LIST [SCRIPT_ITEM]
        require
            range_valid: a_start >= 1 and a_count >= 0 and a_start + a_count - 1 <= a_text.count
            bidi_covers: a_bidi.levels_model.count = a_text.count
        deferred
        ensure
            never_void: Result /= Void
            empty_iff_empty: Result.is_empty = (a_count = 0)
            first_at_start: a_count > 0 implies Result.first.start_index = a_start
            contiguous: across 1 |..| (Result.count - 1) as i all
                Result [@i + 1].start_index = Result [@i].start_index + Result [@i].count end
            total_cover: a_count > 0 implies
                Result.last.start_index + Result.last.count = a_start + a_count
            items_nonempty: across Result as it all @it.count > 0 end
        end
    soft_breaks (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM): ARRAY [BOOLEAN]
        deferred
        ensure
            one_per_character: Result.count = a_item.count
            no_break_before_first: a_item.count > 0 implies not Result [1]
        end
end

deferred class GLYPH_SHAPER
    -- Characters of one item + one realized font -> SHAPED_ITEM. NEVER raises: coverage
    -- gaps are counted (probe duty for FONT_FALLBACK), failures degrade (NFR-011).
    -- NO glyph-count bound is promised: 1.5n+16 is buffer guidance only (03 A-C02).
feature -- Operations
    shape (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM; a_font: SHAPING_FONT): SHAPED_ITEM
        require
            item_in_text: a_item.start_index + a_item.count - 1 <= a_text.count
            font_ready: a_font.is_ready
        deferred
        ensure
            never_void: Result /= Void
            cluster_per_character: Result.clusters_model.count = a_item.count
            clusters_monotone_ltr: not a_item.is_rtl implies is_non_decreasing (Result.clusters_model)
            clusters_monotone_rtl: a_item.is_rtl implies is_non_increasing (Result.clusters_model)
            advances_match: Result.advances_model.count = Result.glyphs_model.count
            advances_non_negative: Result.advances_model.for_all (agent non_negative)
            complete_meaning: Result.is_complete = (Result.missing_glyph_count = 0)
            font_recorded: Result.font = a_font
        end
end

deferred class FONT_FALLBACK
    -- The rendering font for an item (G2: LIST_FONT_FALLBACK in every MVP configuration).
    -- Never Void, never a silent drop (DR-010): worst case is the requested font
    -- with missing-glyph boxes, reported via is_complete_coverage = False.
feature -- Operations
    font_for (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
              a_requested: SHAPING_FONT): FALLBACK_CHOICE
        require font_ready: a_requested.is_ready
        deferred
        ensure
            never_void: Result /= Void
            same_pixel_size: Result.font.pixel_size = a_requested.pixel_size
            same_style: Result.font.weight = a_requested.weight and
                        Result.font.is_italic = a_requested.is_italic
            no_silent_drop: Result.is_complete_coverage or Result.font = a_requested
        end
end
```

### SHAPED_RUN family (the structural emoji split, I-002/G3)

```eiffel
deferred class SHAPED_RUN
    -- One maximal same-kind stretch of a visual line. CLOSED over exactly two heirs by
    -- design intent: GLYPH_RUN (text through the shaper) and IMAGE_RUN (emoji through
    -- the asset path). Color emoji CANNOT travel the glyph path on this renderer
    -- (research-proven); the split is therefore structural, not stylistic (RISK-003).
feature -- Access
    source_start: INTEGER          -- logical range in the paragraph
    source_count: INTEGER
    advance_width: REAL_64
    height: REAL_64
    embedding_level: NATURAL_8
    is_rtl: BOOLEAN
invariant
    range_valid: source_start >= 1 and source_count > 0
    advance_non_negative: advance_width >= 0.0
    height_positive: height > 0.0
    direction_parity: is_rtl = (embedding_level \\ 2 = 1)
end

class GLYPH_RUN inherit SHAPED_RUN
    -- cairo-ready: `glyph_ids` are the physical glyph indices of `font`'s HFONT —
    -- exactly cairo_glyph_t.index space for the face from
    -- cairo_win32_font_face_create_for_logfontw_hfont (verified bridge, D-S03).
    -- Positions are shaper-authoritative at `font.pixel_size` (same-N rule, DR-009).
feature -- Access
    font: SHAPING_FONT
    glyph_ids: ARRAY [NATURAL_32]
    x_positions, y_positions: ARRAY [REAL_64]   -- run-relative, baseline origin
    cluster_map: ARRAY [INTEGER]                -- source char -> first glyph of its cluster
    script_code: INTEGER
invariant
    arrays_aligned: glyph_ids.count = x_positions.count and x_positions.count = y_positions.count
    cluster_per_source_char: cluster_map.count = source_count
    clusters_monotone: (is_rtl implies is_non_increasing (clusters_model)) and
                       (not is_rtl implies is_non_decreasing (clusters_model))
end

class IMAGE_RUN inherit SHAPED_RUN
    -- One resolved emoji sequence as a fixed image box (G3: Noto png/128,
    -- emoji_u1f916.png is U+1F916). ALWAYS resolved (DR-006): unresolvable sequences
    -- degraded to the glyph path before run construction — consumers never see a broken image.
feature -- Access
    codepoints: ARRAY [NATURAL_32]
    asset_key: IMMUTABLE_STRING_8       -- "emoji_u1f916"; VS16 dropped; ZWJ joined with '_'
    asset_path: IMMUTABLE_STRING_32     -- absolute path under the configured asset directory
    width: REAL_64                      -- box (advance_width = width for image runs)
invariant
    codepoints_nonempty: not codepoints.is_empty
    resolved: not asset_key.is_empty and not asset_path.is_empty
    box_positive: width > 0.0 and height > 0.0
    box_is_advance: advance_width = width
end
```

### SHAPING_FONT (the D-S03 bridge contract holder)

```eiffel
class SHAPING_FONT
    -- One (family, weight, style, pixel size) realization owning: LOGFONTW, HFONT
    -- selected into a private memory HDC, a Uniscribe SCRIPT_CACHE, and a lazily
    -- created cairo font face (cairo_win32_font_face_create_for_logfontw_hfont).
    -- SAME-N RULE (D-S03): shaping/placement run at `pixel_size` through the HFONT;
    -- the paint side MUST set_font_size (pixel_size) on `cairo_face` — cairo ignores
    -- LOGFONT lfHeight and sizes via the font matrix. Positions are shaper-authoritative.
    -- CONFINEMENT (DR-012): owned by exactly one FONT_REGISTRY on one processor.
create {FONT_REGISTRY}
    make
feature -- Access
    family: IMMUTABLE_STRING_32
    weight: INTEGER
    is_italic: BOOLEAN
    pixel_size: INTEGER
    ascent, descent: REAL_64            -- at pixel_size (Phase 4: TEXTMETRIC)
feature -- Status
    is_ready: BOOLEAN                   -- native handles realized
    has_cairo_face: BOOLEAN             -- face created (lazy)
feature {SHAPING_CAIRO_BRIDGE, GLYPH_SHAPER, FONT_REGISTRY} -- Native
    cairo_face: CAIRO_FONT_FACE         -- D-S07 type from simple_cairo (lazy create)
        require ready: is_ready
    -- hfont / hdc / script_cache: POINTER handles, {NONE}/{USP10_API} visibility (Phase 4)
invariant
    identity_positive: pixel_size > 0 and not family.is_empty
    line_metrics: is_ready implies (ascent > 0.0 and descent >= 0.0)
    face_needs_realization: has_cairo_face implies is_ready
end
```

### SHAPED_LAYOUT / SHAPED_LINE (results; full invariants in 05)

```eiffel
class SHAPED_LAYOUT
    -- Immutable. Total-function result: ALWAYS paintable; degradations in `notes` (NFR-011).
feature -- Access
    source_text: IMMUTABLE_STRING_32
    width_pixels, pixel_size: INTEGER
    base_direction: INTEGER             -- resolved (first-strong or forced)
    lines: ARRAYED_LIST [SHAPED_LINE]   -- model: lines_model
    notes: ARRAYED_LIST [SHAPING_NOTE]  -- model: notes_model
    total_width, total_height: REAL_64
feature -- Status
    has_notes: BOOLEAN
    covers_all_characters: BOOLEAN      -- DR-008 (definition query used by contracts)
    respects_width: BOOLEAN             -- every line fits or is flagged overflowing
invariant
    at_least_one_line: not lines_model.is_empty
    coverage_holds: covers_all_characters
    sizes_non_negative: total_width >= 0.0 and total_height >= 0.0
end

class SHAPED_LINE
    -- Runs stored in VISUAL order (post-reorder). Logical range is contiguous.
feature -- Access
    runs: ARRAYED_LIST [SHAPED_RUN]     -- model: runs_model
    source_start, source_count: INTEGER
    width, height, ascent: REAL_64
    is_overflowing: BOOLEAN             -- single unbreakable cluster/image wider than the pane
feature -- Future (FR-013; names reserved, NOT compiled this cycle)
    -- character_index_at_x (a_x: REAL_64): INTEGER
    -- x_at_character_index (a_index: INTEGER): REAL_64
invariant
    metrics_sane: height > 0.0 and ascent > 0.0 and ascent <= height
    overflow_shape: is_overflowing implies runs_model.count = 1
end
```

## Dependencies

| Dependency | Kind | Purpose | Status |
|------------|------|---------|--------|
| simple_mml | Library (simple_*) | Model queries + frame conditions in every collection contract | Exists |
| simple_cairo | Library (simple_*) | CAIRO_CONTEXT/CAIRO_SURFACE/CAIRO_FONT_FACE; `CAIRO_SURFACE.make_from_png` (emoji surfaces — OQ-4, already present) | Exists; **NEEDS D-S07** |
| **D-S07 gated addition to simple_cairo** | External dependency (separate repo, Larry's gate) | `cairo_glyph_t` array marshalling, `CAIRO_CONTEXT.show_glyphs`, `glyph_extents`, `set_font_face`, `CAIRO_FONT_FACE` wrapping the two win32 face constructors (headers already in its Clib) | **NOT this library's code**; fallback if the gate slips: temporary externals in simple_shaping's own cluster, migrated later (RISK-008) |
| OS usp10.dll / gdi32.dll | OS APIs | Uniscribe seams (G1) + font realization | Ships with Windows 10/11; zero DLLs added; Win8+ link order (Usp10.lib before gdi32.lib) → build docs |
| Noto Emoji png/128 assets | Data (Apache-2.0) | G3 emoji boxes; `emoji_u1f916.png` = U+1F916 | Copied into assets/; LICENSE-ASSETS.md ships (NFR-009) |
| Pinned Unicode data (emoji-test.txt RGI, emoji-zwj-sequences.txt; BidiTest/BidiCharacterTest oracles) | Data → generated Eiffel (D-S08) / test fixtures | EMOJI_DATA_TABLES; conformance harness | Generator in tools/; version constant pinned to asset set (DR-013) |
| simple_widgets | CONSUMER (not a dependency) | SW_PAINTER.draw_shaped_layout + SW_CHAT_VIEW adoption | Second gated repo change, coordinated at Phase 7 |

Dependency direction (D-S07 layering): simple_widgets → simple_shaping → simple_cairo → cairo.dll; simple_shaping → (usp10, gdi32).

## File Structure

As designed in 04 (src/ clusters: root facade + config/ result/ pipeline/ fonts/ emoji/(+generated/) uniscribe/ fallback/ null/ bridge/; testing/ with harness; assets/noto-emoji/png/128 + LICENSE-ASSETS.md; tools/ generator). ECF: `simple_shaping.ecf` — void_safety full, SCOOP-capable concurrency setting, library targets + test target (TEST_APP/LIB_TESTS per ecosystem test conventions), no Clib in MVP (externals are inline; a Clib appears only if LOGFONTW/SCRIPT_ITEM struct marshalling proves unreasonable over MANAGED_POINTER — Phase-4 call, recorded).

## Acceptance Demo (Phase 5/7)

`שלום 🤖 Χριστός` (the D-015 string) laid out and painted in a simple_widgets pane: Hebrew visually RTL with correct niqqud, U+1F916 as the identical Noto PNG on every machine, Greek intact; sampled BidiCharacterTest cases green; unchanged-pane repaint with statistics.shape_calls unchanged; fresh-machine run from a copied folder with zero installers and zero new DLLs.
