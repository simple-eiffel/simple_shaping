# CHALLENGED ASSUMPTIONS: simple_shaping

Attack pass over the research and the kickoff instructions. The research's four assumptions A-1..A-4 were already verdict-stamped there (A-1 bridge CONFIRMED, A-2 Uniscribe-3-of-4 CONFIRMED, A-3 color-emoji REFUTED, A-4 Eiffel-prior-art REFUTED); this file challenges what the SPEC must now decide on top of them.

## Assumptions Challenged

### A-C01: "Uniscribe SCRIPT_CACHE semantics are safe enough under SCOOP if we just document it" (OQ-1)
**Challenge:** The research explicitly could NOT verify usp10 thread-safety from fetched documentation ("not verifiable from the pages fetched"; RISK-009). Designing as if a promise exists would be riffing on an absent source.
**Evidence for danger:** SCRIPT_CACHE is a mutable per-font native cache passed by address into every ScriptShape/ScriptPlace call; HDC selection state (SelectObject) is inherently per-thread-unsafe; Uniscribe docs are silent on concurrent SCRIPT_CACHE use.
**Evidence against danger:** Chat shapes on the UI processor anyway; nothing in the consumer needs cross-processor shaping.
**Verdict:** NEEDS_VALIDATION — and the design must not depend on the answer.
**Action (RESOLUTION, bound into the design):** Design defensively as instructed at kickoff: (1) one SIMPLE_SHAPING instance — with its FONT_REGISTRY, all SHAPING_FONTs, every SCRIPT_CACHE, HDCs, and the LAYOUT_CACHE — per SCOOP processor; (2) no cache, font, or native handle is ever shared or passed `separate`; (3) the public API declares NO `separate` types, so the compiler cannot smuggle a facade across processors usefully; (4) the confinement is stated in class notes and in the contracts where statable (creation postconditions and invariants tie fonts to their owning registry; see 05 "Concurrency contracts"). A future verified thread-safety claim could only RELAX this; nothing breaks if usp10 turns out stricter than hoped. DR-012.

### A-C02: "The 1.5·n+16 glyph buffer figure is an API invariant that should become a postcondition" (NFR-007 wording)
**Challenge:** The ScriptShape documentation presents 1.5n+16 as a RECOMMENDED BUFFER SIZE ("sufficient for 99% of strings"), with E_OUTOFMEMORY as the signal to retry larger — i.e., it is explicitly NOT a guaranteed output bound. A hard postcondition `glyph_count <= 3*n//2 + 16` would be falsified by rare legitimate shapes and would then crash a correct program at the contract check.
**Verdict:** INVALID as a postcondition; VALID as implementation guidance.
**Action:** Reclassify (recorded in 01 NFR-007): the figure governs the FIRST allocation in UNISCRIBE_GLYPH_SHAPER with a documented grow-and-retry loop on E_OUTOFMEMORY. The contracts that REMAIN hard: cluster-map monotonicity and range-validity, coverage, non-negative advances, level parity. This is the one deliberate deviation from the research's NFR-007 wording — a weaker claim the sources actually support.

