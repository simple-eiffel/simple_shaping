# PARSED REQUIREMENTS: simple_shaping

Date: 2026-09-01. Source: `.eiffel-workflow/research/` (01-SCOPE through 07-RECOMMENDATION + REFERENCES), all read in full. Larry's gates of 2026-09-01 are bound below as decisions G1-G3.

## Problem Summary

simple_widgets renders text through cairo's "toy" API (`SW_PAINTER.text` → `cairo_show_text`, sw_painter.e:74): no bidi, no shaping, no itemization, no font fallback. Hebrew comes out left-to-right and unshaped, mixed Hebrew/Latin lines are scrambled, and emoji outside the UI font are tofu. This blocks simple_chat's thick-client message pane (`SW_CHAT_VIEW` over simple_widgets, D-015) whose acceptance criterion is: `שלום 🤖 Χριστός` renders with Hebrew right-to-left, the robot as the same picture on every member's screen, and Greek intact.

simple_shaping is the library that fixes it: paragraph text in, positioned glyph/image runs out, drawn by simple_cairo via `cairo_show_glyphs`.

## Scope

### In Scope (MUST)
- Four deferred-class seams per D-014: `BIDI_RESOLVER`, `SCRIPT_ITEMIZER`, `GLYPH_SHAPER`, `FONT_FALLBACK` — each independently swappable.
- Uniscribe backend (G1) behind the first three seams; output = glyph runs (glyph indices + positions + cluster map) drawn via `cairo_win32_font_face_create_for_logfontw_hfont` + `cairo_show_glyphs`.
- Emoji sequence segmentation (UTS #51: VS16, ZWJ, RGI) producing IMAGE runs keyed by codepoint sequence, resolved against shipped Noto Emoji png/128 assets (G3).
- Line layout for a chat pane: greedy wrap at legal break points, never inside a cluster or emoji sequence; per-line/paragraph caching.
- Hebrew (with niqqud), Greek, Latin, emoji. Paragraph direction detection (first-strong).
- Measurement API (paragraph size, line height/baseline, run extents) for SW_CHAT_VIEW bubble sizing.
- Pluggable ordered font list for fallback with per-script preferences (G2).

### Out of Scope
- Full text-editor machinery (styles engine, justification, hyphenation) — consumer is a chat message pane (C-007).
- Arabic/Indic/Thai shaping correctness guarantees — untested bonus, whatever the OS backend gives.
- Printing/PDF text extraction; vertical text; kashida.
- Color-font (COLR/CBDT) rasterization — research-proven dead end through cairo 1.17.2 win32 under ANY shaper; emoji go through the image path (G3).

### Deferred to Future
- Hit-testing/caret/selection (`ScriptXtoCP`-class) for `SW_TEXT_BOX` — API names reserved on `SHAPED_LINE` (FR-013).
- Pure-Eiffel `GLYPH_SHAPER` (OpenType GSUB/GPOS) — the long pole; possibly never (D-S06).
- DirectWrite backends — stage 2, only against a demonstrated Uniscribe limit (D-S02); first target seam would be FONT_FALLBACK's provider.
- Full BidiTest.txt (513,494 cases) + BidiCharacterTest.txt conformance run — the harness ships with the library, sampled in MVP tests; the FULL pass is a Phase-5 (/eiffel.verify) requirement and the promotion gate for `EIFFEL_BIDI_RESOLVER`.

## Functional Requirements

Carried verbatim in intent from research/03-REQUIREMENTS.md; IDs preserved for traceability.

| ID | Requirement | Priority | Source | Acceptance |
|----|-------------|----------|--------|------------|
| FR-001 | Shape a Unicode paragraph (READABLE_STRING_32) into an ordered sequence of glyph runs (font handle, pixel size, glyph indices, per-glyph positions, cluster map, direction, source range) | MUST | research/03 | "abc" in one font: one LTR run, 3 glyphs, advances > 0, cluster map monotone |
| FR-002 | Correct bidi: paragraph direction by first-strong; embedding levels and visual reordering per UAX #9 | MUST | research/03 | Sampled BidiCharacterTest.txt cases (all-Hebrew, Hebrew+digits, mixed Hebrew/Latin) produce specified level arrays and visual order |
| FR-003 | Hebrew renders RTL with niqqud marks positioned (not overstruck, no tofu) | MUST | research/03 | `שָׁלוֹם` and `שלום עולם 123` render correctly in the demo; visual check vs WordPad/Notepad |
| FR-004 | Greek and Latin intact in mixed lines | MUST | research/03 | The D-015 acceptance string renders with all three scripts correct |
| FR-005 | Script itemization splits runs by script (UAX #24) so each run shapes under one engine and one font | MUST | research/03 | Mixed string yields ≥ 3 runs (Hebrew, emoji-image, Greek); no run mixes scripts |
| FR-006 | Emoji segmentation per UTS #51 (VS16, ZWJ, RGI) → IMAGE run with codepoint-sequence asset key | MUST | research/03 | 🤖 (U+1F916) → asset `emoji_u1f916.png`; `❤️` (2764 FE0F) → `emoji_u2764.png` (VS16 dropped from the key); a ZWJ family sequence maps to ONE image run |
| FR-007 | Image runs resolve to shipped PNG assets and report box size to layout; unknown sequences fall back to per-codepoint images, then to the glyph path (monochrome) | MUST | research/03 | Asset present: image box at line height; asset absent: no crash, monochrome glyphs or missing-glyph boxes; degradation recorded as a SHAPING_NOTE |
| FR-008 | Font fallback: when the requested font lacks a run's characters (missing-glyph scan / USP_E_SCRIPT_NOT_IN_FONT), retry the run against a configurable ordered font list | MUST | research/03 | A CJK codepoint under the UI font renders from a fallback face, not tofu; the run's `font` reports the fallback face |
| FR-009 | Line layout: greedy wrap at legal break opportunities (ScriptBreak-class), never inside a cluster or emoji sequence; produces lines with height/baseline | MUST | research/03 | Wrapping `שלום עולם` at a narrow width never splits base+mark; RTL word order per line correct |
| FR-010 | Cairo bridge: per glyph run, obtain/cache a `cairo_font_face_t` via `cairo_win32_font_face_create_for_logfontw_hfont`, set matching pixel size (same-N rule), emit `cairo_show_glyphs` arrays with shaper glyph ids as `cairo_glyph_t.index` | MUST | research/03, D-S03 | Round-trip demo: cairo-drawn glyphs match GDI `ExtTextOut ETO_GLYPH_INDEX` output pixel-close on screen |
| FR-011 | Measurement API: paragraph → total size; line → height, baseline, advance; run → extents | MUST | research/03 | Measured width of "abc" = sum of advances; line height ≥ ascent+descent |
| FR-012 | Layout cache keyed by (text, width, pixel size, font config): shaping never runs during paint for unchanged lines | SHOULD | research/03 | Re-paint of an unchanged 200-line pane performs zero ScriptShape calls (counter-instrumented) |
| FR-013 | Hit-testing/caret mapping (x ↔ character position, RTL-aware) | FUTURE | research/03 | Deferred; feature names reserved on SHAPED_LINE |

## Non-Functional Requirements

| ID | Requirement | Category | Measure | Target |
|----|-------------|----------|---------|--------|
| NFR-001 | Shaping throughput | PERFORMANCE | One 80-char mixed-script line, warm caches | ≤ 1 ms typical; ≤ 5 ms worst |
| NFR-002 | Paint-path cost | PERFORMANCE | Work per cached line at paint | Array handoff to cairo only; zero shaping calls |
| NFR-003 | Memory | PERFORMANCE | Cached layout per line | O(glyphs); hundreds of lines ≈ few MB; cache is capacity-bounded |
| NFR-004 | Zero new DLLs (MVP) | DEPLOYMENT | Files added to runnable folder besides own code + PNG assets | 0 DLLs (usp10/gdi32 are OS-provided) |
| NFR-005 | Void safety | CORRECTNESS | ECF void_safety full | Compiles void-safe |
| NFR-006 | SCOOP compatibility | CORRECTNESS | No shared mutable native caches across processors | One SIMPLE_SHAPING (and all its fonts/caches) per processor; OQ-1 resolved by confinement — see 03/05 |
| NFR-007 | Contract coverage | CORRECTNESS | Public features carry require/ensure; documented API invariants become contracts (cluster-map monotonicity; even/odd bidi levels; run coverage; reorder-is-permutation) | 100% of public API. NOTE: the "1.5·n+16" glyph figure is reclassified as buffer-sizing guidance, NOT a postcondition — see 03-CHALLENGED-ASSUMPTIONS A-C02 |
| NFR-008 | Conformance testability | CORRECTNESS | BIDI_RESOLVER implementations runnable against BidiTest.txt/BidiCharacterTest.txt harness | Harness class in testing/ from day one; MVP samples; FULL pass = Phase-5 requirement + pure-Eiffel promotion gate |
| NFR-009 | Licensing | LEGAL | Permissive only; asset licenses shipped | Noto Emoji PNG Apache-2.0 (G3); LICENSE-ASSETS.md in runnable folder |
| NFR-010 | Documentation | ECOSYSTEM | README + /docs per ecosystem push rule | Present at ship |
| NFR-011 | Never-raises native boundary | CORRECTNESS | Every Uniscribe/GDI call site checks HRESULT and degrades (retry, fallback run, or SHAPING_NOTE); no exception crosses a seam | `layout` is a total function: always returns a paintable SHAPED_LAYOUT (new; from the never-raises rule bound at spec kickoff) |

## Constraints (simple_* First)

| ID | Constraint | Type | Immutable? |
|----|------------|------|------------|
| C-001 | SCOOP-compatible, void-safe Eiffel | TECHNICAL | YES |
| C-002 | simple_* first (consume simple_cairo; no ISE/Gobo text deps) | ECOSYSTEM | YES |
| C-003 | Windows 10/11 only | PLATFORM | YES |
| C-004 | Renderer is cairo 1.17.2 win32 font backend as shipped (no DLL swap) | TECHNICAL | YES for MVP |
| C-005 | Runnable-folder distribution; no installer; no new DLLs | DEPLOYMENT | YES |
| C-006 | Four-seam architecture per D-014 (deferred BIDI_RESOLVER / SCRIPT_ITEMIZER / GLYPH_SHAPER / FONT_FALLBACK) | DESIGN | YES (Larry's standing decision) |
| C-007 | Consumer scope = chat message pane display (SW_CHAT_VIEW); not a text editor | SCOPE | YES for MVP |

## Decisions Already Made

| ID | Decision | Rationale | From |
|----|----------|-----------|------|
| D-014 | simple_shaping is its own library with four deferred-class seams | Per-seam swap and testing | simple_chat research (Larry) |
| G1 (accepts D-S01/D-S02) | Uniscribe is the MVP backend for BIDI_RESOLVER, SCRIPT_ITEMIZER, GLYPH_SHAPER (flat C API, zero COM, zero DLLs); DirectWrite demoted to a stage-2 swap behind the same seams, gated on a demonstrated limit | Cheapest correct MVP; usp10 is load-bearing for GDI itself | Larry's gate 2026-09-01 |
| G2 (accepts D-S05) | FONT_FALLBACK is simple_shaping's own list+probe component in every configuration | Uniscribe mandates app-side fallback; determinism across members' machines | Larry's gate 2026-09-01 |
| G3 (closes D-019/D-S04/OQ-2) | Color emoji ship as inline Noto Emoji png/128 assets (Apache-2.0; `emoji_u1f916.png` is 🤖). Color fonts cannot render through the cairo/GDI pipeline at all (research-proven), so the shaper SEGMENTS emoji runs out for the consumer to paint as images | Only color path that exists; pixel-identical emoji on every machine | Larry's gate 2026-09-01 |
| D-S03 | Cairo bridge is HFONT-first: one SHAPING_FONT per (family, weight, style, pixel size) owning LOGFONTW + HFONT in a memory HDC + SCRIPT_CACHE + lazy cairo face; same-N rule (shape at pixel size N; cairo `set_font_size (N)` on the same face — cairo ignores LOGFONT lfHeight); positions from the shaper are authoritative | Verified: cairo-win32 draws via ExtTextOutW(ETO_GLYPH_INDEX); ScriptShape emits that HFONT's glyph ids | research/04 |
| D-S06 | Staged pure-Eiffel replacement: bidi first (full-conformance gated), itemizer second, fallback already pure, shaper native indefinitely | rustybuzz evidence: shaper port is a multi-year loss | research/04 |
| D-S07 | simple_cairo must gain a glyph API (`cairo_glyph_t` marshalling, `show_glyphs`, `glyph_extents`, two win32 face constructors) — an EXTERNAL DEPENDENCY on a separate gated repo change, not this library's code | Preserve layering: simple_widgets → simple_shaping → simple_cairo → cairo.dll | research/04 |
| D-S08 | Emoji segmentation data are compiled-in Eiffel tables generated from pinned Unicode data (emoji-test.txt RGI + emoji-zwj-sequences.txt), version-locked to the asset set | Deterministic; runnable-folder friendly | research/04 |

## Innovations to Implement

| ID | Innovation | Design Impact |
|----|------------|---------------|
| I-001 | Contract-carrying shaping seams: documented invariants of the underlying APIs become machine-checked postconditions (levels even=LTR/odd=RTL; cluster maps monotone, decreasing for RTL; run coverage exact; reorder is a permutation; fallback always renders something) | Contracts double as the cross-backend equivalence oracle — any two effectings of a seam must satisfy identical postconditions |
| I-002 | Emoji lifted out of the glyph path as first-class IMAGE runs before the shaper | Heterogeneous run model from day one (`SHAPED_RUN` = `GLYPH_RUN` \| `IMAGE_RUN`); future hook for inline attachments |
| I-003 | Staged nativization with a conformance gate per seam | Conformance harness class ships in testing/ in MVP; full-suite pass is the Phase-5 gate |
| I-004 | First Eiffel text-shaping library | API designed Eiffel-first (READABLE_STRING_32 in, contracted value objects out), not a C wrapper's shadow |

## Risks to Address in Design

| ID | Risk | Mitigation Strategy in Design |
|----|------|-------------------------------|
| RISK-001 | COM-from-Eiffel cost explodes | MVP touches zero COM (G1); DirectWrite classes appear ONLY as named future effectings in 04 |
| RISK-002 | Uniscribe frozen/removed | Seams make DirectWrite a backend swap; conformance harness verifies any swap |
| RISK-003 | Someone later "fixes" emoji via fonts | The type system forbids it: emoji NEVER reach GLYPH_SHAPER; `IMAGE_RUN` is structural (I-002); recorded as a constraint in class notes |
| RISK-004 | Bidi correctness bugs (mixed digits/punctuation) | Harness from day one; reordering happens ONLY inside BIDI_RESOLVER; permutation + level postconditions |
| RISK-005 | Emoji asset/table drift | D-S08 pinned generation; FR-007 degradation ladder with SHAPING_NOTE observability |
| RISK-006 | Font-realization mismatch (stage-2 DWrite) | HFONT-first pipeline (D-S03); MVP immune; startup glyph-id probe reserved for stage 2 |
| RISK-007 | Shaper-vs-cairo size mismatch | Same-N rule as a documented invariant of SHAPING_FONT + FR-010 round-trip test |
| RISK-008 | simple_cairo gated addition slips | D-S07 recorded as external dependency with a fallback plan (temporary externals inside simple_shaping's own cluster, migrated later) — see 07 Dependencies |
| RISK-009 | SCRIPT_CACHE concurrency under SCOOP | OQ-1 RESOLVED DEFENSIVELY: one shaper instance (facade + fonts + caches) per SCOOP processor; caches never shared; no `separate` types in the API; stated in contracts/notes — see 03 A-C01 and 05 |
| RISK-010 | Niqqud positioning quality varies by font | Default FONT_LIST puts a probed "SBL Hebrew" ahead of OS faces for the Hebrew script class (OQ-3 resolution); pointed-Hebrew acceptance test; contingency ladder unchanged |
| RISK-011 | Scope creep toward a text editor | C-007; hit-testing names reserved but deferred (FR-013) |

## Use Cases

### UC-001: Lay out and paint a chat message
**Actor:** SW_CHAT_VIEW (simple_chat thick client) on the UI processor
**Precondition:** A SIMPLE_SHAPING facade exists on this processor; asset directory configured; fonts available
**Main Flow:**
1. View receives message text `שלום 🤖 Χριστός` and knows its bubble width W and text pixel size N.
2. View calls `layout (text, W, N, fonts)` → SHAPED_LAYOUT (from cache if unchanged).
3. View sizes the bubble from `total_width`/`total_height`.
4. On paint, for each SHAPED_LINE, for each SHAPED_RUN in visual order: GLYPH_RUN → bridge draws via `show_glyphs` on the run's cairo face at size N; IMAGE_RUN → bridge blits the cached PNG surface (`CAIRO_SURFACE.make_from_png`).
**Postcondition:** Hebrew visually RTL, Greek/Latin intact, robot identical on every machine; zero shaping calls on unchanged re-paint.

### UC-002: Fallback rescue of an uncovered codepoint
**Actor:** Any consumer
**Precondition:** Requested font lacks glyphs for part of a run
**Main Flow:**
1. GLYPH_SHAPER reports missing glyphs for the item under the requested font (probe, not exception).
2. FONT_FALLBACK walks the configured list, probing each candidate; first covering font wins.
3. Run is re-shaped under the fallback font; `GLYPH_RUN.font` reports the fallback face.
4. If NO font covers: shape under the requested font anyway (missing-glyph boxes) and record a SHAPING_NOTE.
**Postcondition:** Something always renders; no exception; degradation observable.

### UC-003: Wrap a Hebrew paragraph to a narrow pane
**Actor:** SW_CHAT_VIEW
**Main Flow:** layout with small W; engine wraps at soft breaks only, never inside a cluster (base+niqqud) or emoji sequence; each line's runs are reordered visually per UAX #9 L2.
**Postcondition:** Every source character appears in exactly one line; no line exceeds W unless a single unbreakable cluster/image is wider than W (then that line is flagged overflowing).

### UC-004: Backend swap without consumer change (stage 2 / pure Eiffel)
**Actor:** Library maintainer
**Main Flow:** New effecting of a seam (e.g., EIFFEL_BIDI_RESOLVER) passes the same seam postconditions and the conformance harness (full BidiTest.txt for bidi); facade wiring switches; consumers recompile unchanged.
**Postcondition:** Identical observable behavior, proven not hoped (I-001/I-003).

### UC-005: Headless layout testing without the OS (NULL doubles)
**Actor:** Test suites (this library's and simple_chat's)
**Main Flow:** Facade created with NULL_* effectings (deterministic fake metrics); layout logic (wrap, coverage, caching, measurement) assaulted headless with no usp10/gdi32 calls.
**Postcondition:** Layout-engine contracts testable on any machine, including CI without fonts.
