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
		Phase-5 fills `run_character_case''s comparison body; the Phase-1
		stub honestly RECORDS A FAILURE for every case (a fake pass would
		poison the gate).
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
		do
			-- Phase 5: build the STRING_32, resolver.resolve, compare
			-- paragraph level and per-character levels (skipping -1
			-- positions), resolver.reorder, compare visual order; report
			-- mismatches with the case's codepoints.
			cases_run := cases_run + 1
			failures := failures + 1
			Result := False
		ensure
			counted: cases_run = old cases_run + 1
			failure_recorded_unless_pass: Result or failures = old failures + 1
			pass_records_no_failure: Result implies failures = old failures
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
