# DESIGN VALIDATION: simple_shaping

## OOSC2 Compliance

| Principle | Status | Evidence |
|-----------|--------|----------|
| Single Responsibility | PASS | 39 designed classes, one job each (04 inventory): facade coordinates; seams answer one question each; engines own one algorithm; values hold one result shape |
| Single Choice | PASS | Backend wiring decided ONLY in SIMPLE_SHAPING creation; Noto naming ONLY in EMOJI_ASSET_CATALOG; same-N ONLY in SHAPING_FONT/bridge; degradation ladder ONLY in EMOJI_SEGMENTER (A-C06) |
| Open/Closed | PASS | Four deferred seams closed for modification, open for DIRECTWRITE_*/EIFFEL_* effectings (named, undesigned); SHAPED_RUN deliberately closed over two heirs with the closure documented as a domain constraint (RISK-003) |
| Liskov Substitution | PASS | 04 inheritance table: every effecting satisfies the seam's full contract (contracts-as-oracle, I-001); GLYPH_RUN/IMAGE_RUN honor all SHAPED_RUN queries |
| Interface Segregation | PASS | 06: measuring consumers see facade+values only; painting adds the bridge; tests see seams+doubles; only Phase 4 sees USP10_API/GDI32_API |
| Dependency Inversion | PASS | Facade and LINE_LAYOUT_ENGINE depend on the four ABSTRACT seams; Uniscribe appears only in effectings; injection via make_with_backends |
| Information Hiding | PASS | Native handles {NONE}/selectively exported; consumers never see HFONT, SCRIPT_CACHE, HRESULT, or glyph marshalling |
| Genericity | PASS (considered, declined) | 04: no type parameter earns its keep; recorded deliberately |

## Eiffel Excellence

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Command-Query Separation | PASS | 05/06 CQS tables; `layout` memo effect DECLARED and confined to non-abstract state; fluent setters follow simple_cairo house style |
| Uniform Access | PASS | Metrics/status as queries; consumers cannot tell attribute from function anywhere in the API |
| Design by Contract | PASS | 05: every public feature carries require/ensure; seam postconditions are the cross-backend oracle; invariants on every value class |
| MML models | PASS | 05 model table: 14 collection-bearing classes mapped to MML_SEQUENCE/MML_MAP; frame conditions via `|=|` on cache and bridge |
| Inheritance is IS-A only | PASS | Runs and seam effectings only; constants mixin conventional |
| Void safety | PASS | All results attached (total functions); detachable only in LAYOUT_CACHE.item where absence is real |
| SCOOP compatibility | PASS | By confinement (OQ-1 resolution): no `separate` types in the API; per-processor facade; DR-012 notes + statable ownership contracts (05) |
| simple_* first | PASS | simple_mml + simple_cairo only; zero ISE/Gobo text machinery; OS APIs are not libraries |
| Testable | PASS | NULL doubles for all four seams (UC-005 headless); LINE_LAYOUT_ENGINE a class for that reason; statistics counters make FR-012 assertable; conformance harness class in testing/ |

## Requirements Traceability (research FR/NFR tables → design)

