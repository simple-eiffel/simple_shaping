# CONTRACT DESIGN: simple_shaping

Contracts follow the completeness rule: every postcondition answers WHAT changed, HOW (vs `old`), and WHAT DID NOT (frame, via MML model equality `|=|` where models exist). Value classes are immutable — their "frame" is the invariant itself. Innovation I-001 is enforced here: seam postconditions ARE the cross-backend equivalence oracle, so effectings may strengthen but never weaken them.

## MML Model Queries

Every collection-bearing class exposes a model (simple_mml):

| Class | Attribute | Model Query | MML Type |
|-------|-----------|-------------|----------|
| SHAPED_LAYOUT | lines | `lines_model` | MML_SEQUENCE [SHAPED_LINE] |
| SHAPED_LAYOUT | notes | `notes_model` | MML_SEQUENCE [SHAPING_NOTE] |
| SHAPED_LINE | runs | `runs_model` | MML_SEQUENCE [SHAPED_RUN] |
| GLYPH_RUN | glyph ids | `glyphs_model` | MML_SEQUENCE [NATURAL_32] |
| GLYPH_RUN | cluster map | `clusters_model` | MML_SEQUENCE [INTEGER] |
| IMAGE_RUN | codepoints | `codepoints_model` | MML_SEQUENCE [NATURAL_32] |
| BIDI_RESULT | levels | `levels_model` | MML_SEQUENCE [NATURAL_8] |
| SHAPED_ITEM | glyphs/advances/clusters | `glyphs_model` / `advances_model` / `clusters_model` | MML_SEQUENCE |
| FONT_LIST | general families | `families_model` | MML_SEQUENCE [IMMUTABLE_STRING_32] |
| FONT_LIST | per-script prepends | `script_families_model` | MML_MAP [INTEGER, MML_SEQUENCE [IMMUTABLE_STRING_32]] |
| FONT_REGISTRY | realized fonts | `fonts_model` | MML_MAP [IMMUTABLE_STRING_32, SHAPING_FONT] |
| LAYOUT_CACHE | entries | `cache_model` | MML_MAP [IMMUTABLE_STRING_8, SHAPED_LAYOUT] |
| EMOJI_ASSET_CATALOG | resolved keys | `resolved_model` | MML_MAP [IMMUTABLE_STRING_8, IMMUTABLE_STRING_32] |
| EMOJI_SURFACE_CACHE | decoded surfaces | `surfaces_model` | MML_MAP [IMMUTABLE_STRING_32, CAIRO_SURFACE] |
| SHAPING_STATISTICS | counters | (scalar attributes; no collection) | — |

## Concurrency Contracts (OQ-1 resolution — DR-012)

Not everything statable in assertions; the statable part IS stated, the rest is a binding class note:

- **Note on SIMPLE_SHAPING, SHAPING_FONT, FONT_REGISTRY, LAYOUT_CACHE, UNISCRIBE_*:** "Confined to the creating processor. SCRIPT_CACHE thread-safety under concurrent use is UNVERIFIED in Microsoft's documentation (research OQ-1); this library therefore never shares a font, cache, or native handle across processors. Public features neither accept nor return `separate` types."
- **Statable and stated:** `FONT_REGISTRY` invariant `fonts_are_owned: across fonts_model.domain as k all attached fonts_model [k.item] end` plus creation ensure `registry_empty: fonts_model.is_empty`; `SHAPING_FONT.make` ensure `owner_registered: registry = a_registry` (back-pointer fixes ownership at birth); facade creation ensure wires all seams to freshly created (non-shared) effectings.
- **Design consequence:** SW_CHAT_VIEW shapes on the UI processor; a hypothetical background shaper would create its OWN facade. Nothing in this library needs `separate` to compile under SCOOP (it is SCOOP-compatible by confinement, not by sharing).

## Never-Raises Boundary (NFR-011 — DR-011)

