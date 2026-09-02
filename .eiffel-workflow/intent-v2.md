# Intent v2: simple_shaping

Phase 0 refined intent = intent.md (carried in full, Part A) + deep adversarial self-review (Part B) + dependency audit (Part C) + refinements bound for Phase 1 (Part D). Review engine: Claude (Fable) self-review, 2026-09-01.

**Approval gate:** this document awaits Larry's explicit approval before `/eiffel.contracts D:\prod\simple_shaping`.

---

## Part A — Intent (unchanged from intent.md)

### What

The first Eiffel text-shaping library: mixed-script paragraph text (Hebrew with niqqud, Greek, Latin, emoji) in; cached, contracted, paintable layouts out. Glyph runs are drawn by simple_cairo via `cairo_show_glyphs` on win32 font faces (`cairo_win32_font_face_create_for_logfontw_hfont`); emoji are pixel-identical inline Noto PNG boxes. One facade (`SIMPLE_SHAPING`): `layout (text, width_pixels, pixel_size, fonts): SHAPED_LAYOUT` — a total function that never raises; degradations surface as `SHAPING_NOTE` data.

### Why

simple_widgets renders text through cairo's "toy" API (`SW_PAINTER.text` → `cairo_show_text`): no bidi, no shaping, no itemization, no font fallback. Hebrew comes out left-to-right and unshaped, mixed Hebrew/Latin lines are scrambled, emoji are tofu. This blocks simple_chat's thick client (D-015: "Thick first and no browser"), whose acceptance criterion is that `שלום 🤖 Χριστός` renders with Hebrew right-to-left, the robot as the same picture on every member's screen, and Greek intact. Downstream, every simple_widgets app that shows user text (the scholar GUI's daily Hebrew/Greek included) inherits the fix.

### Users

| User | How they use it |
|------|-----------------|
| **simple_chat's SW_CHAT_VIEW** (THE consumer; apps/client over simple_widgets, Phase 4 there) | One `SIMPLE_SHAPING` per UI processor; `layout_default (message.text, bubble_inner_width, N)` per message; bubble sized from `total_width/total_height`; paint via `SHAPING_CAIRO_BRIDGE.draw_layout`; unchanged re-paint hits the cache (zero shaping calls) |
| simple_widgets (`SW_PAINTER.draw_shaped_layout`, later `SW_TEXT_BOX`) | Delegates to the bridge; hit-testing names reserved for the future text box |
| Scholar GUI / future simple_* apps | Hebrew + Greek display with niqqud correctly positioned |
| Test suites (this library's and simple_chat's) | `make_with_backends` + NULL_* doubles: headless layout testing, no usp10/gdi32 (CI-safe) |

### Bound Decisions (carried verbatim — NEVER reopened here)

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

*(Note: simple_chat's 10-ADDENDUM-THICK-CLIENT.md still says "Backends: DirectWrite first" — that line predates and is superseded by Larry's G1 gate of 2026-09-01. Do not re-derive backend order from the addendum.)*

### Acceptance Criteria (deterministic, testable; centered on SW_CHAT_VIEW)

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

### Out of Scope

- Text-editor machinery: styles engine, justification, hyphenation, rich multi-style runs (C-007 — consumer is a chat message pane).
- Arabic/Indic/Thai shaping GUARANTEES (whatever Uniscribe gives is an untested bonus).
- Printing/PDF text extraction; vertical text; kashida.
- Color-font (COLR/CBDT) rasterization — dead end through cairo 1.17.2 win32 (G3 exists because of this).
- Hit-testing/caret/selection — FUTURE (FR-013); `character_index_at_x` / `x_at_character_index` names reserved on SHAPED_LINE, not compiled this cycle.
- DirectWrite backends (stage-2 slots, named only); pure-Eiffel bidi/itemizer (staged behind full-conformance gates, D-S06).
- The simple_cairo glyph API itself (D-S07 — external gated repo change) and the simple_widgets adoption (`SW_PAINTER.draw_shaped_layout` — second gated repo change, Phase 7 coordination).
- Cross-machine pixel-identical TEXT rendering (fonts are not shipped; only emoji are pixel-identical by design — see Q7).

