# simple_shaping

**[GitHub](https://github.com/simple-eiffel/simple_shaping)**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Eiffel](https://img.shields.io/badge/Eiffel-25.02-blue.svg)](https://www.eiffel.org/)
[![Design by Contract](https://img.shields.io/badge/DbC-enforced-orange.svg)]()

Text shaping for the simple_* ecosystem: mixed-script paragraph text (Hebrew
with niqqud, Greek, Latin, emoji) in; cached, contracted, paintable layouts
out. Bidi, itemization, glyph shaping and font fallback live behind four
swappable seams - DirectWrite-first, Noto emoji as pixel-identical images.

Part of the [Simple Eiffel](https://github.com/simple-eiffel) ecosystem.

> **Status: 0.1.0 pre-release - Phase 4 in progress (Tasks 1-8 and 10 landed).**
> The full contract surface compiles and is enforced; pure value classes and
> pure-logic engines (FONT_LIST, LAYOUT_CACHE, the NULL doubles, the asset
> catalog's naming) are real; as of Phase 4 Task 1 the NATIVE surfaces are
> real too - `DWRITE_API` and `GDI32_API` now drive DirectWrite text analysis,
> line breakpoints, GDI font realization and real glyph shaping through
> `Clib/simple_shaping_dwrite.h` (still zero new DLLs). Task 2 makes FONTS real:
> `FONT_REGISTRY.font` realizes an identity on first use (LOGFONTW, HFONT,
> memory DC, TEXTMETRIC metrics, `IDWriteFontFace`), `dispose_all` gives every
> handle back, `family_exists` answers R1's "does this machine have that face?"
> through `GetTextFaceW` rather than trusting GDI's silent substitution, and the
> layout cache is keyed by the POST-PROBE effective font policy (R5), so two
> policies that differ only in a missing family share one entry. As of Task 3
> SEAM 1 is real - `DIRECTWRITE_BIDI_RESOLVER` resolves UAX #9 embedding levels
> per CODE POINT (surrogate pairs included), detects first-strong paragraph
> direction itself (DirectWrite offers no facility for it), and reorders lines
> by rule L2. It agrees with 358 of 396 sampled Unicode BidiCharacterTest
> cases; the 38 that differ are two named DirectWrite rule gaps, recorded in
> `tools/bidi-conformance.md` rather than worked around. As of Task 4
> SEAM 2 is real - `DIRECTWRITE_SCRIPT_ITEMIZER` splits a span into the items
> one engine shapes with one font, and it does so as the INTERSECTION of
> DirectWrite's `AnalyzeScript` runs with the resolved bidi levels, because
> `AnalyzeScript` alone merges Common-script characters into their neighbors
> (the D-015 line gives 3 script runs but must itemize into 4). Positions and
> counts are CODE POINTS - a surrogate pair is one code point of one item -
> each item carries the run's `DWRITE_SCRIPT_ANALYSIS` bytes verbatim for the
> shaper, and `soft_breaks` reports UAX #14 break opportunities from
> `AnalyzeLineBreakpoints`. As of Task 5 **SEAM 3 is real** -
> `DIRECTWRITE_GLYPH_SHAPER` shapes an item over its font's `IDWriteFontFace`
> with `GetGlyphs` + `GetGlyphPlacements` at the font's pixel size (same-N),
> returning real glyph ids, pixel advances, mark offsets and a cluster map in
> CODE-POINT space; an uncovered run is COUNTED (`missing_glyph_count`, the
> probe verdict seam 4 leans on) rather than thrown, and any unrecoverable
> native failure degrades to R3's tofu-but-valid synthesis, never to an empty
> item and never to a raise. EMOJI is real end to
> end (Tasks 6-8): the Noto png/128 set ships in `assets/`, `EMOJI_DATA_TABLES`
> is generated from pinned Unicode 17.0 data, and `EMOJI_SEGMENTER` performs
> full RGI longest-match segmentation with the FR-007 degradation ladder over a
> real file probe. As of Task 10 the WRAP is real -
> `LINE_LAYOUT_ENGINE.build_lines` fills lines greedily from runs the facade
> pre-splits at soft breaks (so a break falls BETWEEN runs and never inside a
> cluster or an emoji box), keeps a line-trailing breaking space on the
> preceding line while excluding its advance from the fit test (R2), gives a
> single over-wide unbreakable run its own `is_overflowing` line instead of
> splitting it, and reorders every finished line into visual paint order by
> UAX #9 L2 with metrics taken from the runs' own fonts and boxes. The rest of
> the shaping PIPELINE - fallback and the facade's `layout` - is still
> degenerate placeholders, so nothing here draws text yet and the segmenter and
> the wrap are not threaded through `layout` until Task 11. The Phase 2 adversarial contract review's
> conditions are repaired - all 22 findings applied, seam signatures amended
> and frozen (see CHANGELOG `[Unreleased]` and `.eiffel-workflow/evidence/phase2-repair.txt`).

## Why

simple_widgets renders text through cairo's "toy" API: no bidi, no shaping, no
itemization, no font fallback. Hebrew comes out left-to-right and unshaped,
mixed Hebrew/Latin lines are scrambled, emoji are tofu. This blocks
simple_chat's thick client, whose acceptance criterion is that a line mixing
Hebrew, an emoji and Greek renders with Hebrew right-to-left, the robot as the
same picture on every member's screen, and Greek intact. Every simple_widgets
app that shows user text inherits the fix.

## The architecture a caller leans on

- **One facade.** `layout (text, width_pixels, pixel_size, fonts): SHAPED_LAYOUT`
  is a TOTAL function: it never raises. Native failures degrade to fallback
  runs, missing-glyph boxes, or `SHAPING_NOTE` records - a layout cannot fail,
  only degrade, and every degradation is data.
- **Four seams, contracts as the oracle.** `BIDI_RESOLVER`, `SCRIPT_ITEMIZER`,
  `GLYPH_SHAPER`, `FONT_FALLBACK` are deferred classes whose postconditions
  are normative: any backend that satisfies them is a lawful engine, and the
  bidi conformance harness tells real ones apart. Backends may strengthen,
  never weaken.
- **DirectWrite first.** The MVP effects the first three seams over
  `IDWriteTextAnalyzer` (AnalyzeScript / AnalyzeBidi / GetGlyphs /
  GetGlyphPlacements) through a plain-C COM shim - no C++, no ATL, no import
  library - a pattern proven end-to-end by the feasibility spike kept in
  `spikes/dwrite/`. Uniscribe remains a named alternate slot.
- **The itemizer emits the script x bidi intersection.** Runs partition each
  span; every run carries one script id and one bidi level; boundaries are
  exactly the union of script and bidi boundaries. Script ids are
  engine-internal opaque ints - never comparable across backends.
- **Emoji are images, structurally.** `SHAPED_RUN` is closed over exactly
  `GLYPH_RUN | IMAGE_RUN`. The emoji segmenter runs after bidi resolution and
  BEFORE itemization, so a shaper never sees an emoji (the spike measured what
  happens otherwise: tofu). Every `IMAGE_RUN` is resolved to a shipped Noto
  png/128 asset - consumers never handle a broken image. The artwork is in
  the repository at `assets/noto-emoji/png/128/` (3,768 files, ~20 MiB, from
  noto-emoji tag `v2.051` = Unicode emoji 17.0); it ships in the runnable
  folder together with `LICENSE-ASSETS.md`. The detection tables are
  generated from the matching pinned Unicode data files and compiled in -
  see `tools/emoji-acquisition.md` for the pin and
  `tools/generate_emoji_tables.py` for the generator. Assets and tables move
  in ONE commit (DR-013).
- **Fallback is ours (G2).** A deterministic `FONT_LIST` walk with
  shaper probes, in every configuration. Exhaustion means requested-font
  boxes plus a note - never a silent drop.
- **Caching is the paint path.** Layouts are immutable and cached by value
  (text, width, size, fonts digest, asset directory) with verified hits - an
  unchanged pane repaint performs zero shaping calls, and the `statistics`
  counters prove it.
- **SCOOP by confinement.** One `SIMPLE_SHAPING` - with its fonts, caches and
  native handles - per processor. No `separate` types in the API.

## Installation

Set the ecosystem environment variable (one-time setup for all simple_* libraries):

```
SIMPLE_EIFFEL=D:\prod
```

Add to your ECF:

```xml
<library name="simple_shaping" location="$SIMPLE_EIFFEL/simple_shaping/simple_shaping.ecf"/>
```

Dependencies: `base`, `simple_mml` (models in contracts). The test target adds
`simple_testing`. Phase 4 adds the gated simple_cairo glyph API for painting;
usp10/gdi32/dwrite are OS-provided - zero DLLs ship.

## Usage (the consumer story)

```eiffel
local
    shaper: SIMPLE_SHAPING
    l: SHAPED_LAYOUT
do
    -- once per UI processor:
    create shaper.make ({STRING_32} "assets\noto-emoji\png\128")

    -- per message bubble (measure):
    l := shaper.layout_default (message_text, bubble_inner_width, 14)
    bubble_height := l.total_height + 2 * padding

    -- per paint (cached; zero shaping when unchanged):
    l := shaper.layout_default (message_text, bubble_inner_width, 14)
    -- Phase 4+: SHAPING_CAIRO_BRIDGE.draw_layout (context, l, x, y)

    -- degradations are data, never exceptions:
    if l.has_notes then
        across l.notes as n loop
            log (n.code_name)
        end
    end
end
```

Guidance bound into the API docs: size bubbles from `layout.total_height`
always (`line_height` is only for empty-message minimums), and re-layout on
resize-END, not per resize tick.

## Testing

```
/d/prod/ec.sh test -config simple_shaping.ecf -target simple_shaping_tests
EIFGENs/simple_shaping_tests/F_code/simple_shaping.exe
```

Headless by design: the NULL_* doubles effect all four seams with pure logic,
so layout logic tests run on any machine with zero native calls.

## License

simple_shaping is MIT (`LICENSE`).

The emoji artwork under `assets/noto-emoji/png/128/` is Google Noto Emoji,
Copyright 2013 Google LLC, redistributed unmodified under the terms in
`LICENSE-ASSETS.md` - which ships beside the executable. At the pinned tag
(`v2.051`) upstream's root `LICENSE` is the SIL OFL 1.1 while its README
still calls image resources Apache-2.0, so `LICENSE-ASSETS.md` carries the
full text of BOTH and complies with the stricter reading. Neither imposes
an attribution-UI requirement.