Pattern specified for USP10_API/GDI32_API and every effecting: native calls return HRESULT/handles; wrappers CHECK and convert:
- `E_OUTOFMEMORY` from ScriptShape → grow buffer (start 3n//2+16 per A-C02 guidance) and retry, bounded (3 attempts), then degrade;
- `E_PENDING`/`USP_E_SCRIPT_NOT_IN_FONT` → defined probe outcomes (NOT errors): select HFONT into HDC and retry / report missing coverage to FONT_FALLBACK;
- any other failure → empty-but-valid result + SHAPING_NOTE (`Note_backend_error_recovered`).
Contracts carry it as: (a) every seam query ensures `Result /= Void` with valid-model postconditions; (b) note `never_raises: "No exception propagates from this feature; failures degrade per NFR-011"` on each seam feature; (c) facade `layout` is TOTAL (below). No `rescue`-based control flow is admitted in the design (rescue may appear only as a last-ditch note-and-degrade guard inside effectings, never as logic).

## Class Contracts

### SIMPLE_SHAPING (facade)

Creation:
```eiffel
make (a_asset_directory: READABLE_STRING_32)
    ensure
        uniscribe_wired: attached {UNISCRIBE_BIDI_RESOLVER} bidi_resolver     -- G1
        own_fallback: attached {LIST_FONT_FALLBACK} font_fallback             -- G2
        asset_directory_set: asset_directory.same_string_general (a_asset_directory)
        cache_empty: cache_count = 0
        defaults_present: not default_fonts.is_empty
        statistics_zero: statistics.shape_calls = 0

make_with_backends (a_bidi: BIDI_RESOLVER; a_itemizer: SCRIPT_ITEMIZER;
                    a_shaper: GLYPH_SHAPER; a_fallback: FONT_FALLBACK;
                    a_asset_directory: READABLE_STRING_32)
    ensure
        wired: bidi_resolver = a_bidi and script_itemizer = a_itemizer
               and glyph_shaper = a_shaper and font_fallback = a_fallback
        cache_empty: cache_count = 0
```

The core query (total function; benign memo effect — see CQS note):
```eiffel
layout (a_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER;
        a_fonts: FONT_LIST): SHAPED_LAYOUT
    require
        width_non_negative: a_width_pixels >= 0        -- 0 = No_wrap
        size_positive: a_pixel_size > 0
        fonts_usable: not a_fonts.is_empty
    ensure
        total_function: Result /= Void                  -- never raises (NFR-011)
        source_kept: Result.source_text.same_string (a_text)
        parameters_kept: Result.width_pixels = a_width_pixels and Result.pixel_size = a_pixel_size
        at_least_one_line: not Result.lines_model.is_empty          -- FR-N01: even for empty text
        coverage: Result.covers_all_characters                      -- DR-008 (defined on SHAPED_LAYOUT)
        width_respected: a_width_pixels > 0 implies Result.respects_width  -- lines fit or are flagged overflowing
        cached_now: is_cached (a_text, a_width_pixels, a_pixel_size, a_fonts)
        cache_grows_by_at_most_one: cache_count <= old cache_count + 1
        deterministic: (old is_cached (a_text, a_width_pixels, a_pixel_size, a_fonts))
                       implies statistics.shape_calls = old statistics.shape_calls   -- FR-012: cache hit shapes nothing
```

Configuration commands (fluent, cairo_context house style):
```eiffel
set_default_fonts (a_fonts: FONT_LIST): like Current
    require fonts_usable: not a_fonts.is_empty
    ensure  set: default_fonts ~ a_fonts
            chaining: Result = Current
            cache_invalidated_only_if_changed: (old default_fonts ~ a_fonts) implies cache_count = old cache_count

set_asset_directory (a_path: READABLE_STRING_32): like Current
    require path_not_empty: not a_path.is_empty
    ensure  set: asset_directory.same_string_general (a_path)
            chaining: Result = Current
            cache_cleared: cache_count = 0        -- assets are part of layout identity

clear_cache
    ensure emptied: cache_count = 0
           statistics_kept: statistics.shape_calls = old statistics.shape_calls
```

Invariant:
```eiffel
invariant
    seams_attached: bidi_resolver /= Void and script_itemizer /= Void
                    and glyph_shaper /= Void and font_fallback /= Void
    cache_bounded: cache_count <= cache_capacity
    capacity_positive: cache_capacity > 0
    defaults_usable: not default_fonts.is_empty
```

### BIDI_RESOLVER (seam 1 — the oracle contracts, DR-001/DR-002)

```eiffel
resolve (a_text: READABLE_STRING_32; a_base_direction: INTEGER): BIDI_RESULT
        -- Embedding levels for `a_text`; base Direction_auto (first-strong), _ltr, or _rtl.
    require
        base_valid: is_valid_base_direction (a_base_direction)
    ensure
        never_void: Result /= Void
        one_level_per_character: Result.levels_model.count = a_text.count
        levels_bounded: Result.levels_model.for_all (agent (i: INTEGER; l: NATURAL_8): BOOLEAN
                            do Result := l <= Max_bidi_level end)
        paragraph_level_binary: Result.paragraph_level <= 1
        forced_base_honored: a_base_direction = Direction_ltr implies Result.paragraph_level = 0
        forced_base_honored_rtl: a_base_direction = Direction_rtl implies Result.paragraph_level = 1
        empty_text_ltr_default: a_text.is_empty implies Result.levels_model.is_empty
    -- note: even level = LTR, odd = RTL (UAX #9); full conformance = harness (Phase 5), not assertable here

reorder (a_levels: ARRAY [NATURAL_8]): ARRAY [INTEGER]
        -- Visual order of `a_levels.count` logical positions (UAX #9 L2) for ONE line.
    ensure
        same_count: Result.count = a_levels.count
        is_permutation: across 1 |..| Result.count as i all
                            occurrences_in (Result, i.item) = 1 end          -- DR-002
        indices_in_range: across Result as r all r.item >= 1 and r.item <= a_levels.count end
        all_even_is_identity: is_all_even (a_levels) implies is_identity (Result)
```

`UNISCRIBE_BIDI_RESOLVER` (ScriptItemize levels; ScriptLayout for reorder) and future `EIFFEL_BIDI_RESOLVER` add NOTHING to these signatures — only the harness distinguishes them (I-001/I-003). `NULL_BIDI_RESOLVER` ensures additionally `all_zero: Result.paragraph_level = 0`.

### SCRIPT_ITEMIZER (seam 2 — DR-003)

```eiffel
itemize (a_text: READABLE_STRING_32; a_start, a_count: INTEGER;
         a_bidi: BIDI_RESULT): ARRAYED_LIST [SCRIPT_ITEM]
        -- Same-script, same-level items covering a_text[a_start .. a_start+a_count-1]
        -- (a PLAIN segment — emoji spans never arrive here, DR-005).
    require
        range_valid: a_start >= 1 and a_count >= 0 and a_start + a_count - 1 <= a_text.count
        bidi_covers: a_bidi.levels_model.count = a_text.count
    ensure
        never_void: Result /= Void
        empty_iff_empty: Result.is_empty = (a_count = 0)
        first_at_start: a_count > 0 implies Result.first.start_index = a_start
        contiguous_cover: across 1 |..| (Result.count - 1) as i all
                              Result [i.item + 1].start_index
                              = Result [i.item].start_index + Result [i.item].count end
        total_cover: a_count > 0 implies
                     Result.last.start_index + Result.last.count = a_start + a_count   -- exactly once
        items_nonempty: across Result as it all it.item.count > 0 end
        levels_carried: across Result as it all
                            it.item.embedding_level = a_bidi.levels_model [it.item.start_index] end

soft_breaks (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM): ARRAY [BOOLEAN]
        -- True at i = wrap legally allowed BEFORE the item's i-th character (A-C07).
    ensure
        one_per_character: Result.count = a_item.count
        never_break_before_first: a_item.count > 0 implies not Result [1]
```

### GLYPH_SHAPER (seam 3 — DR-004, A-C02)

```eiffel
shape (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM; a_font: SHAPING_FONT): SHAPED_ITEM
        -- Shape + place the item's characters under `a_font` at the font's pixel size.
        -- NEVER raises; coverage gaps are reported, not thrown (probe duty for seam 4).
    require
        item_in_text: a_item.start_index + a_item.count - 1 <= a_text.count
        font_ready: a_font.is_ready
    ensure
        never_void: Result /= Void
        cluster_per_character: Result.clusters_model.count = a_item.count
        clusters_reference_real_glyphs: across Result.clusters_model as c all
                                            c.item >= 1 and c.item <= Result.glyphs_model.count.max (1) end
        clusters_monotone_ltr: not a_item.is_rtl implies is_non_decreasing (Result.clusters_model)
        clusters_monotone_rtl: a_item.is_rtl implies is_non_increasing (Result.clusters_model)   -- per ScriptShape doc
        advances_match_glyphs: Result.advances_model.count = Result.glyphs_model.count
        advances_non_negative: Result.advances_model.for_all (agent non_negative)
        missing_counted: Result.missing_glyph_count >= 0
        complete_means_none_missing: Result.is_complete = (Result.missing_glyph_count = 0)
        font_recorded: Result.font = a_font
    -- NO glyph-count upper bound: 1.5n+16 is buffer guidance, not an invariant (03 A-C02)
```

### FONT_FALLBACK (seam 4 — DR-010, G2)

```eiffel
font_for (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM;
          a_requested: SHAPING_FONT): FALLBACK_CHOICE
        -- The font this item should render with: `a_requested` if it covers the item,
        -- else the first covering font from the configured policy,
        -- else `a_requested` again with is_complete_coverage = False (something ALWAYS renders).
    require
        font_ready: a_requested.is_ready
    ensure
        never_void: Result /= Void
        font_attached: Result.font /= Void
        same_pixel_size: Result.font.pixel_size = a_requested.pixel_size
        same_style: Result.font.weight = a_requested.weight and Result.font.is_italic = a_requested.is_italic
        no_silent_drop: Result.is_complete_coverage or Result.font = a_requested
            -- incomplete coverage only ever falls back to the REQUESTED font (tofu boxes + note upstream)
```
(`FALLBACK_CHOICE` is a two-field value: `font: SHAPING_FONT`, `is_complete_coverage: BOOLEAN` — added to the inventory as a micro-value of seam 4; keeps the seam CQS-clean instead of an out-parameter.)

`LIST_FONT_FALLBACK` additional creation contract: `make (a_fonts: FONT_LIST; a_probe: GLYPH_SHAPER; a_registry: FONT_REGISTRY)` ensure `policy_kept: fonts ~ a_fonts`; its probe cache invariant: `cache_only_grows: verdicts are write-once per (script_class, family)` (stated as note + model frame conditions on the probing feature).

### EMOJI_SEGMENTER (DR-005/DR-006, G3, A-C06)

```eiffel
segment (a_text: READABLE_STRING_32; a_bidi: BIDI_RESULT): ARRAYED_LIST [TEXT_SEGMENT]
    require
        bidi_matches: a_bidi.levels_model.count = a_text.count
    ensure
        never_void: Result /= Void
        partition: segments_partition (Result, a_text.count)     -- contiguous, exactly-once, in order
        emoji_resolved: across Result as s all
                            s.item.is_emoji implies s.item.has_resolved_asset end   -- DR-006
        plain_has_no_full_rgi_sequence: -- no detectable+resolvable emoji left unlifted (note-level; harness-tested)
        empty_text: a_text.is_empty implies Result.is_empty
```

### EMOJI_ASSET_CATALOG

```eiffel
asset_key (a_codepoints: ARRAY [NATURAL_32]): STRING_8
        -- Noto naming: hex codepoints joined by '_', VS16 (FE0F) dropped: [1F916] -> "emoji_u1f916".
    require nonempty: not a_codepoints.is_empty
    ensure  noto_prefix: Result.starts_with ("emoji_u")
            no_vs16: not Result.has_substring ("fe0f")
            deterministic: Result ~ asset_key (a_codepoints)

has_asset (a_codepoints: ARRAY [NATURAL_32]): BOOLEAN
asset_path (a_codepoints: ARRAY [NATURAL_32]): IMMUTABLE_STRING_32
    require known: has_asset (a_codepoints)
    ensure  under_directory: Result.starts_with (directory)
            is_png: Result.ends_with (".png")
invariant
    tables_and_assets_pinned_together: data_tables.unicode_version ~ expected_unicode_version  -- DR-013
```

### Value-class invariants (immutability = the frame)

```eiffel
class SHAPED_LAYOUT
invariant
    at_least_one_line: not lines_model.is_empty                          -- FR-N01
    lines_partition_text: covers_all_characters                          -- DR-008
    sizes_non_negative: total_width >= 0 and total_height >= 0
    height_is_sum: total_height = sum_of_line_heights
    parameters_positive: pixel_size > 0 and width_pixels >= 0
    notes_are_facts: notes_model.count >= 0                              -- observability channel (NFR-011)

class SHAPED_LINE
invariant
    runs_visual_order: True  -- BY CONSTRUCTION: runs stored post-reorder (note; permutation checked at build, DR-002)
    metrics_sane: height > 0 and ascent > 0 and ascent <= height
    width_is_run_sum: width = sum_of_run_advances
    source_range_valid: source_start >= 1 and source_count >= 0
    overflow_only_when_unbreakable: is_overflowing implies runs_model.count = 1  -- single cluster/image wider than pane

class GLYPH_RUN  (heir of SHAPED_RUN)
invariant
    arrays_aligned: glyphs_model.count = x_positions.count and x_positions.count = y_positions.count
    cluster_per_source_char: clusters_model.count = source_count
    clusters_monotone: is_rtl implies is_non_increasing (clusters_model)
                       and (not is_rtl implies is_non_decreasing (clusters_model))   -- DR-004
    advance_non_negative: advance_width >= 0
    same_n_rule: font.pixel_size = pixel_size                            -- DR-009: positions valid only at this size

class IMAGE_RUN  (heir of SHAPED_RUN)
invariant
    codepoints_nonempty: not codepoints_model.is_empty
    asset_resolved: not asset_key.is_empty and not asset_path.is_empty   -- DR-006 (A-C06: no broken images exist)
    box_positive: width > 0 and height > 0

class BIDI_RESULT
invariant
    paragraph_level_binary: paragraph_level <= 1
    levels_bounded: levels_model.for_all (agent bounded_by_max_level)     -- DR-001

class SCRIPT_ITEM
invariant
    range_valid: start_index >= 1 and count > 0
    direction_from_level: is_rtl = (embedding_level \\ 2 = 1)             -- DR-001 parity

class SHAPING_FONT
invariant
    identity_positive: pixel_size > 0 and not family.is_empty
    ready_means_realized: is_ready implies (has_hfont and has_hdc)        -- native handles live
    cairo_face_lazy: has_cairo_face implies is_ready                     -- face only from a realized font (D-S03)

class FONT_LIST
invariant
    not_empty_in_use: True  -- emptiness legal only pre-configuration; facade preconditions demand non-empty
    digest_is_value_based: (Current ~ other) implies (digest ~ other.digest)   -- FR-N03 (stated as note + test)

class LAYOUT_CACHE
invariant
    bounded: cache_model.count <= capacity
    capacity_positive: capacity > 0

class SHAPING_STATISTICS
invariant
    counters_non_negative: shape_calls >= 0 and cache_hits >= 0 and cache_misses >= 0
                           and fallback_probes >= 0 and notes_emitted >= 0
```

### LAYOUT_CACHE (mutation with full frame conditions)

```eiffel
put (a_key: READABLE_STRING_8; a_layout: SHAPED_LAYOUT)
    ensure
        stored: cache_model.domain [a_key.to_string_8]
        stored_value: cache_model [a_key.to_string_8] = a_layout
        others_kept_or_evicted: (old cache_model.count < capacity) implies
            cache_model |=| old cache_model.updated (a_key.to_string_8, a_layout)   -- frame: only this key
        bounded_after: cache_model.count <= capacity                                 -- eviction path

item (a_key: READABLE_STRING_8): detachable SHAPED_LAYOUT
    ensure
        from_model: Result = (if cache_model.domain [a_key.to_string_8]
                              then cache_model [a_key.to_string_8] else Void end)
        model_unchanged: cache_model |=| old cache_model      -- pure query (LRU order is not model-visible)
```

### SHAPING_CAIRO_BRIDGE (paint side)

```eiffel
draw_layout (a_context: CAIRO_CONTEXT; a_layout: SHAPED_LAYOUT; a_x, a_y: REAL_64)
    require
        context_valid: a_context.is_valid
    ensure
        layout_untouched: a_layout.lines_model |=| old a_layout.lines_model   -- painting never mutates layouts
    -- notes: glyph runs at run.font.pixel_size on run.font.cairo_face (same-N, DR-009);
    --        never raises; a failed surface/face becomes a skipped run + internal note
```

## Contract Completeness Checklist

- [x] **What changed?** Every command's direct effect stated (facade config, cache put, statistics).
- [x] **How did it change?** `old`-relative clauses on cache growth, statistics stability on hits, config transitions.
- [x] **What did NOT change?** MML `|=|` frames on cache/query paths; value classes immutable by invariant; `draw_layout` frames the layout.
- [x] **Never-raises** encoded as total-function ensures + notes at every native boundary (NFR-011).
- [x] **Bidi correctness** as postconditions where statable (level bounds/parity, permutation reorder, coverage); full UAX #9 conformance explicitly delegated to the Phase-5 harness (NFR-008) — contracts do not overclaim.
- [x] **Cross-backend oracle:** seam contracts identical for every effecting; doubles may strengthen only.

## CQS Audit Notes (for Phase 4.5)

| Feature | Type | Verdict |
|---------|------|---------|
| `layout` / `layout_default` | Query with benign memo effect (cache fill, statistics) | DECLARED EXCEPTION, documented: observable value depends only on arguments + configuration; cache/statistics are not part of the abstract state (uniform-access preserved). Same pattern as the skill's `execute` exception. |
| `set_*` fluent configs | Commands returning `like Current` | House-style chaining exception (matches simple_cairo) |
| `measured_width`, `line_height`, all value-class queries, `item` | Pure queries | CQS-clean |
| `clear_cache`, `wipe_statistics`, `put` | Commands | CQS-clean |
