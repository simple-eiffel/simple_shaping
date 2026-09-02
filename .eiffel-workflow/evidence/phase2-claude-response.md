# Phase 2: Claude Review Response
# STATUS: COMPLETE
# Date: 2026-09-01
# Model: Claude (adversarial self-review, Fable 5)
# Baseline: main 94242d8 (Phase 1m), clean tree
# Scope: all 37 src/ classes + 4 testing/ classes, reviewed against intent-v2
# (G1 = DirectWrite-first per Larry's 2026-09-01 ruling + spike verdict),
# spec/05 + 07, research/04, spikes/dwrite/run_output.txt.

## Per-class verdicts (clean classes; terse by order)

- SHAPING_CONSTANTS - clean. Pure helpers with definition ensures; `lines_partition_text` correctly rejects empty line-lists and forces exact cover.
- BIDI_RESOLVER - sound oracle (levels count/bounds, forced bases, permutation reorder + range + LTR identity). See ISSUE 13 for a free strengthening.
- BIDI_RESULT - clean. Defensive twin + rebase; model agrees with `level`; invariants right.
- SCRIPT_ITEMIZER - partition/level clauses sound and satisfiable (level changes force boundaries via `one_level_per_item` + contiguity). See ISSUES 1, 19, 20.
- SCRIPT_ITEM - clean. Opaque-id discipline well documented; analysis bytes modeled as identity-only.
- GLYPH_SHAPER - sound (cluster arity/monotonicity, advance non-negativity, probe-verdict meaning, font recorded). Never-raises is note-level by necessity.
- SHAPED_ITEM - clean. Constructor pins every argument; `clusters_in_range` correctly guards the glyph-less case with `.max (1)`.
- FONT_FALLBACK / FALLBACK_CHOICE - seam clauses right (size/style preserved, no_silent_drop exact). See ISSUE 4 (signature) and 7 (probe counting).
- LAYOUT_CACHE - exemplary. All three put paths exact, LRU victim named through the keys witness, R8 verification and demotion contracted, recency touch declared and framed. No findings.
- LINE_LAYOUT_ENGINE - clean for Phase 1. `fits_within` IS R2's rule, real and contracted; build_lines placeholder honestly satisfies partition.
- TEXT_SEGMENT - clean. Plain/emoji split invariants exact (emoji_resolved, plain_bare, emoji_carries_sequence).
- SHAPED_RUN / GLYPH_RUN / IMAGE_RUN - value invariants right; closed-family intent documented; box_is_advance via ensure-then. See ISSUES 8 (same-N closure), 21 (shared arrays).
- SHAPED_LAYOUT / SHAPED_LINE - clean. Coverage invariant + height_is_sum sound (identical fold both sides); width computed once from runs.
- SHAPING_NOTE - clean. Code range + stable names; whole-paragraph (0) convention documented.
- SHAPING_FONT - clean. Identity/realization/face staging invariants exact; creation restricted to FONT_REGISTRY; R9 constant present.
- FONT_REGISTRY - clean. Memo contract exact via one `updated` clause; ownership invariant enforced.
- SHAPING_STATISTICS - clean. Exact slot-wise model frames; R7 definitions bound in the note.
- FONT_LIST - see ISSUES 2, 3, 14. Model frames on the mutators are otherwise exact and strong.
- EMOJI_SEGMENTER - see ISSUES 1, 6, 10. Partition predicate correct including empty text.
- EMOJI_ASSET_CATALOG - see ISSUE 5. Memo contracts (write-once, negative-no-memo) are exemplary; injected probe design is right.
- EMOJI_DATA_TABLES - honest stubs: structural facts real, membership False until generated - the lawful pre-asset behavior. Clean (but see ISSUE 1: `is_regional_indicator` being real is what makes the precondition break live today).
- DIRECTWRITE_BIDI_RESOLVER / _SCRIPT_ITEMIZER / _GLYPH_SHAPER - placeholders satisfy every seam clause honestly (all-paragraph levels; level-split items; R3 tofu). Clean for Phase 1; Phase-4 obligations well documented from the spike.
- DWRITE_API / GDI32_API - inert by design; index-guarded accessors right. See ISSUE 11 (vacuous postconditions at the boundary).
- NULL_BIDI_RESOLVER / NULL_SCRIPT_ITEMIZER / NULL_GLYPH_SHAPER / NULL_FONT_FALLBACK - lawful doubles: requires weakened, ensures strengthened, never the reverse. Metric-predictable shaper is a good test instrument. Clean.
- LIST_FONT_FALLBACK - creation contract fine; see ISSUES 4, 7.
- SIMPLE_SHAPING - layout/layout_default/cache/statistics contracts are strong and mutually consistent (hit/miss counting, exact-when-room, hit frames). See ISSUES 2, 4, 9, 15, 16.
- LIB_TESTS / TEST_APP / TEST_SCOOP_CONSUMER - real tests where Phase 1 has real logic; rescue/retry runner correct; SCOOP gate present. See ISSUE 18 (skeletal markers).
- BIDI_CONFORMANCE_HARNESS - exemplary honest-failure stub (a fake pass would poison the gate; this records failures instead). Clean.