| Requirement | Addressed By | Status |
|-------------|--------------|--------|
| FR-001 shape to glyph runs | GLYPH_SHAPER.shape → SHAPED_ITEM → GLYPH_RUN (ids, positions, cluster map, direction, source range); DR-004 contracts | TRACED |
| FR-002 bidi per UAX #9, first-strong | BIDI_RESOLVER.resolve/reorder contracts (DR-001/DR-002); Direction_auto; harness NFR-008 | TRACED |
| FR-003 Hebrew RTL + niqqud | UNISCRIBE_GLYPH_SHAPER (ScriptShape/Place); cluster invariants; OQ-3 default FONT_LIST with probed SBL Hebrew; pointed-Hebrew acceptance test (RISK-010) | TRACED |
| FR-004 Greek/Latin intact | Itemization DR-003 + per-item fonts; D-015 acceptance demo (07) | TRACED |
| FR-005 itemization UAX #24 | SCRIPT_ITEMIZER.itemize coverage contracts (DR-003) | TRACED |
| FR-006 UTS #51 emoji → IMAGE_RUN keys | EMOJI_SEGMENTER + EMOJI_ASSET_CATALOG.asset_key (VS16 dropped, ZWJ joined); EMOJI_DATA_TABLES (D-S08) | TRACED |
| FR-007 asset resolution + degradation ladder | A-C06: ladder inside segmenter; IMAGE_RUN always resolved (DR-006); SHAPING_NOTE observability | TRACED (strengthened: no broken-image state reaches consumers) |
| FR-008 font fallback list+probe | FONT_FALLBACK seam + LIST_FONT_FALLBACK (G2); FALLBACK_CHOICE.no_silent_drop (DR-010); UC-002 | TRACED |
| FR-009 cluster-safe greedy wrap | LINE_LAYOUT_ENGINE + SCRIPT_ITEMIZER.soft_breaks (A-C07); DR-007; per-line reorder DR-002 | TRACED |
| FR-010 cairo bridge, same-N | SHAPING_FONT (D-S03 holder) + SHAPING_CAIRO_BRIDGE + D-S07 dependency; DR-009; round-trip test Phase 5 | TRACED |
| FR-011 measurement API | Facade measured_width/line_height + SHAPED_LAYOUT/LINE/RUN metric queries | TRACED |
| FR-012 layout cache, zero shaping on repaint | LAYOUT_CACHE + `hit_shapes_nothing` postcondition + SHAPING_STATISTICS (FR-N02); A-C04 bound into MVP | TRACED |
| FR-013 hit-testing (FUTURE) | Names reserved on SHAPED_LINE (06); not compiled; RISK-011 fence | TRACED (deferred by design) |
| FR-N01 empty text measurable | `at_least_one_line` + line_height (03 finding) | TRACED |
| FR-N02 counters as API | SHAPING_STATISTICS (03 finding) | TRACED |
| FR-N03 value-based font digest | FONT_LIST.digest contract (A-C05) | TRACED |
| NFR-001 ≤1 ms/line typical | Uniscribe warm-cache path + per-font SCRIPT_CACHE; measured Phase 5 (03 verdict) | TRACED (measure later) |
| NFR-002 zero shaping at paint | Cache + bridge reads immutable layouts (`draw_layout` frame condition) | TRACED |
| NFR-003 bounded memory | LAYOUT_CACHE capacity invariant; O(glyphs) value classes | TRACED |
| NFR-004 zero new DLLs | G1 OS backends; inline externals; assets are data (07 dependencies) | TRACED |
| NFR-005 void-safe | 07 ECF; attached-by-default API | TRACED |
| NFR-006 SCOOP | OQ-1 confinement design (A-C01, DR-012, 05 concurrency contracts) | TRACED |
| NFR-007 contract coverage | 05 in full; A-C02 reclassified the 1.5n+16 figure (deviation, justified) | TRACED |
| NFR-008 conformance testability | BIDI_CONFORMANCE_HARNESS in testing/ (MVP samples; FULL run = Phase-5 requirement + EIFFEL_BIDI_RESOLVER promotion gate) | TRACED |
| NFR-009 licensing | Noto Apache-2.0 (G3); LICENSE-ASSETS.md in assets/ + runnable folder | TRACED |
| NFR-010 README + /docs | Phase 7 (ship) per ecosystem push rule | TRACED (later phase) |
| NFR-011 never-raises boundary | 05 boundary pattern; total-function `layout`; SHAPING_NOTE channel | TRACED |
| C-001..C-007 | 03 constraint validation table — all YES | TRACED |

## Decision Traceability

