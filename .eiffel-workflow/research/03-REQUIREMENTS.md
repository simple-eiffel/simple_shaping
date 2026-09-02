# REQUIREMENTS: simple_shaping

## Functional Requirements

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-001 | Shape a Unicode paragraph (STRING_32) into an ordered sequence of `GLYPH_RUN`s (font handle, pixel size, glyph indices, per-glyph positions, cluster map, direction, source range) | MUST | For "abc" in one font: one LTR run, 3 glyphs, advances > 0; cluster map monotone |
| FR-002 | Correct bidi: paragraph direction by first-strong character; embedding levels and visual reordering per UAX #9 | MUST | Sampled BidiCharacterTest.txt cases (all-Hebrew, Hebrew+digits, mixed Hebrew/Latin) produce the specified level arrays and visual order |
| FR-003 | Hebrew renders RTL with niqqud marks positioned (not overstruck on the wrong base, no tofu) | MUST | `שָׁלוֹם` and `שלום עולם 123` render correctly in the demo app; visual check against WordPad/Notepad rendering of the same string |
| FR-004 | Greek and Latin render intact in mixed lines | MUST | `שלום 🤖 Χριστός` — the D-015 acceptance string — renders with all three scripts correct |
| FR-005 | Script itemization splits runs by script (UAX #24) so each run shapes under one engine and one font | MUST | Mixed string yields ≥ 3 runs (Hebrew, emoji-image, Greek); no run mixes scripts |
| FR-006 | Emoji segmentation per UTS #51: emoji presentation (VS16), ZWJ sequences, RGI set → `IMAGE_RUN` with a codepoint-sequence asset key | MUST | 🤖 (U+1F916) → key `1f916`; `❤️` (2764 FE0F) → key `2764`; a ZWJ family sequence maps to ONE image run |
| FR-007 | Emoji image runs resolve to shipped PNG assets and report the box size to layout; unknown sequences fall back to per-codepoint images, then to the glyph path (monochrome) | MUST | Asset present: image drawn at line-height; asset absent: no crash, monochrome glyph or replacement box |
| FR-008 | Font fallback: when the requested font lacks a run's characters (missing-glyph scan / USP_E_SCRIPT_NOT_IN_FONT), retry the run against a configurable ordered font list | MUST | A CJK codepoint under "Segoe UI" renders from a fallback face, not as tofu; the run's `GLYPH_RUN.font` reports the fallback face |
| FR-009 | Line layout: greedy wrap at legal break opportunities (ScriptBreak-class soft breaks), never inside a cluster or emoji sequence; produces `SHAPED_LINE`s with height/baseline | MUST | Wrapping `שלום עולם` at a narrow width never splits base+mark; RTL word order per line is correct |
| FR-010 | Cairo bridge: for each `GLYPH_RUN`, obtain/cache a `cairo_font_face_t` via `cairo_win32_font_face_create_for_logfontw` (+`_hfont`), set matching pixel size, emit `cairo_show_glyphs` arrays | MUST | Round-trip demo: same glyph ids drawn by cairo match GDI `ExtTextOut ETO_GLYPH_INDEX` output pixel-for-pixel-close on screen |
| FR-011 | Measurement API: paragraph → total size; line → height, baseline, advance; run → extents (for bubbles, sticky-bottom, avatar alignment in SW_CHAT_THREAD) | MUST | Measured width of "abc" equals sum of advances; line height ≥ font ascent+descent |
| FR-012 | Layout cache keyed by (text, width, font config): shaping never runs during paint for unchanged lines | SHOULD | Re-paint of an unchanged 200-line pane performs zero ScriptShape calls (counter-instrumented) |
| FR-013 | Hit-testing/caret mapping (x ↔ character position within a line, RTL-aware) | FUTURE (SW_TEXT_BOX) | Deferred; API reserved on SHAPED_LINE |

## Non-Functional Requirements

| ID | Requirement | Category | Measure | Target |
|----|-------------|----------|---------|--------|
| NFR-001 | Shaping throughput | PERFORMANCE | Time to shape one 80-char mixed-script line (warm caches) | ≤ 1 ms typical; ≤ 5 ms worst |
| NFR-002 | Paint-path cost | PERFORMANCE | Work per cached line at paint | Array handoff to cairo only; no shaping calls |
| NFR-003 | Memory | PERFORMANCE | Cached layout per line | O(glyphs); hundreds of lines ≈ few MB |
| NFR-004 | Zero new DLLs (MVP) | DEPLOYMENT | Files added to the runnable folder besides simple_shaping's own code + PNG assets | 0 DLLs (usp10/gdi32 are OS-provided) |
| NFR-005 | Void safety | CORRECTNESS | ECF `void_safety` full; no CAT-calls | Compiles void-safe |
| NFR-006 | SCOOP compatibility | CORRECTNESS | No shared mutable native caches across processors; SCRIPT_CACHE confinement | Documented model; concurrency thread-safety of usp10 verified at spec phase (open question OQ-1) |
| NFR-007 | Contract coverage | CORRECTNESS | Public features carry require/ensure; documented API invariants become contracts (glyph buffer bound "1.5·n+16" per ScriptShape docs; cluster-map monotonicity; even/odd bidi levels = LTR/RTL) | 100% of public API |
| NFR-008 | Conformance testability | CORRECTNESS | BIDI_RESOLVER implementations runnable against BidiTest.txt/BidiCharacterTest.txt harness | Harness in testing/ from day one; OS backend spot-checked, pure-Eiffel backend gated on full pass |
| NFR-009 | Licensing | LEGAL | All components permissive; assets' licenses shipped | OS APIs (n/a) + Noto Emoji PNG Apache-2.0 (or Twemoji CC-BY 4.0 with attribution); LICENSE-ASSETS.md in the runnable folder |
| NFR-010 | Documentation | ECOSYSTEM | README + /docs per ecosystem push rule | Present at ship |

## Constraints

| ID | Constraint | Type | Immutable? |
|----|------------|------|------------|
| C-001 | SCOOP-compatible, void-safe Eiffel | TECHNICAL | YES |
| C-002 | simple_* first (consume simple_cairo; no ISE/Gobo text deps) | ECOSYSTEM | YES |
| C-003 | Windows 10/11 only | PLATFORM | YES (per project policy) |
| C-004 | Renderer is cairo 1.17.2 win32 font backend as shipped (no DLL swap in this project) | TECHNICAL | YES for MVP; revisit only as its own decision |
| C-005 | Runnable-folder distribution; no installer | DEPLOYMENT | YES |
| C-006 | Four-seam architecture per simple_chat D-014 (BIDI_RESOLVER / SCRIPT_ITEMIZER / GLYPH_SHAPER / FONT_FALLBACK as deferred classes) | DESIGN | YES (Larry's standing decision) |
| C-007 | Consumer scope = chat message pane display (D-015/SW_CHAT_THREAD); not a text editor | SCOPE | YES for MVP |

## Open Questions (carried to /eiffel.spec)

| ID | Question | Why it matters |
|----|----------|----------------|
| OQ-1 | Uniscribe thread-safety rules for SCRIPT_CACHE under SCOOP (confine one cache per processor? serialize shaping?) | NFR-006; not verifiable from the pages fetched in this research — must be settled from usp10 docs/testing before contracts freeze |
| OQ-2 | Noto Emoji vs Twemoji as the shipped set (Apache-2.0 no-attribution vs CC-BY attribution; 128px vs 72px; style) | NFR-009, D-019 closure detail; recommendation in 04 D-S04 is Noto, Larry's call on style |
| OQ-3 | Fallback font list contents for Hebrew niqqud-heavy text (Segoe UI vs SBL Hebrew if installed) | FR-003 quality on scholar text |
| OQ-4 | Where the WIC-decoded emoji PNGs are cached (shared with D-020 image pipeline?) | Avoid two PNG decoders in the client |