### MML Decision (REQUIRED)

**Decision:** YES-Required
**Rationale:** Ecosystem default, bound at kickoff. The contract design (05) already maps every collection-bearing class to MML models; seam postconditions (coverage partitions, permutation reorder, monotone cluster maps) and cache frame conditions (`|=|`) are unstatable without them. simple_mml exists and is the ecosystem's own model library.

---

## Part B — Deep Intent Review (12 probing questions, with recommended answers)

Each question attacks something the spec left genuinely open. Machine facts below were verified on Larry's Windows 11 Pro machine (C:\Windows\Fonts, 2026-09-01). Larry can override any recommendation at the gate.

### Q1. What should `FONT_LIST.make_default` actually contain, given what is installed on Larry's machine and guaranteed on members' machines?

- **Why it matters:** The spec's default Hebrew prepend is `["SBL Hebrew" (probed), "Segoe UI", "David", "Tahoma"]`. Verified: **SBL Hebrew is NOT installed** on Larry's machine (nor Ezra SIL); **classic Windows "David" is NOT installed either** (david.ttf absent — the Hebrew supplemental-fonts optional feature is off). What IS installed: full Segoe UI family, Tahoma, Arial, Times New Roman, Calibri, Courier New, Palatino Linotype, plus third-party Hebrew faces (Culmus: DavidCLM, DavidLibre, FrankRuehlCLM/Hofshi, MiriamCLM/Libre/Mono, NachlieliCLM; and Noto Sans Hebrew). Members' machines will have NONE of the third-party faces. A default naming absent families must not break layout or the digest.
- **Alternatives:** (a) hardcode only guaranteed Win10/11 faces; (b) keep aspirational scholar faces first with a creation-time existence probe; (c) per-machine discovery of "best Hebrew face".
- **RECOMMENDED:** (b), sharpened: Hebrew prepend = `["SBL Hebrew", "Ezra SIL", "Noto Sans Hebrew", "David Libre", "David"]` (all existence-probed at realization; absent families dropped from the effective list with one statistics-visible note) followed by guaranteed anchors `["Segoe UI", "Tahoma", "Arial"]`. Greek prepend = `["Segoe UI", "Palatino Linotype", "Times New Roman"]`. General list = `[UI face ("Archivo" from SW_THEME — Latin-only, verified), "Segoe UI", "Arial", "Tahoma"]`. **Segoe UI is the deterministic backstop** — present on every Win10/11 install with full Hebrew + niqqud mark positioning. Pointed-Hebrew acceptance (AC-2) runs against the effective list on the build machine; RISK-010's contingency ladder unchanged.

### Q2. How big should LAYOUT_CACHE be, and what is the real eviction pattern under the chat pane's scrolling?

- **Why it matters:** The consumer keeps hundreds of messages; keys include width, so every window resize mints a NEW generation of entries while the old generation becomes dead weight that plain LRU only gradually expels. Undersizing reintroduces shaping on scroll (kills FR-012/NFR-002); oversizing bloats (NFR-003).
- **Alternatives:** (a) default 512, plain LRU (spec); (b) generational purge on width change (drop all entries whose width ≠ current); (c) cost-aware eviction.
- **RECOMMENDED:** (a) for MVP — 512 ≈ 2.5× a 200-message scrollback, few MB at chat sizes; scroll is LRU-friendly (recency = visibility). Add ONE consumer-guidance note (not code): SW_CHAT_VIEW should re-layout on resize-END (or debounced), not per resize tick, or live-resize thrash evicts the useful generation. Defer (b) until Phase 5 measurement proves need; capacity stays configurable (`set_cache_capacity`).

### Q3. What exactly does `measured_width` promise for empty and whitespace-only text, and do trailing spaces count?

