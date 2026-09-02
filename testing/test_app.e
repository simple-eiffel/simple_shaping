note
	description: "[
		Test application for simple_shaping (Phase 1, with the Phase-2
		repair pass).

		SKIPS ARE NOT PASSES (Phase 2 / ISSUE 18). The Phase-5 markers have
		empty bodies; counting them as PASS made the suite report "28 passed"
		when eight of those were no-ops, and a forgotten skeletal body would
		have passed forever. They now run through `run_skeletal_test', print
		an explicit SKIP line, and are tallied in their own counter. The
		totals line reports passed / skipped / failed separately, and the
		final verdict names how many are still skeletal - so /eiffel.verify
		at Phase 5 has a number to drive to zero.
	]"
	author: "Larry Rix"

class
	TEST_APP

create
	make

feature {NONE} -- Initialization

	make
			-- Run the tests.
		do
			print ("Running SIMPLE_SHAPING tests (Phase 1: contracts)...%N%N")
			passed := 0
			skipped := 0
			failed := 0
			native_skipped := 0

			run_lib_tests
			run_scoop_consumer

			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + skipped.out
				+ " skipped, " + failed.out + " failed%N")
			if native_skipped > 0 then
				print ("  (" + native_skipped.out + " machine-dependent test(s) SKIPPED: this"
					+ " machine lacks the capability they need - NOT counted as passes)%N")
			end

			if failed > 0 then
				print ("TESTS FAILED%N")
				(create {EXCEPTIONS}).die (1)
			elseif skipped > 0 then
				print ("ALL RUN TESTS PASSED (" + skipped.out
					+ " skeletal, awaiting Phase 5)%N")
			else
				print ("ALL TESTS PASSED%N")
			end
		end

feature {NONE} -- Test Runners

	run_lib_tests
			-- The Phase-1 set: real where logic is real, skeletal for Phase 5.
		do
			create lib_tests
			run_test (agent lib_tests.test_facade_wires_directwrite_first, "test_facade_wires_directwrite_first")
			run_test (agent lib_tests.test_facade_injected_backends, "test_facade_injected_backends")
			run_test (agent lib_tests.test_layout_total_function_and_cache_discipline, "test_layout_total_function_and_cache_discipline")
			run_test (agent lib_tests.test_layout_empty_text, "test_layout_empty_text")
			run_test (agent lib_tests.test_measured_width_empty_is_zero, "test_measured_width_empty_is_zero")
			run_test (agent lib_tests.test_font_list_value_digest, "test_font_list_value_digest")
			run_test (agent lib_tests.test_font_list_script_prepends, "test_font_list_script_prepends")
			run_test (agent lib_tests.test_font_list_twin_is_independent, "test_font_list_twin_is_independent")
			run_test (agent lib_tests.test_font_list_digest_is_injective, "test_font_list_digest_is_injective")
			run_test (agent lib_tests.test_statistics_counters, "test_statistics_counters")
			run_test (agent lib_tests.test_shaping_note_fields, "test_shaping_note_fields")
			run_test (agent lib_tests.test_layout_cache_verified_hit_and_demotion, "test_layout_cache_verified_hit_and_demotion")
			run_test (agent lib_tests.test_layout_cache_lru_eviction, "test_layout_cache_lru_eviction")
			run_test (agent lib_tests.test_asset_catalog_key_scheme, "test_asset_catalog_key_scheme")
			run_test (agent lib_tests.test_asset_catalog_injected_probe, "test_asset_catalog_injected_probe")
			run_test (agent lib_tests.test_null_bidi_levels_and_reorder, "test_null_bidi_levels_and_reorder")
			run_test (agent lib_tests.test_null_itemizer_intersection_contract, "test_null_itemizer_intersection_contract")
			run_test (agent lib_tests.test_null_itemizer_soft_breaks, "test_null_itemizer_soft_breaks")
			run_test (agent lib_tests.test_null_shaper_and_fallback_headless, "test_null_shaper_and_fallback_headless")
			run_test (agent lib_tests.test_registry_identity_and_ownership, "test_registry_identity_and_ownership")
			run_test (agent lib_tests.test_emoji_segmenter_degenerate_partition, "test_emoji_segmenter_degenerate_partition")
			run_native_test (agent lib_tests.test_dwrite_native_round_trip, "test_dwrite_native_round_trip")
			run_machine_test (agent lib_tests.test_font_realization_round_trip, "test_font_realization_round_trip")
			run_machine_test (agent lib_tests.test_family_existence_probe, "test_family_existence_probe")
			run_test (agent lib_tests.test_effective_digest_drops_absent_families, "test_effective_digest_drops_absent_families")
			run_skeletal_test (agent lib_tests.test_bidi_conformance_samples, "test_bidi_conformance_samples")
			run_skeletal_test (agent lib_tests.test_wrap_cluster_safety, "test_wrap_cluster_safety")
			run_skeletal_test (agent lib_tests.test_fallback_rescue, "test_fallback_rescue")
			run_skeletal_test (agent lib_tests.test_emoji_zwj_single_image_run, "test_emoji_zwj_single_image_run")
			run_skeletal_test (agent lib_tests.test_never_raises_fault_injection, "test_never_raises_fault_injection")
			run_skeletal_test (agent lib_tests.test_headless_full_pipeline, "test_headless_full_pipeline")
			run_skeletal_test (agent lib_tests.test_measured_width_sums_advances, "test_measured_width_sums_advances")
			run_skeletal_test (agent lib_tests.test_d015_chat_line, "test_d015_chat_line")
			run_skeletal_test (agent lib_tests.test_whitespace_measures_positive_under_realized_font,
				"test_whitespace_measures_positive_under_realized_font")
		end

	run_scoop_consumer
			-- The mandatory SCOOP consumer gate.
		do
			create scoop_consumer
			run_test (agent scoop_consumer.test_scoop_compatibility, "test_scoop_compatibility")
		end

feature {NONE} -- Implementation

	lib_tests: LIB_TESTS

	scoop_consumer: TEST_SCOOP_CONSUMER

	passed: INTEGER
			-- Tests that ran and asserted successfully.

	skipped: INTEGER
			-- [skeletal] Phase-5 markers: bodies still empty, NEVER counted
			-- as passes (ISSUE 18).

	failed: INTEGER
			-- Tests that raised.

	native_skipped: INTEGER
			-- [Phase 4 Task 1; widened Task 2] Tests that could not reach
			-- the machine capability they need - a live DirectWrite backend
			-- (Task 1) or real GDI font realization (Task 2). Counted APART
			-- from the Phase-5 skeletal `skipped' - so the skeletal number
			-- Phase 5 must drive to zero never moves because of a machine's
			-- capabilities - and never counted as a pass (ISSUE 18).

	run_test (a_test: PROCEDURE; a_name: STRING)
			-- Run a single test and update counters.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				print ("  PASS: " + a_name + "%N")
				passed := passed + 1
			end
		rescue
			print ("  FAIL: " + a_name + "%N")
			failed := failed + 1
			l_retried := True
			retry
		end

	run_native_test (a_test: PROCEDURE; a_name: STRING)
			-- [Phase 4 Task 1] Run a NATIVE round-trip test. It asserts for
			-- real when the backend is there; on a machine where
			-- `DWRITE_API.open' fails it reports an honest SKIP with the
			-- reason, never a pass.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				if lib_tests.native_round_trip_ran then
					print ("  PASS: " + a_name + "%N")
					passed := passed + 1
				else
					print ("  SKIP: " + a_name + " [native backend unavailable: "
						+ lib_tests.native_skip_reason + "]%N")
					native_skipped := native_skipped + 1
				end
			end
		rescue
			print ("  FAIL: " + a_name + "%N")
			failed := failed + 1
			l_retried := True
			retry
		end

	run_machine_test (a_test: PROCEDURE; a_name: STRING)
			-- [Phase 4 Task 2] Run a MACHINE-DEPENDENT test through the
			-- `begin_machine_test' protocol: the test asserts for real when
			-- the machine can realize the fonts it needs, and reports an
			-- honest SKIP with a reason when it cannot (no GDI realization;
			-- or, for the R1 probe, a machine that actually owns the family
			-- the test needs to be MISSING). Skips tally with the Task-1
			-- native skips - apart from the Phase-5 skeletal count and never
			-- as passes (ISSUE 18).
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				if lib_tests.machine_test_ran then
					print ("  PASS: " + a_name + "%N")
					passed := passed + 1
				else
					print ("  SKIP: " + a_name + " [machine cannot run it: "
						+ lib_tests.machine_skip_reason + "]%N")
					native_skipped := native_skipped + 1
				end
			end
		rescue
			print ("  FAIL: " + a_name + "%N")
			failed := failed + 1
			l_retried := True
			retry
		end

	run_skeletal_test (a_test: PROCEDURE; a_name: STRING)
			-- Run a Phase-5 MARKER whose body is still empty: it is
			-- executed (so a body that grows real assertions starts
			-- reporting immediately if it raises), but its clean return is
			-- reported and counted as a SKIP, never as a pass (ISSUE 18).
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				print ("  SKIP: " + a_name + " [skeletal - Phase 5]%N")
				skipped := skipped + 1
			end
		rescue
			print ("  FAIL: " + a_name + " [skeletal]%N")
			failed := failed + 1
			l_retried := True
			retry
		end

end
