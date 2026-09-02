note
	description: "[
		Runs Unicode bidi conformance cases against ANY BIDI_RESOLVER -
		the seam contracts' external oracle (I-003/NFR-008).

		MVP (Phase 1/5 start): sampled BidiCharacterTest.txt cases (AC-5:
		all-Hebrew, Hebrew+digits, mixed Hebrew/Latin). Phase 5
		(/eiffel.verify): the FULL BidiTest.txt (513,494 cases) +
		BidiCharacterTest.txt run is a hard requirement - and the promotion
		gate for a future EIFFEL_BIDI_RESOLVER (D-S06).

		Testing-cluster class: ships with the repo, never with a consumer.

		PHASE 4 TASK 3 - `run_character_case' HAS ITS REAL BODY. It checks a
		case in two halves, because the seam has two features and they fail
		independently:

		  1. RESOLVE. Build the STRING_32 from the case's code points, call
		     `resolver.resolve' under the case's paragraph direction, and
		     compare the resolved paragraph level and every per-character
		     level, skipping the positions the case marks -1 (BidiCharacter-
		     Test's 'x': removed by rule X9, so the file states no level for
		     them).
		  2. REORDER. Rule L2 runs on the text AFTER X9 has removed those
		     positions, and the file's visual-order field lists only the KEPT
		     ones. So the reorder half hands `resolver.reorder' the EXPECTED
		     levels of the kept positions - the Unicode oracle's own numbers -
		     and maps the returned permutation back to input indices. That
		     keeps L2 under test as itself: a backend that resolves a level
		     wrongly fails half 1, and is not also charged with an L2 defect
		     it does not have.

		A case passes only when BOTH halves agree. Everything is compared, and
		nothing is skipped for being hard.
	]"
	author: "Larry Rix"

class
	BIDI_CONFORMANCE_HARNESS

inherit
	SHAPING_CONSTANTS

create
	make

feature {NONE} -- Initialization

	make (a_resolver: BIDI_RESOLVER)
			-- Harness over `a_resolver'.
		do
			resolver := a_resolver
		ensure
			resolver_kept: resolver = a_resolver
			nothing_run: cases_run = 0 and failures = 0
		end

feature -- Access

	resolver: BIDI_RESOLVER
			-- The implementation under test.

	cases_run: INTEGER
			-- Cases executed so far.

	failures: INTEGER
			-- Cases that did not match the expectation.

	all_passed: BOOLEAN
			-- Zero failures so far?
		do
			Result := failures = 0
		ensure
			definition: Result = (failures = 0)
		end

