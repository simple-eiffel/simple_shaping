# Intent: simple_shaping

Phase 0 intent, pre-populated from the complete spec (`.eiffel-workflow/spec/01..08`) and research (`.eiffel-workflow/research/01..07`). Spec decisions are BOUND and carried verbatim; this document states WHAT and WHY for the approval gate.

## What

The first Eiffel text-shaping library: mixed-script paragraph text (Hebrew with niqqud, Greek, Latin, emoji) in; cached, contracted, paintable layouts out. Glyph runs are drawn by simple_cairo via `cairo_show_glyphs` on win32 font faces (`cairo_win32_font_face_create_for_logfontw_hfont`); emoji are pixel-identical inline Noto PNG boxes. One facade (`SIMPLE_SHAPING`): `layout (text, width_pixels, pixel_size, fonts): SHAPED_LAYOUT` — a total function that never raises; degradations surface as `SHAPING_NOTE` data.

## Why

simple_widgets renders text through cairo's "toy" API (`SW_PAINTER.text` → `cairo_show_text`): no bidi, no shaping, no itemization, no font fallback. Hebrew comes out left-to-right and unshaped, mixed Hebrew/Latin lines are scrambled, emoji are tofu. This blocks simple_chat's thick client (D-015: "Thick first and no browser"), whose acceptance criterion is that `שלום 🤖 Χριστός` renders with Hebrew right-to-left, the robot as the same picture on every member's screen, and Greek intact. Downstream, every simple_widgets app that shows user text (the scholar GUI's daily Hebrew/Greek included) inherits the fix.

## Users

| User | How they use it |
|------|-----------------|
| **simple_chat's SW_CHAT_VIEW** (THE consumer; apps/client over simple_widgets, Phase 4 there) | One `SIMPLE_SHAPING` per UI processor; `layout_default (message.text, bubble_inner_width, N)` per message; bubble sized from `total_width/total_height`; paint via `SHAPING_CAIRO_BRIDGE.draw_layout`; unchanged re-paint hits the cache (zero shaping calls) |
| simple_widgets (`SW_PAINTER.draw_shaped_layout`, later `SW_TEXT_BOX`) | Delegates to the bridge; hit-testing names reserved for the future text box |
| Scholar GUI / future simple_* apps | Hebrew + Greek display with niqqud correctly positioned |
| Test suites (this library's and simple_chat's) | `make_with_backends` + NULL_* doubles: headless layout testing, no usp10/gdi32 (CI-safe) |

## Bound Decisions (carried verbatim — NEVER reopened here)