Verified against the attack list: no `separate` types anywhere in the public API (OQ-1 holds); no contract smuggles the pure-TrueType endgame; IMAGE_RUN.resolved is dischargeable under an all-False probe (no emoji segments exist, vacuous); a lone ZWJ or VS16 at span start does NOT break `is_emoji_free` (joiners/selectors are not starters - correct); `boundaries_are_script_or_bidi` is satisfiable for every admitted input (empty span: vacuous; single char: one item; all-Common: merged or single-id items both lawful).

---

### ISSUE 1: `itemize` precondition `plain_span_only` is unsatisfiable for correct callers under the FR-007 ladder
- **LOCATION**: SCRIPT_ITEMIZER.itemize (require plain_span_only, line ~76) + is_emoji_free (~110); EMOJI_SEGMENTER.segment (ensure, ~80); EMOJI_DATA_TABLES.is_emoji_starter
- **SEVERITY**: HIGH
- **DESCRIPTION**: FR-007 rung 3 (A-C06) sends unresolvable emoji sequences PLAIN into the glyph path. But a plain span containing that sequence fails `is_emoji_free` (any Extended_Pictographic or regional indicator is a starter), so the facade cannot lawfully call `itemize` on it - the documented degradation path is a precondition violation, i.e. NFR-011's never-raises law broken BY a contract. This is live today: `is_regional_indicator` is real (U+1F1E6..1F1FF) while `is_extended_pictographic` is stubbed False, so any text with a regional indicator already yields a "plain" segment that `itemize` must reject. After Phase-3 table generation but before assets (make_without_assets - the facade's current production wiring), the D-015 acceptance string itself (U+1F916 unresolvable -> plain) would crash at Phase 4 instead of degrading. Compounding: EMOJI_SEGMENTER.segment's ensure never establishes any emoji-free property for plain segments, despite its class note claiming "this class is what makes that precondition satisfiable" - the caller cannot prove the precondition from the supplier's postcondition even in the resolvable case.
- **SUGGESTION**: Weaken the precondition (lawful direction). Options, best first: (a) drop `plain_span_only` to a class-note duty on callers and let pictographs reaching the shaper produce .notdef/monochrome glyphs - which is exactly what rung 3 MEANS; (b) if a machine-checkable guard is wanted, redefine it as "no span-internal sequence the SEGMENTER WOULD LIFT" and add the mirror ensure on `segment` (requires threading catalog state - heavier). Either way, add to `segment` the honest statable ensure: plain segments contain no character that the segmenter's own tables + catalog would have resolved (or document why not statable). Do this before Phase 3 freezes tasks.

### ISSUE 2: FONT_LIST digest / facade cache_key serialization is non-injective - wrong layout can be served
- **LOCATION**: FONT_LIST.digest (~150) + is_equal (~253); SIMPLE_SHAPING.cache_key (~415); LAYOUT_CACHE.item_verified (R8 check set)
- **SEVERITY**: HIGH
- **DESCRIPTION**: `digest` concatenates family names with ';', '|', ':' as bare separators, and family names are arbitrary non-empty strings. Families ["A;B"] and ["A","B"] produce the identical digest "g:A;B;..." - so (a) `is_equal` (defined AS digest equality) equates genuinely different policies, breaking FR-N03 value semantics for correct code; (b) two different FONT_LISTs passed to `layout` with the same text/width/size/directory can produce the SAME full cache key, and `item_verified` verifies only (text, width, pixels) - NOT the fonts digest that intent R8 explicitly listed in the entry tuple - so a verified "hit" can return a layout computed under a DIFFERENT font policy. Silent wrong-layout service, invisible to every contract. The digest's own bottom note ("a serialization cannot collide two different lists") is factually wrong without escaping.
- **SUGGESTION**: Make the serialization injective: length-prefix every component (e.g. `count ':' name`) in both `digest` and `cache_key`, or escape the separator characters. With HASH_TABLE exact-string keying plus an injective key, cross-policy collisions become impossible and R8's three-field verification is again pure belt-and-braces. Also either implement R8 as bound (store/compare the fonts digest in the entry) or amend R8's text to record why key-injectivity makes it unnecessary.

