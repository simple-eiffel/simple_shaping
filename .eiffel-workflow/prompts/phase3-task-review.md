# Task Completeness Review: simple_shaping (Phase 3)

Review the Phase-4 task breakdown for completeness against the frozen contracts. This is a
COVERAGE audit, not a design review: the contracts are the specification and the seam signatures
froze after Phase 2. Do not propose contract changes — if a task cannot be done without one, say
so and name the clause.

Read (by path, in this order — nothing is pasted into this prompt):

1. `.eiffel-workflow/tasks.md` — the breakdown under review
2. `.eiffel-workflow/synopsis.md` + `.eiffel-workflow/evidence/phase2-repair.txt` — what Phase 2
   found and how each of the 22 findings was repaired
3. `.eiffel-workflow/approach.md` — architecture, the five-step implementation order, dependencies
4. `.eiffel-workflow/intent-v2.md` Part D — R1-R11 as amended (R3, R7, R8 amended; R11 approved
   2026-09-02)
5. `.eiffel-workflow/spec/07-SPECIFICATION.md`, **including "Amendments after Phase 2" at the
   bottom** — the frozen signatures; and `.eiffel-workflow/spec/04-CLASS-DESIGN.md`
6. `.eiffel-workflow/research/04-DECISIONS.md` (D-S03 same-N, D-S04 emoji segmentation, D-S07 the
   gated simple_cairo change, D-S08 generated tables) and `research/06-RISKS.md` (RISK-008)
7. **Every class in `src/` (36 files) and `testing/` (4)** — the contracts ARE the specification
8. `spikes/dwrite/` — the proven COM shim (header, Eiffel root, `run_output.txt`) that Task 1
   promotes into `Clib/`

## Check for

**Coverage gaps.** Walk every feature in `src/` whose body is a `-- Phase 4:` marker, a degenerate
placeholder, or an attribute that no feature can currently set, and name the task that claims it.
The decomposition counts 40 `-- Phase 4:` body markers across 10 src files, 7 unmarked degenerate
items (4 SHAPING_FONT realization attributes, 2 EMOJI_DATA_TABLES stubs, 1 catalog version
expectation) and 10 Phase-5 markers in `testing/`. Verify that count independently and report any
placeholder no task claims — and any task that claims something already real.

**Contract clauses no acceptance criterion names.** Each task's acceptance criteria are supposed to
name the CONTRACT clauses the body must discharge. Find postconditions, invariants and preconditions
that no task's criteria mention — especially the Phase-2 additions, which exist precisely because
they were once missing: `DWRITE_API.runs_on_success` / `glyphs_on_success` / `failure_reported`
(ISSUE 11), `BIDI_RESOLVER.rtl_reversal` / `empty_auto_ltr` (ISSUE 13), `FALLBACK_CHOICE.probes_performed`
and the seam's `probes_counted` (ISSUE 7), `SHAPED_LAYOUT.runs_at_this_size` /
`SHAPING_CONSTANTS.runs_at_layout_size` (ISSUE 8), `LAYOUT_CACHE`'s digest frames (ISSUE 2 / R8),
`EMOJI_SEGMENTER.no_resolvable_single_left_plain` / `emoji_levels_inherited` / `notes_only_grow` /
`appended_notes_are_degradations` (ISSUES 1, 6, 10), `EMOJI_ASSET_CATALOG.noto_minimum_padding`
(ISSUE 5), `FONT_LIST.copy`'s deep semantics (ISSUE 3).

**Dependency errors.** Is any task ordered before something it needs? Is any declared dependency
spurious? Specifically check: nothing shapes before a font can be REALIZED (`GLYPH_SHAPER.shape`
and `FONT_FALLBACK.font_for` both require `a_font.is_ready`); nothing itemizes before a real
`BIDI_RESULT` exists; the emoji ladder cannot be tested before tables AND assets are pinned
together (DR-013 lockstep); the paint bridge cannot precede a real layout.

**Sizing.** Flag tasks too large to land in one clean-compile-green cycle (candidates: Task 1's
28 native bodies, Task 11's whole facade pipeline) and tasks too small to stand alone (should they
fold into a neighbor?). Say which split or merge you would make and why.

**Never-raises and total-function coverage.** NFR-011 says `layout` never raises. Confirm the tasks
carry every degradation path as DATA: fallback exhaustion → `Note_fallback_exhausted`; hard native
failure → R3 tofu-but-valid (glyph 0 per char, advance `pixel_size/2`, one-to-one cluster map
REVERSED for RTL) + `Note_backend_error_recovered`; unresolvable emoji → PLAIN +
`Note_emoji_degraded`; absent family → `Note_family_missing`. Any path that could still raise, or
still silently drop a character range, is a finding.

**External and gated work.** Confirm the D-S07 simple_cairo change is listed as an EXTERNAL task
requiring Larry's gate, with RISK-008's fallback (temporary in-library externals) named, and that
no in-library task secretly depends on it.

**Open questions.** The breakdown ends with seven questions for Larry (soft-break channel, font
realization surface, the R5 memo, RGI table queries, `script_class_of`, documentation drift,
`record_fallback_probe`). Are any of them actually decidable from the existing contracts — i.e.
wrongly escalated? Are there OTHER decisions the tasks quietly make that should have been
escalated instead?

## Output

A numbered findings list, each with: severity (HIGH / MEDIUM / LOW), the file and feature or task
number it concerns, what is missing or wrong, and the smallest correction. End with a verdict:
COMPLETE, or COMPLETE WITH GAPS (list them), or INCOMPLETE (say what must be added before Phase 4
starts). Do not rewrite `tasks.md`.