feature -- Operations

	run_character_case (a_codepoints: ARRAY [NATURAL_32]; a_base_direction: INTEGER;
			a_expected_paragraph_level: INTEGER; a_expected_levels: ARRAY [INTEGER];
			a_expected_visual_order: ARRAY [INTEGER]): BOOLEAN
			-- One BidiCharacterTest.txt case: `a_codepoints' under
			-- `a_base_direction'; expected paragraph level; expected levels
			-- (-1 = position removed by rule X9); expected visual order of
			-- the kept positions. True iff the resolver matches.
		require
			case_nonempty: not a_codepoints.is_empty
			base_valid: is_valid_base_direction (a_base_direction)
			levels_cover: a_expected_levels.count = a_codepoints.count
			paragraph_sane: a_expected_paragraph_level >= 0 and a_expected_paragraph_level <= 1
		local
			l_text: STRING_32
			l_resolved: BIDI_RESULT
			l_kept: ARRAYED_LIST [INTEGER]
			l_levels: ARRAY [NATURAL_8]
			l_order: ARRAY [INTEGER]
			i, k, l_expected: INTEGER
			l_ok, l_failed: BOOLEAN
		do
			if not l_failed then
					-- ---- half 1: resolve ----
				create l_text.make (a_codepoints.count)
				from i := a_codepoints.lower until i > a_codepoints.upper loop
					l_text.append_code (a_codepoints [i])
					i := i + 1
				end
				l_resolved := resolver.resolve (l_text, a_base_direction)
				l_ok := l_resolved.count = a_codepoints.count and then
					l_resolved.paragraph_level.to_integer_32 = a_expected_paragraph_level
				from i := 1 until i > a_codepoints.count or not l_ok loop
					l_expected := a_expected_levels [a_expected_levels.lower + i - 1]
					if l_expected >= 0 then
						l_ok := l_resolved.level (i).to_integer_32 = l_expected
					end
					i := i + 1
				end
					-- ---- half 2: reorder (L2 over the X9-kept positions) ----
				if l_ok then
					create l_kept.make (a_codepoints.count)
					from i := 1 until i > a_codepoints.count loop
						if a_expected_levels [a_expected_levels.lower + i - 1] >= 0 then
							l_kept.extend (i)
						end
						i := i + 1
					end
					create l_levels.make_filled ({NATURAL_8} 0, 1, l_kept.count)
					from k := 1 until k > l_kept.count loop
						l_levels [k] := a_expected_levels [a_expected_levels.lower + l_kept [k] - 1].to_natural_8
						k := k + 1
					end
					l_order := resolver.reorder (l_levels)
					l_ok := l_order.count = a_expected_visual_order.count
					from k := 1 until k > l_order.count or not l_ok loop
						l_ok := l_kept [l_order [k]] - 1 =
							a_expected_visual_order [a_expected_visual_order.lower + k - 1]
						k := k + 1
					end
				end
			end
			cases_run := cases_run + 1
			if not l_ok then
				failures := failures + 1
			end
			Result := l_ok
		ensure
			counted: cases_run = old cases_run + 1
			failure_recorded_unless_pass: Result or failures = old failures + 1
			pass_records_no_failure: Result implies failures = old failures
		rescue
			if not l_failed then
					-- NFR-011 belt: a case that blows up is a FAILED case,
					-- never a crashed suite and never a silent pass.
				l_failed := True
				l_ok := False
				retry
			end
		end

	run_case (a_codepoints: ARRAY [NATURAL_32]; a_base_direction: INTEGER;
			a_expected_levels: ARRAY [INTEGER];
			a_expected_visual_order: ARRAY [INTEGER]): BOOLEAN
			-- [ADDED Phase 4 Task 12] One BidiTest.txt case: `a_codepoints'
			-- under `a_base_direction'; expected levels (-1 = position
			-- removed by rule X9); expected visual order of the kept
			-- positions. True iff the resolver matches.
			--
			-- WHY THIS IS NOT `run_character_case'. BidiTest.txt states NO
			-- paragraph level. Its data lines carry a bitset of paragraph
			-- DIRECTIONS (1 auto / 2 LTR / 4 RTL) and nothing else, so the
			-- only honest comparison is the per-character levels and the L2
			-- visual order. Asking `run_character_case' for this file would
			-- have meant inventing an expected paragraph level - deriving
			-- P2/P3 in the test and then checking the backend against the
			-- test's own arithmetic, which is not an oracle. The two halves
			-- that ARE stated are judged exactly as `run_character_case'
			-- judges them, including L2 against the oracle's own levels.
		require
			case_nonempty: not a_codepoints.is_empty
			base_valid: is_valid_base_direction (a_base_direction)
			levels_cover: a_expected_levels.count = a_codepoints.count
		local
			l_text: STRING_32
			l_resolved: BIDI_RESULT
			l_kept: ARRAYED_LIST [INTEGER]
			l_levels: ARRAY [NATURAL_8]
			l_order: ARRAY [INTEGER]
			i, k, l_expected: INTEGER
			l_ok, l_failed: BOOLEAN
		do
			if not l_failed then
					-- ---- half 1: resolve (levels only) ----
				create l_text.make (a_codepoints.count)
				from i := a_codepoints.lower until i > a_codepoints.upper loop
					l_text.append_code (a_codepoints [i])
					i := i + 1
				end
				l_resolved := resolver.resolve (l_text, a_base_direction)
				l_ok := l_resolved.count = a_codepoints.count
				from i := 1 until i > a_codepoints.count or not l_ok loop
					l_expected := a_expected_levels [a_expected_levels.lower + i - 1]
					if l_expected >= 0 then
						l_ok := l_resolved.level (i).to_integer_32 = l_expected
					end
					i := i + 1
				end
					-- ---- half 2: reorder (L2 over the X9-kept positions) ----
				if l_ok then
					create l_kept.make (a_codepoints.count)
					from i := 1 until i > a_codepoints.count loop
						if a_expected_levels [a_expected_levels.lower + i - 1] >= 0 then
							l_kept.extend (i)
						end
						i := i + 1
					end
					create l_levels.make_filled ({NATURAL_8} 0, 1, l_kept.count)
					from k := 1 until k > l_kept.count loop
						l_levels [k] := a_expected_levels [a_expected_levels.lower + l_kept [k] - 1].to_natural_8
						k := k + 1
					end
					l_order := resolver.reorder (l_levels)
					l_ok := l_order.count = a_expected_visual_order.count
					from k := 1 until k > l_order.count or not l_ok loop
						l_ok := l_kept [l_order [k]] - 1 =
							a_expected_visual_order [a_expected_visual_order.lower + k - 1]
						k := k + 1
					end
				end
			end
			cases_run := cases_run + 1
			if not l_ok then
				failures := failures + 1
			end
			Result := l_ok
		ensure
			counted: cases_run = old cases_run + 1
			failure_recorded_unless_pass: Result or failures = old failures + 1
			pass_records_no_failure: Result implies failures = old failures
		rescue
			if not l_failed then
					-- Same NFR-011 belt as `run_character_case': a case that
					-- blows up is a FAILED case, never a crashed suite.
				l_failed := True
				l_ok := False
				retry
			end
		end

	wipe
			-- Reset counters between suites.
		do
			cases_run := 0
			failures := 0
		ensure
			zeroed: cases_run = 0 and failures = 0
		end

invariant
	counters_sane: cases_run >= 0 and failures >= 0 and failures <= cases_run

end