### A-C03: "Emoji segmentation runs BEFORE everything (D-S04: 'before itemization/shaping')"
**Challenge:** If the segmenter literally ran before BIDI resolution and levels were computed only on the emoji-stripped remainder, image boxes would carry NO bidi level — and an emoji inside a Hebrew sentence would be positioned wrong in the visual line (emoji are bidi-neutral and take surrounding levels per UAX #9).
**Evidence:** UAX #9 resolves neutrals from context; removing characters changes neighboring resolution (e.g., `שלום 🤖 שלום` — the ON between two R's must resolve R).
**Verdict:** VALID as written (D-S04 says before ITEMIZATION/SHAPING, not before bidi) — but under-specified.
**Action:** Pipeline fixed as: bidi over the FULL text → segmentation (emoji spans inherit their characters' resolved levels) → itemization of plain spans only → shaping. D-S04's guarantee is preserved: the shaper never sees an emoji sequence. Recorded as DR-005 + the 02 pipeline note. No research contradiction — a refinement.

### A-C04: "SHOULD-priority FR-012 (layout cache) can slip out of MVP"
**Challenge:** The consumer's success criterion "re-paint of an unchanged pane performs zero shaping calls" and NFR-002 make the cache load-bearing for the chat pane at hundreds of visible lines; SW_CHAT_THREAD re-wraps every message on every paint today — the exact behavior being replaced.
**Verdict:** MODIFY — keep FR-012's SHOULD label (research fidelity) but bind it into the facade's design now: `layout` reads/writes LAYOUT_CACHE by design, not as an add-on. The cache is in the MVP class inventory; only its eviction sophistication (plain LRU, bounded) is minimal.

### A-C05: "The facade should take `a_fonts` on every call" (kickoff signature)
**Challenge:** Chat calls layout for every message with the same font policy; forcing the list through every call invites accidental cache-key churn (a fresh FONT_LIST per call would defeat FR-012 unless keys are value-compared).
**Verdict:** VALID (keep the kickoff signature) with a design consequence: FONT_LIST is an immutable-after-configuration value whose cache-key digest is VALUE-based (model comparison), so equal lists hit the same cache entries; plus a convenience `layout_default` using the facade's `default_fonts`. Both appear in 06.

### A-C06: "IMAGE_RUN needs a fallback story inside the run (is_resolved flag)"
**Challenge:** If IMAGE_RUN can be unresolved, every consumer must handle a broken-image case forever — a permanent tax for a state the library can preclude.
**Verdict:** INVALID — stronger design chosen: resolution happens BEFORE run construction. EMOJI_SEGMENTER consults EMOJI_ASSET_CATALOG; a sequence without a full-sequence asset retries per-codepoint (FR-007 ladder); codepoints still unresolved stay PLAIN text into the glyph path (monochrome or tofu boxes + SHAPING_NOTE). Invariant: every IMAGE_RUN is resolved (DR-006). The degradation ladder lives in ONE place (segmenter), not in every consumer.

### A-C07: "ScriptBreak belongs to the GLYPH_SHAPER seam since it is a Uniscribe call"
**Challenge:** Break opportunities are a property of characters and their script analysis, not of glyphs or fonts; putting them on GLYPH_SHAPER would force layout to shape before it can wrap and would break the NULL-double story for headless wrap tests.
**Verdict:** INVALID — `soft_breaks` goes on SCRIPT_ITEMIZER (Uniscribe's ScriptBreak takes the SCRIPT_ANALYSIS produced by ScriptItemize; same-backend affinity holds). D-014's four-seam count is preserved; no fifth seam.

### A-C08: "Emoji PNG decode should share simple_chat's D-020 WIC pipeline" (OQ-4)
**Challenge:** WIC is a COM dependency living in the CLIENT app; simple_shaping must not depend upward on a consumer's image pipeline, and RISK-001 wants zero COM here.
**Evidence:** simple_cairo ALREADY binds `cairo_image_surface_create_from_png` (`CAIRO_SURFACE.make_from_png`, verified in D:\prod\simple_cairo\src\cairo_surface.e:65) — cairo 1.17.2 ships PNG functions.
**Verdict:** RESOLVED — OQ-4 answered: the bridge's EMOJI_SURFACE_CACHE decodes via `CAIRO_SURFACE.make_from_png`. Zero COM, zero new dependency, no D-S07 growth (make_from_png already exists). simple_chat may still WIC-decode its own attachment images; emoji never touch WIC.

## Requirements Questioned

### FR-010 (cairo bridge inside THIS library)
**Challenge:** Should painting live in simple_widgets instead, keeping simple_shaping renderer-agnostic?
**Verdict:** KEEP — the research assigns FR-010 here, D-S07's layering puts simple_shaping above simple_cairo, and the same-N rule couples shaping and face sizing so tightly that splitting them across repos would smear one invariant over two owners. The bridge is a distinct cluster (`src/bridge/`) so a future renderer ignores it cleanly.

### FR-013 (hit-testing) 
**Verdict:** KEEP as FUTURE. Feature names reserved on SHAPED_LINE (`character_index_at_x`, `x_at_character_index`) and listed in 06 as reserved (no contracts frozen for them in this cycle) — reserving names now prevents a breaking rename when SW_TEXT_BOX arrives (RISK-011 fence intact).

### NFR-001 (≤ 1 ms/line typical)
**Challenge:** Unverifiable at spec time.
**Verdict:** KEEP — plausible for Uniscribe on 80-char lines; made testable via the counter/timer instrumentation that FR-012's acceptance already requires. Phase-5 measures it.

## Missing Requirements Identified

| ID | Missing Requirement | How Discovered |
|----|---------------------|----------------|
| NFR-011 | Never-raises native boundary; `layout` is a TOTAL function (always returns a paintable layout; degradations are SHAPING_NOTEs) | Bound at spec kickoff; implied by research's FR-007 "no crash" but never stated as a cross-cutting rule. Added to 01. |
| FR-N01 | Empty and whitespace-only text must still produce one measurable line (chat panes size empty/blank messages by font height) | UC walk-through of SW_CHAT_VIEW; research silent. Acceptance: `layout ("")` → 1 line, 0 runs, height = font ascent+descent, no notes. |
| FR-N02 | The facade must expose shaping-call counters (shape-call count at minimum) | FR-012's own acceptance criterion says "counter-instrumented" — the counter must therefore be API, not test scaffolding. Modeled as `statistics` query on the facade. |
| FR-N03 | FONT_LIST equality/digest must be value-based so equal configurations share cache entries | A-C05. |

## Design Constraints Validated

| Constraint | Valid? | Notes |
|------------|--------|-------|
| simple_* first | YES | simple_cairo (existing) + simple_mml (models) are the only library deps; usp10/gdi32 are OS, not libraries; NO ISE/Gobo text machinery |
| SCOOP-compatible | YES | Via confinement (A-C01); no `separate` in API |
| Void-safe | YES | All results attached; detachable appears only where absence is a real state (e.g., probe results); XOR-style invariants on option-like values |
| Four seams (C-006/D-014) | YES | Exactly four deferred seam classes; ScriptBreak placement (A-C07) keeps the count |
| Zero new DLLs (C-005/NFR-004) | YES | Externals bind OS usp10/gdi32; cairo.dll already ships with simple_widgets; PNG assets are data |
| Runnable folder | YES | Assets + LICENSE-ASSETS.md copied beside the exe; no installer, no registry |
| cairo 1.17.2 as shipped (C-004) | YES | Bridge uses only 1.17.2-present symbols (verified in research: cairo-win32.h lines 82/88; PNG functions present via simple_cairo) |
