# INTERFACE DESIGN: simple_shaping

Public API as the consumer (SW_CHAT_VIEW / SW_PAINTER) experiences it. Eiffel-first (I-004): READABLE_STRING_32 in, contracted value objects out; fluent configuration in the simple_cairo house style (`: like Current`).

## Public API Summary

### Creation (SIMPLE_SHAPING)
| Feature | Purpose | Typical Use |
|---------|---------|-------------|
| `make (a_asset_directory)` | Production wiring: Uniscribe seams (G1) + LIST_FONT_FALLBACK (G2) + default FONT_LIST | `create shaper.make ("assets\noto-emoji\png\128")` |
| `make_with_backends (bidi, itemizer, shaper, fallback, asset_dir)` | Injected seams (tests, stage-2 swap experiments) | headless tests with NULL_* doubles |

### Core Operations
| Feature | Returns | Purpose |
|---------|---------|---------|
| `layout (text, width_pixels, pixel_size, fonts)` | SHAPED_LAYOUT | THE operation: paragraph → cached, paintable layout; total function (never raises) |
| `layout_default (text, width_pixels, pixel_size)` | SHAPED_LAYOUT | Same under `default_fonts` — the chat pane's per-message call |

### Measurement (FR-011)
| Feature | Returns | Purpose |
|---------|---------|---------|
| `measured_width (text, pixel_size, fonts)` | REAL_64 | Unwrapped advance width (bubble min-width, widest-line logic) |
| `line_height (pixel_size, fonts)` | REAL_64 | One line's height in the primary face (empty-message sizing, FR-N01) |
| `SHAPED_LAYOUT.total_width / total_height` | REAL_64 | Bubble size |
| `SHAPED_LINE.width / height / ascent` | REAL_64 | Baseline placement: draw at y_top + ascent |
| `SHAPED_RUN.advance_width / source_start / source_count / is_rtl` | mixed | Per-run geometry and provenance |

### Configuration (fluent)
| Feature | Returns | Purpose |
|---------|---------|---------|
| `set_default_fonts (fonts)` | like Current | Fallback policy for `layout_default` |
| `set_asset_directory (path)` | like Current | Noto png/128 location (clears cache — asset identity) |
| `set_cache_capacity (n)` | like Current | Bound the layout cache (default 512) |

### Status Queries
| Feature | Returns | Purpose |
|---------|---------|---------|
| `default_fonts` | FONT_LIST | Current policy |
| `asset_directory` | IMMUTABLE_STRING_32 | Current asset root |
| `statistics` | SHAPING_STATISTICS | shape_calls / cache_hits / cache_misses / fallback_probes / notes_emitted (FR-N02; FR-012 acceptance counter) |
| `cache_count`, `cache_capacity` | INTEGER | Cache observability |
| `is_cached (text, width, size, fonts)` | BOOLEAN | Pre-flight (used by layout's own postconditions) |

### Commands
| Feature | Purpose |
|---------|---------|
| `clear_cache` | Drop all cached layouts (theme/font change) |
| `wipe_statistics` | Reset counters (test isolation) |

## FONT_LIST (builder-style value)

| Feature | Returns | Purpose |
|---------|---------|---------|
| `make_default` | — | The OQ-3 resolution: general [UI face, "Segoe UI", "Arial", "Tahoma"]; hebrew prepends ["SBL Hebrew"(probed), "Segoe UI", "David", "Tahoma"]; greek prepends ["Segoe UI", "Palatino Linotype"] |
| `make_empty` | — | Start from scratch |
| `with_family (name)` | like Current | Append to the general list |
| `with_family_for_script (script_class, name)` | like Current | Prepend for one script class (`Script_class_hebrew`, `_greek`, `_latin`, `_symbol`, `_other`) |
| `families_for (script_class)` | ordered names | What fallback will probe, in order |
| `is_empty`, `digest` | BOOLEAN / STRING_8 | Usability guard; VALUE-based cache-key part (FR-N03: equal lists ⇒ equal digests) |

## The run model at the consumer (emoji segmentation in the type system)

```eiffel
across a_layout.lines as line loop
    across line.runs as run loop                      -- VISUAL order: paint left to right
        if attached {GLYPH_RUN} run as g then
            -- g.font (SHAPING_FONT), g.glyph_ids, g.x_positions/y_positions, g.cluster_map
        elseif attached {IMAGE_RUN} run as im then
            -- im.asset_path (resolved ALWAYS — DR-006), im.width/height, im.codepoints
        end
    end
end
```
Consumers that only paint never write this loop — the bridge owns it:

## Fluent API Example (the whole consumer story)

```eiffel
-- once per UI processor (SW_CHAT_VIEW creation):
create shaper.make ("assets\noto-emoji\png\128")
shaper.set_default_fonts (create {FONT_LIST}.make_default)
      .set_cache_capacity (1_000).do_nothing
create bridge.make (shaper)

-- per message bubble (measure):
l := shaper.layout_default (message.text, bubble_inner_width, 14)
bubble_height := l.total_height + 2 * padding

-- per paint (cached; zero shaping calls when unchanged — FR-012):
l := shaper.layout_default (message.text, bubble_inner_width, 14)
bridge.draw_layout (painter.context, l, x + padding, y + padding)
```
`SW_PAINTER` grows one feature: `draw_shaped_layout (a_layout; a_x, a_y)` delegating to the bridge (the simple_widgets-side gated change flagged in research 06-RISKS "Ecosystem Risks"; not this library's code).

## Error Handling Pattern (no exceptions — NFR-011)

```eiffel
l := shaper.layout_default (text, w, size)
-- ALWAYS paintable. Degradations are data:
if l.has_notes then
    across l.notes as n loop
        log (n.code_name + ": " + n.message)   -- e.g. fallback_exhausted, emoji_degraded, backend_error_recovered
    end
end
```
There is no `is_success` on SHAPED_LAYOUT — a layout cannot fail, only degrade (total function). The XOR success/error pattern is deliberately NOT used here; SHAPING_NOTE carries specifics with source ranges.

## Reserved API (FR-013 — names frozen now, contracts in a future cycle)

| Feature (on SHAPED_LINE) | Future purpose |
|--------------------------|----------------|
| `character_index_at_x (a_x: REAL_64): INTEGER` | Hit-testing for SW_TEXT_BOX (ScriptXtoCP-class) |
| `x_at_character_index (a_index: INTEGER): REAL_64` | Caret placement (ScriptCPtoX-class) |

Reserving the names prevents a breaking rename when SW_TEXT_BOX arrives; they ship as `feature -- Future` comments in the class text of this cycle, NOT compiled features.

## Command-Query Separation

| Feature | Type | Modifies State? | Returns Value? |
|---------|------|-----------------|----------------|
| `layout`, `layout_default` | Query (benign memo) | cache/statistics only — not abstract state | SHAPED_LAYOUT (declared exception, documented; 05 CQS notes) |
| `measured_width`, `line_height` | Query (memo via layout) | same | REAL_64 |
| `set_*` | Command | YES | like Current (house-style chaining) |
| `clear_cache`, `wipe_statistics` | Command | YES | NO |
| all status queries, all value-class queries | Query | NO | YES |

## Interface Segregation

- Consumers that only MEASURE need: facade + SHAPED_LAYOUT metrics — never see seams, fonts, or cairo.
- Consumers that PAINT add: SHAPING_CAIRO_BRIDGE — never see glyph arrays.
- TESTS need: seams + doubles + engine classes — never see native handles.
- Only Phase-4 implementation sees USP10_API/GDI32_API ({NONE}-restricted export status).