- **Why it matters:** Bubbles are sized from measurement; `""` → 0.0 is contracted, but `"   "` is not pinned, and wrap-fit treatment of line-trailing spaces changes which lines "fit" (AC-2 determinism).
- **Alternatives:** (a) trim whitespace before measuring; (b) measure everything as shaped, spaces included; (c) measure all, but exclude line-TRAILING whitespace from the wrap fit test.
- **RECOMMENDED:** (b) for `measured_width` — whitespace-only text returns its real shaped advance (> 0.0), so a "   " message gets a visible bubble (matches FR-N01's spirit; chat must not collapse deliberate spaces); PLUS (c) for LINE_LAYOUT_ENGINE's fit test — the breaking space belongs to the preceding line but its advance is excluded from the fit comparison (the industry-standard hanging-whitespace rule; otherwise wrap points shift one word early). Bind both as Phase-1 contract clauses: `whitespace_measures: a_text.count > 0 implies Result >= 0.0` stays, add `empty_is_zero` (already present) and a LINE_LAYOUT_ENGINE postcondition naming the trailing-space exclusion.

### Q4. How much of the emoji LOOKUP ladder is MVP when the acceptance string needs only single-codepoint 🤖?

- **Why it matters:** UTS #51 spans single codepoints, VS16 pairs (❤️), skin-tone modifiers, ZWJ families, and flag pairs. Under-building silently splits a family into three heads (worse than tofu); over-building delays MVP.
- **Alternatives:** (a) single codepoints + VS16 only, ZWJ deferred; (b) full RGI segmentation + full ladder, coverage limited by shipped assets; (c) full segmentation + full asset set.
- **RECOMMENDED:** (b) → (c) cheaply: the SEGMENTER is table-driven and the tables are GENERATED (D-S08), so full RGI longest-match segmentation (VS16, ZWJ, skin tones, flags) is MVP — the marginal cost over "single codepoint" is generator work, not hand code, and FR-006's own acceptance already demands ZWJ-family → ONE image run. The LADDER (full-sequence asset → per-codepoint assets → PLAIN degrade + note, A-C06) is MVP as specified. Asset BREADTH: ship the full Noto png/128 set (~3.7k files; tens of MB — acceptable beside a chat exe, maximal determinism). If Larry wants a slimmer folder, a curated subset is a Phase-3 data decision — the code is coverage-agnostic and the ladder makes gaps graceful. Default: full set.

### Q5. When Uniscribe itself errors on a run (not a coverage miss — a hard HRESULT failure), what does the user SEE: tofu boxes or a dropped run?

- **Why it matters:** 05's boundary pattern says "empty-but-valid result + note", but an EMPTY shaped item for a non-empty character range would make degradation INVISIBLE (dropped text) and strains coverage/cluster contracts — a silent-drop by another name, violating DR-010's spirit.
- **Alternatives:** (a) drop the run, note it; (b) synthesize a tofu run — one .notdef-style glyph (id 0) per character at a deterministic advance (pixel_size/2), note it; (c) raise after all.
- **RECOMMENDED:** (b), binding: on any unrecoverable native failure the item degrades to a SYNTHESIZED TOFU RUN — glyph id 0 per character, advance = pixel_size/2, cluster map identity — plus `Note_backend_error_recovered` with the source range. The user sees boxes exactly where the text is; nothing silently vanishes; coverage and cluster contracts hold unweakened. Phase 1 must adjust the "empty-but-valid" wording in the boundary pattern to "tofu-but-valid" for non-empty items (refinement R3 below); (c) is forbidden by NFR-011.

### Q6. Which Unicode version pins EMOJI_DATA_TABLES, and what exactly is recorded?

- **Why it matters:** DR-013 requires tables and assets in lockstep; "pinned" without a number is drift waiting to happen (RISK-005), and emoji-test.txt versions change RGI membership.
- **Alternatives:** (a) latest Unicode at acquisition; (b) the Unicode version of the chosen Noto Emoji RELEASE TAG; (c) freeze an old known-good (15.1).
- **RECOMMENDED:** (b): the ASSETS are the constraint, so pin to the Unicode emoji version of the exact Noto Emoji release acquired (acquire the latest tagged release at Phase 3; releases in the 2.04x line cover Unicode 15.1 emoji — verify the tag's stated version at download). Record in tools/: release tag, source URL, archive sha256, and the emoji-test.txt/emoji-zwj-sequences.txt version downloaded to match; emit that version string as the DR-013 constant in generated `EMOJI_DATA_TABLES`; catalog invariant compares it (already specified). Refreshing later = re-run generator + swap assets together, one commit.

### Q7. Does the probe-based FONT_LIST break G2's "determinism across members' machines," and is the digest computed pre- or post-probe?

- **Why it matters:** Two truths collide: G2 promises deterministic rendering; machines carry different fonts (Larry has Culmus + Noto Hebrew; members won't). And FR-N03's value-based digest must decide: same CONFIGURED list on two machines, different EFFECTIVE lists — same cache key or not?
- **Alternatives:** (a) digest over the configured list; (b) digest over the post-probe effective list; (c) ship fonts to make machines identical.
- **RECOMMENDED:** (b) — digest over the post-probe EFFECTIVE list (the cache is per-processor per-machine; a key must name what layout actually depends on, or a font install mid-session serves stale layouts). State honestly in the intent: G2's determinism is POLICY determinism (same list, same probe order, same decision procedure on every machine) — pixel-identical TEXT across machines is out of scope (only emoji are pixel-identical, G3). If cross-machine identity for Hebrew ever becomes a requirement, the lawful path is shipping an OFL-licensed face (e.g., Ezra SIL, David Libre) in the runnable folder — a future data decision, not MVP. (SBL Hebrew's license does not permit redistribution without permission — do not ship it.)

### Q8. What is the "primary face" behind `line_height`, when the general-list head (theme face "Archivo", Latin-only — verified in SW_THEME) cannot render Hebrew?

- **Why it matters:** FR-N01 sizes empty messages by `line_height`; real Hebrew lines will render in Segoe UI (taller ascent/descent than a Latin display face) — bubbles sized from `line_height` but filled by layout would jitter between empty and non-empty messages.
- **Alternatives:** (a) primary = first family of the general list, document the mismatch; (b) primary = max metrics across the effective general list; (c) force consumers to always size from layout.
- **RECOMMENDED:** (a) + (c) as guidance: `line_height` = ascent+descent of the FIRST REALIZED family of the general list (deterministic, cheap, contracted `Result > 0`), and the consumer rule is written into the interface docs: SIZE BUBBLES FROM `layout.total_height` ALWAYS (it is cached; there is no cost), use `line_height` only for the empty-message minimum (FR-N01) and pane pre-allocation. (b) over-inflates every Latin-only line and still cannot anticipate fallback faces.

### Q9. `layout_default` ensures only `Result /= Void` — is a convenience feature allowed a weaker contract than the operation it wraps?

- **Why it matters:** SW_CHAT_VIEW's per-message call IS `layout_default`; if its contract is vacuous, the consumer's proof obligations all detour through implementation knowledge ("it just calls layout") — exactly what DBC forbids.
- **Alternatives:** (a) leave it; (b) restate layout's observable postconditions; (c) postcondition `Result = layout (...)` (re-entrant call in the ensure).
- **RECOMMENDED:** (b): Phase 1 must copy the observable clauses onto `layout_default` (total_function, source_kept, at_least_one_line, coverage, width_respected, cached_now with default_fonts) — NOT (c), which would double the memo effect and re-shape on a cold cache inside an assertion. Same treatment for `measured_width`'s relationship to layout (its two clauses suffice; add `single_line_equivalence` as a note, tested not asserted).

### Q10. What EXACTLY does `statistics.shape_calls` count when fallback PROBES also invoke the shaper — and can a probe inflate the FR-012 "zero shaping on repaint" assertion?

- **Why it matters:** AC-3's determinism hangs on this number. LIST_FONT_FALLBACK probes BY SHAPING (G2). If probes increment `shape_calls`, a cold-cache probe storm makes the counter unusable as the FR-012 oracle; if nothing counts probes, fallback cost is invisible (NFR-001 tuning blind).
- **Alternatives:** (a) count every seam-3 invocation in shape_calls; (b) shape_calls = layout-path shapes only, fallback_probes = probe shapes only, disjoint; (c) count in both.
- **RECOMMENDED:** (b), bound as the counters' DEFINITION in Phase 1 class notes: `shape_calls` = shaping performed to produce runs; `fallback_probes` = coverage probes (whether or not their result is reused as the run's shape — reuse is an optimization, counted as the probe it was); cache-hit path performs ZERO of both (that pair of facts is AC-3's assertion). Counters live in the facade/engines, not inside seam effectings (doubles stay dumb; NULL shaper needs no counting duty).

### Q11. A digest-keyed cache can COLLIDE — two texts, one key, the WRONG layout painted. Acceptable?

- **Why it matters:** LAYOUT_CACHE is keyed by a STRING_8 digest of (text, width, size, fonts, asset dir). A collision would paint another message's layout — a silent correctness failure invisible to every contract (`source_kept` would catch it only if someone asserts it on the HIT path).
- **Alternatives:** (a) trust the hash; (b) store the full key tuple in the entry and VERIFY on hit (collision → miss → reshape); (c) full text as the key.
- **RECOMMENDED:** (b): each cache entry keeps its full (text, width, size, fonts-digest, asset-dir) tuple; a hit compares text (O(n), trivial next to shaping) and demotes mismatch to a miss. This makes `layout`'s `source_kept` postcondition TRUE BY CONSTRUCTION on every path, and the digest is free to be fast (non-cryptographic). (c) bloats keys for multi-KB pastes; (a) gambles display correctness on hash luck.

### Q12. FONT_LIST carries families only — where do WEIGHT and ITALIC enter `layout`, since SHAPING_FONT models both and the fallback contract preserves them?

- **Why it matters:** The facade signature (text, width, size, fonts) has no style parameter; yet SHAPING_FONT's identity is (family, weight, style, size) and seam 4 promises same_style. Either style is a hidden constant (must be documented) or a missing parameter (API break later — sender-name bold is a known chat want).
- **Alternatives:** (a) MVP freezes regular/upright at the facade; styled text arrives later as a styled-runs API (out of scope, C-007); (b) add weight/italic parameters to layout now; (c) put style on FONT_LIST.
- **RECOMMENDED:** (a): MVP shapes everything regular-weight upright — bound as a documented facade note and a SHAPING_FONT creation default; the seam and font model KEEP weight/italic (already specified) so the future styled-runs extension changes the facade only, never the seams or the run model. SW_CHAT_VIEW renders sender names as separate one-style layouts if bold is wanted before styled runs exist. (b) invites per-call churn into the cache key for a capability with no MVP consumer; (c) confuses fallback policy with text attributes.

---

## Part C — Dependency Audit (simple_* First)

Audited against the live ecosystem at D:\prod (directory enumeration + targeted source verification, 2026-09-01).

| Need | Resolution | Verified |
|------|-----------|----------|
| Model queries / frame conditions | **simple_mml** | EXISTS — D:\prod\simple_mml\src (mml_sequence.e, mml_map.e, mml_set.e, mml_bag.e, mml_relation.e, mml_interval.e) |
| Faces/surfaces/PNG decode | **simple_cairo** | EXISTS — `CAIRO_SURFACE.make_from_png` present (src/cairo_surface.e:26,65): emoji surfaces need NO new decode dependency (A-C08 — zero WIC) |
| Glyph drawing API | **D-S07 gated addition to simple_cairo** (EXTERNAL, separate repo, Larry's gate) | GAP CONFIRMED — no `show_glyphs`/`cairo_glyph_t` binding in src/cairo_context.e (only a glyph grid-fitting comment); cairo-win32 headers already in its Clib. Fallback: temporary externals in simple_shaping's own cluster, migrated later (RISK-008) |
| Test infrastructure | **simple_testing** | EXISTS — D:\prod\simple_testing (TEST_SET_BASE per ecosystem conventions) |
| Bidi/itemization/shaping | OS usp10.dll + gdi32.dll (G1) | OS-provided on Win 10/11; zero shipped DLLs; link order Usp10.lib before gdi32.lib → build docs |
| Emoji assets | Noto Emoji png/128 (Apache-2.0) → assets/ + LICENSE-ASSETS.md | NOT YET ACQUIRED (no local copy found under D:\prod; D:\prod\simple_shaping has no assets/ yet) — Phase-3 acquisition task with Q6's pinning record |
| Unicode data | emoji-test.txt (RGI) + emoji-zwj-sequences.txt → generated EMOJI_DATA_TABLES; BidiTest.txt + BidiCharacterTest.txt as fixtures | Generator in tools/ (Phase-3 scripted task); D-S08/DR-013 |
| Fundamental types | ISE `base` only | Allowed by policy (HASH_TABLE, ARRAYED_LIST, IMMUTABLE_STRING_*) |

**Checked for and confirmed absent (no simple_* equivalent exists):** simple_unicode, simple_text, simple_font, simple_image, simple_png — none exist; none are needed (tables are generated in-repo; PNG decode rides simple_cairo; fonts are OS handles).

**Explicitly avoided:** ISE/Gobo text machinery (Gobo has no bidi — research-verified); WIC/COM (A-C08); HarfBuzz/SheenBidi DLLs (zero-DLL policy; contingency only, RISK-010 ladder).

**Consumers (not dependencies):** simple_widgets (SW_PAINTER.draw_shaped_layout — second gated repo change, Phase 7) and simple_chat's SW_CHAT_VIEW (apps/client, "Phase 4, after simple_shaping" per its addendum). Layering: simple_widgets → simple_shaping → simple_cairo → cairo.dll; simple_shaping → (usp10, gdi32).

### Gaps Identified (Potential simple_* Libraries)

| Gap | Current Workaround | Proposed simple_* |
|-----|-------------------|-------------------|
| Uniscribe/GDI font externals live in-library (src/uniscribe/: USP10_API, GDI32_API) | By design this cycle (single consumer) | Extract `simple_uniscribe` ONLY if a second consumer ever appears — recorded, no action now |
| Unicode data tables (emoji properties; someday UAX #9/#24 tables for the pure-Eiffel effectings) | Generated per-library (tools/ + emoji/generated/) | A future `simple_unicode_data` would serve EIFFEL_BIDI_RESOLVER's tables too — D-S06 stage-1 concern, not MVP |

---

## Part D — Refinements bound for Phase 1 (from this review; NOT reopening bound decisions)

- **R1 (Q1):** `FONT_LIST.make_default` lists per Q1; existence probe at realization; absent families dropped from the effective list, noted once via statistics.
- **R2 (Q3):** `measured_width` counts whitespace as shaped; LINE_LAYOUT_ENGINE's fit test excludes line-trailing whitespace advances (contract clause).
- **R3 (Q5):** Never-raises boundary wording becomes "tofu-but-valid": unrecoverable native failure on a non-empty item synthesizes a tofu run (glyph id 0 per char, advance pixel_size/2, identity clusters) + note — never an empty item, never a dropped range.
- **R4 (Q6):** DR-013 constant = the acquired Noto release's Unicode emoji version; tools/ records tag + URL + sha256 + data-file versions.
- **R5 (Q7):** `FONT_LIST.digest` is computed over the post-probe EFFECTIVE list.
- **R6 (Q9):** `layout_default` (and by the same rule every convenience wrapper) restates the wrapped operation's observable postconditions.
- **R7 (Q10):** Counter definitions bound: shape_calls = run-producing shapes; fallback_probes = probe shapes; disjoint; both zero on cache hits; counted in facade/engines, never in seam effectings.
- **R8 (Q11):** LAYOUT_CACHE entries carry their full key tuple; hits verify text equality; collision demotes to miss.
- **R9 (Q12):** MVP style freeze (regular/upright) documented at the facade; SHAPING_FONT keeps weight/italic so styled runs later touch only the facade.
- **R10 (Q2/Q8):** Two consumer-guidance notes into the interface docs: re-layout on resize-end (debounce), and size bubbles from `layout.total_height` (line_height is for empty-message minimums only).

**Approval request:** Intent document refined. Approve to proceed to Phase 1 (`/eiffel.contracts D:\prod\simple_shaping`)? — awaiting Larry's gate.
