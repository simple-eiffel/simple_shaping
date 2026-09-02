note
	description: "Test application for simple_shaping (Phase 1)."
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
			failed := 0

			run_lib_tests
			run_scoop_consumer

			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + failed.out + " failed%N")

			if failed > 0 then
				print ("TESTS FAILED%N")
				(create {EXCEPTIONS}).die (1)
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
			run_test (agent lib_tests.test_bidi_conformance_samples, "test_bidi_conformance_samples [skeletal]")
			run_test (agent lib_tests.test_wrap_cluster_safety, "test_wrap_cluster_safety [skeletal]")
			run_test (agent lib_tests.test_fallback_rescue, "test_fallback_rescue [skeletal]")
			run_test (agent lib_tests.test_emoji_zwj_single_image_run, "test_emoji_zwj_single_image_run [skeletal]")
			run_test (agent lib_tests.test_never_raises_fault_injection, "test_never_raises_fault_injection [skeletal]")
			run_test (agent lib_tests.test_headless_full_pipeline, "test_headless_full_pipeline [skeletal]")
			run_test (agent lib_tests.test_measured_width_sums_advances, "test_measured_width_sums_advances [skeletal]")
			run_test (agent lib_tests.test_d015_chat_line, "test_d015_chat_line [skeletal]")
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

	failed: INTEGER

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

end
