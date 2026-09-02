# SCOPE: simple_shaping

Date: 2026-09-01. Pre-phase research for a NEW library at `D:\prod\simple_shaping`.

## Problem Statement

In one sentence: **simple_widgets cannot render mixed-script chat text — Hebrew (RTL + bidi), Greek, Latin, and emoji — because it draws through cairo's "toy" text API, which does no bidi, no shaping, no itemization, and no font fallback.**

What's wrong today:
- `SW_PAINTER.show_text` (D:\prod\simple_widgets\src\sw_painter.e:74) calls cairo `show_text` — the API cairo's own manual calls a "toy" API, "not expected to be adequate for serious text-using applications" (cairographics.org manual 1.17.2, cairo-text).
- Hebrew comes out left-to-right and unshaped; mixed Hebrew/Latin lines are visually scrambled; emoji beyond the UI font's coverage are tofu.
- This blocks simple_chat's thick-client message pane (`SW_CHAT_THREAD`) — decision D-015 made the thick client the only client, and D-014 already committed to `simple_shaping` as its own library (D:\prod\simple_chat\.eiffel-workflow\research\04-DECISIONS.md).

Who experiences this: Larry and every simple_chat member using the simple_widgets GUI; downstream, every simple_widgets app that shows user text (scholar GUI included — Hebrew/Greek is the daily material of this vault).

Impact of not solving: the thick client cannot ship its acceptance criterion — "shows `שלום 🤖 Χριστός` with Hebrew right-to-left, the marker as the same picture on every member's screen, and Greek intact" (simple_chat spec/10-ADDENDUM-THICK-CLIENT.md).

## Target Users

| User Type | Needs | Pain Level |
|-----------|-------|------------|
| simple_chat thick client (`SW_CHAT_THREAD`) | Correct bidi display, emoji as identical pictures, line wrap, cached layouts | HIGH |
| simple_widgets itself (`SW_PAINTER`, later `SW_TEXT_BOX`) | A `shape` call returning positioned glyph runs; later caret/hit-testing | HIGH |
| Scholar GUI / future simple_* apps | Hebrew + Greek display with niqqud correctly positioned | MED |

## Success Criteria

| Level | Criterion | Measure |
|-------|-----------|---------|
| MVP | `שלום 🤖 Χριστός` renders correctly in SW_CHAT_THREAD | Visual check: Hebrew RTL, 🤖 as PNG, Greek intact; zero browser processes |
| MVP | Mixed bidi paragraph orders per UAX #9 | Sample cases from Unicode BidiCharacterTest.txt pass on the resolver |
| MVP | Missing-glyph fallback works | A codepoint absent from the UI font renders from a fallback font, not tofu |
| MVP | Line wrap on cluster boundaries | No wrap inside a Hebrew cluster (base+niqqud) or emoji sequence |
| Full | Pure-Eiffel BIDI_RESOLVER passes Unicode conformance | BidiTest.txt + BidiCharacterTest.txt harness green |
| Full | Selection/hit-testing for SW_TEXT_BOX | x↔character-position mapping correct in RTL runs |

## Scope Boundaries

