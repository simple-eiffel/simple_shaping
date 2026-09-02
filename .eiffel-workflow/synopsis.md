# Phase 2 Synopsis: simple_shaping adversarial contract review

Reviewed: main 94242d8 (Phase 1m), all 37 src classes + 4 testing classes, against intent-v2 (G1 = DirectWrite-first, Larry's 2026-09-01 ruling), spec/05 + 07, research/04, and the dwrite spike evidence. Full findings: `.eiffel-workflow/evidence/phase2-claude-response.md`.

**Counts: 5 HIGH, 6 MEDIUM, 8 LOW, 3 INFO (22 issues).**

The foundation is strong: LAYOUT_CACHE's three-path exactness, the registry ownership contracts, the statistics slot-wise frames, the honest-failure conformance harness, and the seam oracle discipline (doubles weaken requires / strengthen ensures, never the reverse) are all exemplary. OQ-1 confinement verified - no `separate` type appears in any public signature. No contract smuggles the off-the-table pure-TrueType endgame.

## Critical findings (must fix before Phase 3)

1. **ISSUE 1 - the emoji-free precondition breaks the never-raises law.** `SCRIPT_ITEMIZER.itemize` requires `is_emoji_free`, but FR-007 rung 3 lawfully leaves unresolvable emoji PLAIN - so the documented degradation path is a precondition violation. Live today for regional indicators; after Phase-3 table generation (pre-assets) the D-015 acceptance string itself would crash instead of degrading. Weaken the precondition to a caller-duty note (pictographs reaching the shaper as .notdef IS rung 3's meaning) and give `segment` the honest mirror ensure.
2. **ISSUE 2 - non-injective digest/cache-key serialization.** Family names containing ';'/'|'/':' collide digests: FONT_LIST.is_equal equates different policies, and a colliding key passes R8 verification (text/width/size only - the fonts digest R8 listed was dropped), serving a layout computed under a different font policy. Length-prefix every serialized component in `digest` and `cache_key`.
3. **ISSUE 3 - FONT_LIST shallow twin (the simple_chat D5 lesson).** is_equal redefined without copy: a twin aliases the internal lists; twin-then-mutate silently corrupts the facade's policy and keys. Redefine `copy` deep.
4. **ISSUE 4 - seam 4 cannot see the per-call policy.** `font_for` has no FONT_LIST parameter; LIST_FONT_FALLBACK walks the creation-time list forever, so `layout (..., a_fonts)`'s "under policy a_fonts" is undeliverable and `set_default_fonts` never rewires fallback. Amend the seam signature (`+ a_policy: FONT_LIST`) - or bind policy = creation list explicitly in layout's contract and AC-4. Seam signatures freeze after this phase; decide now.
5. **ISSUE 5 - Noto filename padding.** `lower_hex` strips leading zeros; Noto pads to 4 (emoji_u00a9.png, emoji_u0023_20e3.png). Copyright, registered, and every keycap would silently degrade once assets ship. Pad to 4 and extend the key-scheme test.

## Important findings (fix during implementation, decide interfaces now)

- **ISSUE 6**: `segment` has no channel for Note_emoji_degraded - rung 3's observability is unimplementable; add a notes accumulator parameter or query (interface change: decide at Phase 3 entry).
- **ISSUE 7**: R7 probe counting cannot be done "by the calling engine" - only LIST_FONT_FALLBACK sees its probes; add `probes_performed` to FALLBACK_CHOICE (pairs with ISSUE 4's amendment).
- **ISSUE 8**: same-N is open-ended - add `runs_at_layout_size` to SHAPED_LAYOUT so a Phase-4 body cannot shape at one size and stamp another.
- **ISSUE 9**: delete the vacuous `whitespace_measures` clause (R2's measurement half belongs to a Phase-5 test).
- **ISSUE 10**: contract emoji segments' level inheritance (RTL image placement depends on it).
- **ISSUE 11**: give DWRITE_API.analyze/shape_run/open success-and-failure postconditions so a lying shim is a contract violation, not a surprise.

## Minor (LOW/INFO 12-22)

R3's RTL wording fix; two free bidi-oracle strengthenings; defensive copies for wired FONT_LISTs; the R5 Phase-4 marker on cache_key; set_asset_directory's capacity frame; has_asset into the CQS exception table; visible SKIP reporting for the 8 skeletal AC tests; once-tables unification; itemizer-note softening; shared-array discipline notes; path separator cosmetics.

## Recommended actions before Phase 3 (/eiffel.tasks)

1. Apply ISSUES 1-5 (contract edits only; one seam-signature amendment) and recompile the test target green.
2. Settle the two interface decisions (ISSUES 6, 7) so Phase-3 tasks carry the final signatures.
3. Fold ISSUES 8-11 into the Phase-1 contract set in the same edit pass (all are small clauses).
4. Record the ISSUE 4 resolution (parameter vs bound-creation-policy) in intent-v2 Part D as R11 with Larry's gate.

## Overall assessment

**PASS WITH CONDITIONS** - the architecture and the bulk of the contract network are sound and unusually well-framed, but the five HIGH findings include an unsatisfiable precondition on the acceptance path and two silent-wrong-answer channels; Phase 3 must not start until ISSUES 1-5 are fixed and ISSUES 6-7 are decided.