| Decision | Where honored |
|----------|---------------|
| D-014 four seams | Exactly four deferred seam classes (04); ScriptBreak placed WITHIN seam 2 (A-C07) to keep the count |
| G1 Uniscribe MVP / DirectWrite stage-2 | UNISCRIBE_* effectings designed; DIRECTWRITE_* named-only (04); `make` postcondition pins the wiring (05/07) |
| G2 own FONT_FALLBACK | LIST_FONT_FALLBACK is the only MVP effecting of seam 4; FONT_LIST policy value |
| G3 Noto png/128 inline emoji | EMOJI_ASSET_CATALOG Noto naming contracts; IMAGE_RUN structural; assets/ + license (07) |
| D-S03 same-N + HFONT-first | SHAPING_FONT class note + DR-009 invariants; bridge sets face+size per run |
| D-S06 staged replacement | Future effectings named; harness promotion gates (I-003) |
| D-S07 simple_cairo glyph API | 07 Dependencies: EXTERNAL dependency, not this library's code; RISK-008 fallback recorded |
| D-S08 pinned generated tables | EMOJI_DATA_TABLES + tools/ generator + DR-013 version-lock invariant |

## Risk Mitigations Implemented

| Risk | Mitigation in Design |
|------|---------------------|
| RISK-001 COM cost | Zero COM classes in MVP inventory; DirectWrite slots named only |
| RISK-002 Uniscribe longevity | Seam swap path + harness verifies any replacement (UC-004) |
| RISK-003 emoji "fixed" via fonts later | SHAPED_RUN closure note + DR-005 type-system route; segmenter precedes itemization |
| RISK-004 bidi bugs | Harness class in MVP testing/; reorder-is-permutation + level contracts; reordering confined to seam 1 |
| RISK-005 asset/table drift | DR-013 lockstep invariant; FR-007 ladder + notes |
| RISK-006 stage-2 font mismatch | HFONT-first MVP immune; probe reserved for stage 2 |
| RISK-007 size mismatch | Same-N as invariant (DR-009) + FR-010 round-trip test |
| RISK-008 D-S07 slip | Fallback: temporary in-library externals, migration task recorded (07) |
| RISK-009 SCOOP/SCRIPT_CACHE | Confinement design (A-C01); relaxable if upstream ever documents safety |
| RISK-010 niqqud quality | OQ-3 default list with probed SBL Hebrew; acceptance test; ladder to DWrite/HarfBuzz unchanged |
| RISK-011 editor creep | C-007 + FR-013 names-only reservation |

## Open Issues

1. **D-S07 gate** — simple_cairo additions (show_glyphs, glyph_extents, set_font_face, CAIRO_FONT_FACE + win32 constructors) need Larry's go on that repo before Phase 4 integration; fallback path recorded. (`make_from_png` needs nothing — already present.)
2. **simple_widgets adoption** — SW_PAINTER.draw_shaped_layout + SW_CHAT_VIEW rewrap replacement: second gated repo change, Phase-7 coordination.
3. **Unicode version pin** — pick the exact Unicode/Noto release for tables+assets at Phase-3 tasks (generator input); DR-013 enforces lockstep thereafter.
4. **OQ-1 upstream truth** — confinement stands regardless; if usp10 concurrency is ever documented safe, relaxation is optional, never required.

## Deviations from the Research (all justified in 03)

| # | Deviation | Justification |
|---|-----------|---------------|
| 1 | NFR-007's "1.5·n+16 as contract" → buffer guidance, not postcondition | The source presents it as a recommended buffer with a retry signal; a hard bound would falsify correct programs (A-C02) |
| 2 | D-S04 "segmenter before itemization/shaping" refined to AFTER bidi resolution | UAX #9 neutrals need full-text context; D-S04's actual guarantee (shaper never sees emoji) preserved (A-C03) |
| 3 | IMAGE_RUN carries no unresolved state | FR-007's ladder honored EARLIER (in the segmenter) so consumers never handle broken images (A-C06) |
| 4 | FR-012 SHOULD bound into MVP facade design | Consumer's own acceptance criterion requires it (A-C04) |

## Ready for Implementation

- [x] All requirements traced (13 FR + 3 FR-N + 11 NFR + 7 C)
- [x] All 11 risks mitigated in design
- [x] All principles satisfied (tables above)
- [x] Design complete: 39 classes, 4 seams, 4 effectings, 4 doubles, contracts normative

**VERDICT: READY** — next: `/eiffel.intent D:\prod\simple_shaping`, then Phase 1 contracts (the seam texts in 07 are the freeze candidates).