### In Scope (MUST)
- Four deferred-class seams per D-014: `BIDI_RESOLVER`, `SCRIPT_ITEMIZER`, `GLYPH_SHAPER`, `FONT_FALLBACK` — each independently swappable.
- Windows-native backend first; output = `GLYPH_RUN` sequence (glyph indices + positions + cluster map) that simple_cairo draws via `cairo_win32_font_face_create_for_logfontw` + `cairo_show_glyphs`.
- Emoji sequence segmentation (UTS #51: VS16, ZWJ sequences) producing IMAGE runs keyed by codepoint sequence — resolves D-019.
- Line layout for a chat pane: greedy wrap at legal break points, per-line caching.
- Hebrew (with niqqud), Greek, Latin, emoji. Paragraph direction detection (first-strong).

### In Scope (SHOULD)
- Pluggable font list for fallback (per-script preferred faces).
- Measurement API (line height, run extents) for SW_CHAT_THREAD bubble sizing.

### Out of Scope
- Full text editor machinery (styles engine, justification, hyphenation): the consumer is a chat message pane — display first.
- Arabic/Indic/Thai shaping correctness guarantees: not exercised by the consumer; whatever the OS backend gives is a bonus, untested.
- Printing/PDF text extraction; vertical text; kashida justification.
- Color-font (COLR/CBDT) rasterization: dead end through cairo 1.17.2 win32 — see 02-LANDSCAPE; emoji go through the image path instead.

### Deferred to Future
- Caret movement, selection, hit-testing (`ScriptXtoCP`-class features) for `SW_TEXT_BOX`: needs the same runs, added after display works.
- Pure-Eiffel `GLYPH_SHAPER` (OpenType GSUB/GPOS): the long pole; staged last, possibly never (see 04-DECISIONS D-S06).
- DirectWrite backend: stage 2, only if Uniscribe limits are actually hit (see 04-DECISIONS D-S02).

## Constraints

| Type | Constraint |
|------|------------|
| Technical | Windows 10/11 only; every OS API used must exist there |
| Technical | Ship as runnable folder; **zero new DLLs preferred** — OS-provided APIs win over shipped shapers |
| Technical | Void-safe, SCOOP-compatible Eiffel; simple_* first policy |
| Technical | Renderer is cairo 1.17.2 as shipped by simple_widgets: `CAIRO_HAS_WIN32_FONT 1`, `CAIRO_HAS_FT_FONT 1`, **no DirectWrite font backend** (verified locally: D:\prod\cairo-windows-1.17.2\include\cairo-features.h) |
| Performance | Chat pane: hundreds of visible lines, layouts cached per line; shaping is off the paint path |
| Licensing | Permissive only; emoji assets get their own license section (Noto Apache-2.0 / Twemoji CC-BY 4.0) |

## Assumptions to Validate

| ID | Assumption | Risk if False | Verdict (this research) |
|----|------------|---------------|-------------------------|
| A-1 | Glyph indices from a Windows shaper are valid for cairo's win32 font face on the same font | Whole bridge collapses | **CONFIRMED** — cairo win32 draws via `ExtTextOutW(... ETO_GLYPH_INDEX ...)`; `cairo_glyph_t.index` is "glyph index in the font"; DWrite's `CreateFontFaceFromHdc` guarantees "the same physical typeface that would be used for drawing glyphs ... using ExtTextOut" (see 02, 04) |
| A-2 | Uniscribe alone can deliver Hebrew bidi + shaping | Must pay the DirectWrite COM cost in MVP | **CONFIRMED** for 3 of 4 seams; font fallback is explicitly the application's job (Learn, "Using Font Fallback") |
| A-3 | Color emoji can render through cairo 1.17.2 win32 | D-019 image path would be optional | **REFUTED — color emoji CANNOT render on this path** (GDI has no color-font support; cairo color work is FreeType-side and post-1.17.2). D-019 image path is therefore REQUIRED, not optional |
| A-4 | Some Eiffel text-shaping work exists to reuse | Build from scratch | **REFUTED** — none found in simple_* (D:\prod grep), Gobo string library, or public Eiffel sources |

## Research Questions (answered in 02/04)

- Can Uniscribe alone deliver correct Hebrew bidi + shaping and monochrome-emoji fallback, and what breaks first vs DirectWrite? → 04-DECISIONS D-S01/D-S02.
- How do shaper glyph indices map onto `cairo_win32_font_face_create_for_logfontw` (same font realization? HFONT per run?) → 02-LANDSCAPE "The cairo bridge", 04 D-S03.
- Does color emoji render on any available path (COLR in cairo win32: yes/no)? Does that decide D-019? → 02-LANDSCAPE "Color emoji"; verdict in 04 D-S04.
- What do pango-less ecosystems on cairo do — is "shaper + cairo_show_glyphs" well-trodden? → 02-LANDSCAPE "Cross-language patterns".
- Any existing Eiffel text-shaping work? → 02-LANDSCAPE "Eiffel Ecosystem Check".