### ISSUE 3: FONT_LIST redefines is_equal without redefining copy - shallow twins alias the internal lists (the simple_chat D5 lesson)
- **LOCATION**: FONT_LIST (inheritance clause + missing copy redefinition)
- **SEVERITY**: HIGH
- **DESCRIPTION**: `is_equal` is redefined (digest equality) but `copy`/`twin` remain ANY's field copy: a twin shares `general_families` and `script_prepends` by reference. Correct consumer code - `l := shaping.default_fonts.twin; l.with_family (...)` - mutates the ORIGINAL's lists, silently changing the facade's default policy, the LIST_FONT_FALLBACK's policy, and every future cache key. This is precisely the shallow-twin aliasing defect the simple_chat D5 cycle established as a standing hazard for value-comparable classes.
- **SUGGESTION**: Redefine `copy` to deep-copy both collections (fresh ARRAYED_LISTs, fresh HASH_TABLE with fresh inner lists; IMMUTABLE_STRING_32 elements may be shared). Add a `twin_is_independent` test.

### ISSUE 4: Seam 4 has no FONT_LIST parameter - `layout`'s per-call `a_fonts` policy cannot reach fallback
- **LOCATION**: FONT_FALLBACK.font_for (signature); LIST_FONT_FALLBACK.make/fonts; SIMPLE_SHAPING.make (wires default_fonts at creation), set_default_fonts (does not rewire), layout (header comment "under policy a_fonts")
- **SEVERITY**: HIGH
- **DESCRIPTION**: `font_for (text, item, requested)` carries no policy, so LIST_FONT_FALLBACK walks the FONT_LIST captured at facade creation - forever. Consequences for correct code: (a) `layout (text, w, n, my_fonts)` claims a layout "under policy a_fonts" and keys the cache by `a_fonts.digest`, but the fallback walk ignores `a_fonts` entirely - two different policies yield different cache keys for identical rendering, and the advertised policy is fictional beyond the primary face; (b) `set_default_fonts` swaps the facade's list but LIST_FONT_FALLBACK keeps the old reference - AC-4's "first covering FONT_LIST font" then refers to a list the consumer no longer holds. G2 itself (ours-in-every-config) is honored; the POLICY PLUMBING is not. This must be settled now - seam signatures are frozen after Phase 2.
- **SUGGESTION**: Amend the seam: `font_for (a_text, a_item, a_requested, a_policy: FONT_LIST)` (NULL_ ignores it; DIRECTWRITE_ future slot ignores it; LIST_ walks it). Alternatively bind, in contracts and docs, that fallback policy IS the creation-time default list and demote `layout`'s `a_fonts` to primary-face + key material only - but then say so in `layout`'s header and AC-4. The parameter is the cleaner fix and also gives ISSUE 7 a home.

### ISSUE 5: `lower_hex` omits Noto's 4-digit zero padding - sub-U+1000 emoji resolve to wrong filenames
- **LOCATION**: EMOJI_ASSET_CATALOG.lower_hex (~200) / asset_key
- **SEVERITY**: HIGH
- **DESCRIPTION**: Noto png assets pad codepoints to at least 4 hex digits: copyright is `emoji_u00a9.png`, registered `emoji_u00ae.png`, keycap bases `emoji_u0023_20e3.png` / `emoji_u002a_20e3.png` / `emoji_u0030_20e3.png`.. . `lower_hex` strips leading zeros ("a9", "23"), so every such sequence probes a nonexistent path and degrades - permanent, silent tofu for (c), (r), and all keycaps once assets ship (Phase 3). The Phase-1 tests only use >= 4-digit codepoints (1f916, 2764, 1f469) so the defect is invisible to the suite.
- **SUGGESTION**: Pad to 4 hex digits minimum (prepend '0' while count < 4). Add "emoji_u00a9" and "emoji_u0023_20e3" expectations to test_asset_catalog_key_scheme. Record the padding rule in the class-note naming scheme.

