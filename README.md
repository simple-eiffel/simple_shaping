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

> **Status: 0.1.0 pre-release - Phase 1 (contracts).** The full contract
> surface compiles and is enforced; pure value classes and pure-logic engines
> (FONT_LIST, LAYOUT_CACHE, the NULL doubles, the asset catalog's naming) are
> real; the shaping pipeline bodies are degenerate placeholders until Phase 4.
> Nothing here draws text yet. The Phase 2 adversarial contract review's
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