- **Four-seam architecture** (D-014/C-006): deferred `BIDI_RESOLVER`, `SCRIPT_ITEMIZER`, `GLYPH_SHAPER`, `FONT_FALLBACK`; each independently swappable; contracts are the cross-backend equivalence oracle (I-001).
- **G1**: Uniscribe (usp10, flat C, zero COM, zero shipped DLLs) effects the first three seams in MVP; **DirectWrite is the stage-2 slot**, built only against a demonstrated limit (D-S02).
- **G2**: `FONT_FALLBACK` is the library's own `LIST_FONT_FALLBACK` (configured `FONT_LIST` walk + shaper probe) in EVERY configuration.
- **G3**: emoji ship as **Noto Emoji png/128 assets** (Apache-2.0; `emoji_u1f916.png` = 🤖) with **structural emoji segmentation**: `SHAPED_RUN` is closed over exactly two heirs, `GLYPH_RUN | IMAGE_RUN`; emoji NEVER reach the shaper (color emoji cannot travel this render path — research-proven).
- **D-S03 same-N**: one `SHAPING_FONT` per (family, weight, style, pixel size) owning LOGFONTW + HFONT + memory HDC + SCRIPT_CACHE + lazy cairo face; shape at pixel size N, `set_font_size (N)` on the same face; shaper positions are authoritative.
- **OQ-1 per-processor confinement** (DR-012): one facade — with its registry, fonts, SCRIPT_CACHEs, and layout cache — per SCOOP processor; no `separate` types in the public API; SCRIPT_CACHE concurrency is UNVERIFIED upstream, so the design never depends on it.
- **D-S07 is a GATED EXTERNAL dependency on simple_cairo** (separate repo, Larry's gate): `cairo_glyph_t` marshalling, `show_glyphs`, `glyph_extents`, `set_font_face`, `CAIRO_FONT_FACE` + the two win32 face constructors. NOT this library's code; fallback if the gate slips = temporary externals in-library, migrated later (RISK-008).
- **MML mandatory**; **simple_* first**.
- Pipeline order (A-C03/DR-005): bidi over the FULL text → emoji segmentation (spans inherit resolved levels) → itemization of plain spans only → fallback+shape → cluster-safe greedy wrap → per-line visual reorder.
- `layout` is a TOTAL function (NFR-011): no exception escapes; worst cases are fallback runs, missing-glyph boxes, or notes.

## Acceptance Criteria (deterministic, testable; centered on SW_CHAT_VIEW)

- [ ] **AC-1 The D-015 chat line**: `layout ("שלום 🤖 Χριστός", W, N, default_fonts)` yields a layout in which (a) the Hebrew characters occupy visually-RTL positions (runs in visual order per line), (b) U+1F916 is exactly ONE `IMAGE_RUN` with `asset_key = "emoji_u1f916"` and an `asset_path` under the configured Noto png/128 directory, (c) the Greek and any Latin are `GLYPH_RUN`s, and (d) `covers_all_characters` holds. Painted via `cairo_show_glyphs` + a PNG surface blit in a simple_widgets pane, it matches WordPad/Notepad visually for the text and shows the identical robot on every machine.
- [ ] **AC-2 Pixel-width wrap**: at narrow `W`, wrapping `שלום עולם` (and pointed `שָׁלוֹם`) never splits base+niqqud clusters nor any emoji sequence; every source character lands in exactly one line; every line fits `W` or is flagged `is_overflowing` (single unbreakable run).
- [ ] **AC-3 Cache/repaint**: a second identical `layout` call returns a cached layout with `statistics.shape_calls` unchanged (FR-012); an unchanged 200-line pane repaint performs zero shaping calls.
- [ ] **AC-4 Fallback rescue**: a codepoint absent from the requested font renders from the first covering `FONT_LIST` font; the run's `font` reports the fallback face; exhaustion degrades to the requested font's missing-glyph boxes + a `SHAPING_NOTE` (never Void, never a silent drop).
- [ ] **AC-5 Bidi conformance samples**: the sampled BidiCharacterTest.txt cases (all-Hebrew, Hebrew+digits, mixed Hebrew/Latin) produce the specified level arrays and visual order through `UNISCRIBE_BIDI_RESOLVER`; the harness class ships in testing/ (full run = Phase 5 gate).
- [ ] **AC-6 Empty/whitespace text (FR-N01)**: `layout ("")` → one line, zero runs, height = primary-face line height, no notes; whitespace-only text still measures and lays out.
- [ ] **AC-7 Headless doubles (UC-005)**: the full layout pipeline (wrap, coverage, caching, measurement) runs under NULL_* seams with zero native calls — simple_chat's tests can assault SW_CHAT_VIEW logic on any machine.
- [ ] **AC-8 Never-raises**: with a fault-injecting shaper double (and, on-machine, induced Uniscribe failures), `layout` still returns a paintable layout whose degradations are enumerated in `notes`.
- [ ] **AC-9 Runnable folder**: fresh-machine run from a copied folder — zero installers, zero new DLLs (usp10/gdi32 are OS-provided), assets + LICENSE-ASSETS.md beside the exe.
- [ ] **AC-10 Measurement**: `measured_width ("abc", N, fonts)` = sum of the shaped advances; `line_height` ≥ ascent + descent; empty text measures 0.0.

## Out of Scope

- Text-editor machinery: styles engine, justification, hyphenation, rich multi-style runs (C-007 — consumer is a chat message pane).
- Arabic/Indic/Thai shaping GUARANTEES (whatever Uniscribe gives is an untested bonus).
- Printing/PDF text extraction; vertical text; kashida.
- Color-font (COLR/CBDT) rasterization — dead end through cairo 1.17.2 win32 (G3 exists because of this).
- Hit-testing/caret/selection — FUTURE (FR-013); `character_index_at_x` / `x_at_character_index` names reserved on SHAPED_LINE, not compiled this cycle.
- DirectWrite backends (stage-2 slots, named only); pure-Eiffel bidi/itemizer (staged behind full-conformance gates, D-S06).
- The simple_cairo glyph API itself (D-S07 — external gated repo change) and the simple_widgets adoption (`SW_PAINTER.draw_shaped_layout` — second gated repo change, Phase 7 coordination).

## Dependencies (REQUIRED - simple_* First Policy)

**RULE:** Always prefer simple_* libraries over ISE EiffelStudio stdlib and Gobo.

| Need | Library | Justification |
|------|---------|---------------|
| Model queries + frame conditions | **simple_mml** (exists, D:\prod\simple_mml) | MML_SEQUENCE/MML_MAP models on all 14 collection-bearing classes; `\|=\|` frames (05-CONTRACT-DESIGN) |
| Rendering (faces, surfaces, PNG decode) | **simple_cairo** (exists, D:\prod\simple_cairo) | `CAIRO_SURFACE.make_from_png` VERIFIED present (cairo_surface.e:26,65) — emoji surfaces need nothing new; **glyph API is D-S07** |
| Glyph drawing (`show_glyphs`, `glyph_extents`, `set_font_face`, `CAIRO_FONT_FACE` + win32 constructors) | **D-S07 gated addition to simple_cairo** — EXTERNAL dependency, Larry's gate, separate repo | VERIFIED absent today (no `show_glyphs` in cairo_context.e); headers already in its Clib; fallback: temporary in-library externals (RISK-008) |
| Test infrastructure | **simple_testing** (exists, D:\prod\simple_testing) | TEST_APP/LIB_TESTS per ecosystem conventions; TEST_SET_BASE |
| Bidi/itemize/shape backends | OS usp10.dll / gdi32.dll (G1) | Not libraries; ship with Windows 10/11; zero DLLs added; Win8+ link order (Usp10.lib before gdi32.lib) → build docs |
| Emoji assets | Noto Emoji png/128 (Apache-2.0), copied into assets/ | G3; LICENSE-ASSETS.md ships (NFR-009); NOT yet acquired locally (Phase-3 task) |
| Emoji/bidi Unicode data | Pinned emoji-test.txt (RGI) + emoji-zwj-sequences.txt → generated `EMOJI_DATA_TABLES`; BidiTest/BidiCharacterTest as test fixtures | D-S08: generator in tools/, version constant pinned to the asset set (DR-013) |
| Fundamental types | ISE base only (HASH_TABLE, ARRAYED_LIST, IMMUTABLE_STRING_*) | Allowed per policy; no ISE/Gobo text machinery anywhere |

**Consumer (not a dependency):** simple_widgets / simple_chat's SW_CHAT_VIEW. Layering: simple_widgets → simple_shaping → simple_cairo → cairo.dll; simple_shaping → (usp10, gdi32).

## MML Decision (REQUIRED)

**Decision:** YES-Required
**Rationale:** Ecosystem default, bound at kickoff. The contract design (05) already maps every collection-bearing class to MML models; seam postconditions (coverage partitions, permutation reorder, monotone cluster maps) and cache frame conditions (`|=|`) are unstatable without them. simple_mml exists and is the ecosystem's own model library.