### ISSUE 6: FR-007 rung 3's Note_emoji_degraded has no channel out of the segmenter
- **LOCATION**: EMOJI_SEGMENTER.segment (signature/ensure)
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: The segmenter is the only party that knows a sequence degraded (rung 3), but `segment` returns only TEXT_SEGMENTs - no notes query, no notes parameter. As designed, the facade cannot emit Note_emoji_degraded without re-deriving the degradation, so the FR-007 observability promise (and statistics.notes_emitted for this case) is structurally unimplementable - a silent drop of the NOTE, against DR-010's spirit.
- **SUGGESTION**: Either give `segment` an `a_notes: ARRAYED_LIST [SHAPING_NOTE]` accumulator parameter (matches the facade's building pattern) or add a `last_degradations: ARRAYED_LIST [SHAPING_NOTE]` query with a frame contract. Decide before Phase 3.

### ISSUE 7: R7 probe counting is unimplementable as bound - only LIST_FONT_FALLBACK can see its own probes
- **LOCATION**: LIST_FONT_FALLBACK.font_for (Phase-4 note); SHAPING_STATISTICS note; SIMPLE_SHAPING wiring
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: R7 binds "probe shapes are counted as fallback_probes by the CALLING engine, never inside effectings." But the walk-and-probe loop is INSIDE LIST_FONT_FALLBACK; the calling engine sees only the returned FALLBACK_CHOICE and cannot know how many probe shapes occurred. As written, fallback_probes can never be incremented correctly. R7's rationale (doubles stay dumb) does not require starving LIST_FONT_FALLBACK - it is our engine, not a double.
- **SUGGESTION**: Either (a) add `probes_performed: INTEGER` to FALLBACK_CHOICE (value carries the count; facade adds it - doubles return 0), or (b) pass SHAPING_STATISTICS into LIST_FONT_FALLBACK.make and amend R7 to "never inside SEAM DOUBLES." (a) keeps the seam pure and testable. Pairs naturally with ISSUE 4's signature amendment.

### ISSUE 8: Same-N (D-S03) is not closed - nothing ties run fonts' pixel_size to the layout's pixel_size
- **LOCATION**: GLYPH_RUN.pixel_size (tautological ensure), SHAPED_LINE.make, SHAPED_LAYOUT.make/invariant
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: GLYPH_RUN.pixel_size is defined as font.pixel_size, so its `same_n_rule` ensure proves nothing. Seam 4 preserves size only relative to `a_requested`, and no contract anywhere forces the requested font to be realized at the LAYOUT's `a_pixel_size`. A Phase-4 implementer can therefore shape at one size and stamp the layout with another - silently violating the bound same-N rule; positions would be authoritative at the wrong size and paint would be subtly broken.
- **SUGGESTION**: Add to SHAPED_LAYOUT (invariant + make precondition, over lines' runs): every GLYPH_RUN's `font.pixel_size = pixel_size`. One `runs_at_layout_size` predicate beside `lines_partition_text` in SHAPING_CONSTANTS closes the chain facade -> registry -> seam 4 -> runs.

### ISSUE 9: `measured_width.whitespace_measures` is vacuous while claiming to encode R2
- **LOCATION**: SIMPLE_SHAPING.measured_width (ensure whitespace_measures)
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: `a_text.count > 0 implies Result >= 0.0` is implied by `non_negative` - it constrains nothing, yet its name and the R2 comment present it as the whitespace-measures guarantee. A reader (or Phase-5 verifier) could believe R2's measurement half is contracted when it is not.
- **SUGGESTION**: Delete the clause; bind R2's measurement half to a named Phase-5 test (whitespace-only text under a realized font measures > 0). The wrap half of R2 already lives, real, in `fits_within`.

### ISSUE 10: EMOJI_SEGMENTER.segment does not state that emoji segments inherit their bidi level
- **LOCATION**: EMOJI_SEGMENTER.segment (ensure)
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: The class note and TEXT_SEGMENT doc say emoji spans inherit resolved levels (load-bearing for RTL image placement - AC-1's robot between Hebrew and Greek), but no postcondition states it. A backend could set level 0 on every emoji segment and pass.
- **SUGGESTION**: Add `emoji_levels_inherited: across Result as s all s.is_emoji implies s.embedding_level = a_bidi.level (s.start_index) end`.

### ISSUE 11: DWRITE_API.analyze / shape_run have no postconditions - the never-raises boundary rests on notes alone
- **LOCATION**: DWRITE_API.analyze, shape_run (also open's failure channel)
- **SEVERITY**: MEDIUM
- **DESCRIPTION**: The two workhorse calls ensure nothing: success does not promise populated run/glyph tables, failure does not promise `last_hresult` set. A raising or lying shim is then a surprise, not a contract violation - weaker than the seam layer above it, at exactly the trust boundary the never-raises law needs teeth.
- **SUGGESTION**: Add: `analyze` ensure `runs_on_success: Result implies (script_run_count >= 1 and bidi_run_count >= 1)` (every unit belongs to some run) and `failure_reported: not Result implies last_hresult /= 0`; `shape_run` ensure `glyphs_on_success: Result implies glyph_count >= 1` (non-empty run precondition) and the same failure_reported; `open` ensure `failure_reported: not Result implies last_hresult /= 0`.

### ISSUE 12: R3's "cluster map identity" wording is impossible for RTL items
- **LOCATION**: intent-v2 R3 / SHAPING_CONSTANTS.Note_backend_error_recovered comment vs GLYPH_SHAPER.clusters_monotone_rtl; DIRECTWRITE_GLYPH_SHAPER body
- **SEVERITY**: LOW
- **DESCRIPTION**: R3 binds "identity clusters" for tofu synthesis, but an identity map violates `clusters_monotone_rtl` for any RTL item of 2+ characters. The Phase-1 body already (correctly) reverses for RTL - the contract won; the binding text is wrong and would mislead a Phase-4 implementer following R3's letter.
- **SUGGESTION**: Amend R3's wording (intent + constant comment) to "trivial one-to-one cluster map, reversed for RTL items."

### ISSUE 13: Free strengthenings for the bidi oracle
- **LOCATION**: BIDI_RESOLVER.reorder / resolve
- **SEVERITY**: LOW
- **DESCRIPTION**: The reorder oracle states the LTR identity law but not its dual; resolve leaves empty-text-under-auto's paragraph level open (UAX #9 P3 default is 0).
- **SUGGESTION**: Add `rtl_reversal: is_all_odd (a_levels) implies is_reversal (Result)` (helpers beside is_all_even) and `empty_auto_ltr: (a_text.is_empty and a_base_direction = Direction_auto) implies Result.paragraph_level = 0`. Cheap cross-backend discriminators.

### ISSUE 14: FONT_LIST mutability after wiring is discipline-only
- **LOCATION**: SIMPLE_SHAPING.set_default_fonts / make; LIST_FONT_FALLBACK.make (references kept)
- **SEVERITY**: LOW
- **DESCRIPTION**: "Immutable-after-configuration" (A-C05) is unenforced: the facade and fallback hold live references, and with_family remains callable - a later mutation silently changes policy and future keys mid-life (cache correctness survives via R8/keying; determinism claims do not).
- **SUGGESTION**: Take a defensive deep copy in set_default_fonts/make once ISSUE 3's copy redefinition exists - one line each - or add a seal/frozen flag with mutator preconditions.

### ISSUE 15: cache_key's R5 comment claims the effective digest that Phase 4 must still build
- **LOCATION**: SIMPLE_SHAPING.cache_key (header comment)
- **SEVERITY**: LOW
- **DESCRIPTION**: The comment asserts "fonts digest is over the effective list," but the body calls the configured `a_fonts.digest` and the effective list will not exist until Phase-4 realization. FONT_LIST's own note is honest about this; cache_key's is not marked as a pending obligation.
- **SUGGESTION**: Mark it `-- Phase 4: swap to the post-probe effective digest (R5)` like the other deliberate stubs.

### ISSUE 16: set_asset_directory lacks the capacity_kept frame
- **LOCATION**: SIMPLE_SHAPING.set_asset_directory (ensure)
- **SEVERITY**: LOW
- **DESCRIPTION**: clear_cache states capacity_kept; set_asset_directory (which also wipes) does not - an implementer could lawfully reset capacity there.
- **SUGGESTION**: Add `capacity_kept: cache_capacity = old cache_capacity` (and `statistics`' clause already present; defaults_kept present).

### ISSUE 17: has_asset's benign memo is missing from the 05 CQS exception table
- **LOCATION**: spec/05 CQS Audit Notes vs EMOJI_ASSET_CATALOG.has_asset
- **SEVERITY**: LOW
- **DESCRIPTION**: The table declares layout/layout_default and the fluent setters; has_asset (query with write-once memo, used in asset_path's PRECONDITION - evaluation mutates state under assertions) is undeclared. Phase 4.5's audit will trip over it.
- **SUGGESTION**: Add has_asset (and LAYOUT_CACHE.item_verified's recency touch, already class-noted) to the declared-exception table.

### ISSUE 18: Skeletal AC tests pass vacuously - they name their criteria but encode nothing
- **LOCATION**: LIB_TESTS.test_bidi_conformance_samples .. test_d015_chat_line (8 features); TEST_APP labels
- **SEVERITY**: LOW
- **DESCRIPTION**: The eight Phase-5 markers have empty bodies and report PASS (tagged [skeletal] in the runner - good), so "28 passed" includes 8 no-ops. Contrast BIDI_CONFORMANCE_HARNESS, which honestly fails. A forgotten skeletal body would pass forever.
- **SUGGESTION**: Print an explicit SKIP line (and count skips separately) or add `check skeletal_not_yet_real: True end` plus a Phase-5 gate that greps for the [skeletal] tag and fails /eiffel.verify while any remain.

### ISSUE 19: Two EMOJI_DATA_TABLES instances can diverge under descendant injection
- **LOCATION**: SCRIPT_ITEMIZER.emoji_tables (once) vs SIMPLE_SHAPING.tables (injected into segmenter/catalog)
- **SEVERITY**: LOW
- **DESCRIPTION**: is_emoji_free consults a once-created base-class table while the segmenter consults the injected one; a test or future generator descendant redefining membership splits the verdicts - the precondition and the segmenter then disagree about what "emoji" means.
- **SUGGESTION**: Resolves itself if ISSUE 1 removes the precondition; otherwise thread one tables instance (the facade already owns one).

### ISSUE 20: The itemizer note overstates what the intersection contract enforces
- **LOCATION**: SCRIPT_ITEMIZER class note ("emitted boundaries are exactly the union of script boundaries and bidi boundaries")
- **SEVERITY**: INFO
- **DESCRIPTION**: Level boundaries are enforced both directions (one_level_per_item forces splits; boundaries_are_script_or_bidi limits splits). Script boundaries are trust-based both directions - script_code is opaque and self-reported, so a backend can merge across script changes or split within one by varying ids, satisfying the letter. The note already concedes within-item constancy; the "exactly" claim goes further than the oracle can.
- **SUGGESTION**: Soften the note: level boundaries oracle-checked; script boundaries the engine's own claim.

### ISSUE 21: Shared-array immutability is discipline, not contract
- **LOCATION**: SHAPED_ITEM/GLYPH_RUN/IMAGE_RUN/TEXT_SEGMENT constructors (reference-keeping ensures); SHAPED_LINE.make (runs list)
- **SEVERITY**: INFO
- **DESCRIPTION**: Constructors keep caller arrays/lists by reference ("handed over frozen"; BIDI_RESULT alone twins defensively). A mutating caller breaks invariants only at next evaluation. Documented, consistent, acceptable Phase-1 practice - noting for the Phase-4 "ingest via twins" duty already promised in GLYPH_RUN's note.
- **SUGGESTION**: Keep the Phase-4 twin-on-ingest promise; consider BIDI_RESULT-style twins where cheap.

### ISSUE 22: path_for tolerates a trailing separator in directory
- **LOCATION**: EMOJI_ASSET_CATALOG.path_for
- **SEVERITY**: INFO
- **DESCRIPTION**: A configured directory ending in '\' yields a double backslash (harmless on Win32) and `starts_with (directory)` still holds. Cosmetic.
- **SUGGESTION**: Optionally normalize at creation; or leave as-is.

## Checklist coverage summary

- Contract completeness: no True-only preconditions found; vacuous postconditions at ISSUES 9, 11; missing frames at ISSUE 16; `old` usage correct throughout the cache/statistics/registry surfaces.
- MML review: all 24 model queries pure and fresh-building; HASH_TABLE key/value flips correct (spot-checked all four maps); frames use |=| correctly; LRU keys_model witness discipline is sound and well documented.
- Design review: creation procedures all establish invariants; CQS exceptions declared except ISSUE 17; void-safety idioms (attached-tests, detachable item) correct; state transitions consistent (SHAPING_FONT staging, cache paths).
- Edge cases: empty text sound end-to-end (resolve/segment/itemize/layout/measured_width); duplicate keys exact (put replace path, registry memo); concurrency = confinement, verified no separate types; exception path is the R3/never-raises design - broken only by ISSUE 1, which is the review's headline.
