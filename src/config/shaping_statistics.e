note
	description: "[
		Observability counters for one SIMPLE_SHAPING facade (FR-N02; FR-012's
		acceptance instrument).

		COUNTER DEFINITIONS (R7, binding):
		- shape_calls: shaping performed to PRODUCE RUNS (the layout path).
		- fallback_probes: coverage probes by the fallback seam - counted here
		  even when a probe's result is reused as the run's shape (the reuse is
		  an optimization; the call was a probe).
		- The two counters are DISJOINT. A cache hit performs ZERO of both -
		  that pair of facts is AC-3's assertion.
		- Counting happens in the facade/engines, never inside seam effectings
		  (doubles stay dumb; NULL_GLYPH_SHAPER has no counting duty).
		- R7 AMENDED (Phase 2 / ISSUE 7): fallback probes are counted by the
		  calling engine FROM FALLBACK_CHOICE.probes_performed - the walk is
		  inside LIST_FONT_FALLBACK and the caller can see the tally no other
		  way - never inside seam DOUBLES, which return 0. `record_fallback_probes'
		  is the one-call form the facade uses per seam-4 answer.
	]"
	author: "Larry Rix"

class
	SHAPING_STATISTICS

create
	make

feature {NONE} -- Initialization

	make
			-- All counters at zero.
		do
		ensure
			zeroed: shape_calls = 0 and cache_hits = 0 and cache_misses = 0
				and fallback_probes = 0 and notes_emitted = 0
		end

feature -- Access

	shape_calls: INTEGER
			-- Run-producing shaper invocations (R7).

	cache_hits: INTEGER
			-- Verified layout-cache hits.

	cache_misses: INTEGER
			-- Layout-cache misses (including R8 demotions).

	fallback_probes: INTEGER
			-- Coverage-probe shaper invocations (R7; disjoint from `shape_calls`).

	notes_emitted: INTEGER
			-- SHAPING_NOTEs attached to produced layouts.

feature -- Model queries (simple_mml)

	counters_model: MML_SEQUENCE [INTEGER]
			-- The five counters as one mathematical sequence, in the fixed
			-- order 1 = shape_calls, 2 = cache_hits, 3 = cache_misses,
			-- 4 = fallback_probes, 5 = notes_emitted - so a frame elsewhere
			-- can say "statistics untouched" in one clause.
		do
			create Result
			Result := Result & shape_calls & cache_hits & cache_misses
				& fallback_probes & notes_emitted
		ensure
			arity: Result.count = 5
			shape_calls_slot: Result [1] = shape_calls
			notes_slot: Result [5] = notes_emitted
		end

feature -- Commands

	record_shape_call
			-- One run-producing shape happened.
		do
			shape_calls := shape_calls + 1
		ensure
			counted: shape_calls = old shape_calls + 1
			others_unchanged: cache_hits = old cache_hits and cache_misses = old cache_misses
				and fallback_probes = old fallback_probes and notes_emitted = old notes_emitted
			model_exact: counters_model |=| (old counters_model).replaced_at (1, old shape_calls + 1)
		end

	record_cache_hit
			-- One verified cache hit happened.
		do
			cache_hits := cache_hits + 1
		ensure
			counted: cache_hits = old cache_hits + 1
			others_unchanged: shape_calls = old shape_calls and cache_misses = old cache_misses
				and fallback_probes = old fallback_probes and notes_emitted = old notes_emitted
			model_exact: counters_model |=| (old counters_model).replaced_at (2, old cache_hits + 1)
		end

	record_cache_miss
			-- One cache miss (or R8 demotion) happened.
		do
			cache_misses := cache_misses + 1
		ensure
			counted: cache_misses = old cache_misses + 1
			others_unchanged: shape_calls = old shape_calls and cache_hits = old cache_hits
				and fallback_probes = old fallback_probes and notes_emitted = old notes_emitted
			model_exact: counters_model |=| (old counters_model).replaced_at (3, old cache_misses + 1)
		end

	record_fallback_probes (a_count: INTEGER)
			-- `a_count' coverage probes happened inside one seam-4 answer
			-- (R7 amended: the facade passes FALLBACK_CHOICE.probes_performed).
		require
			count_non_negative: a_count >= 0
		do
			fallback_probes := fallback_probes + a_count
		ensure
			counted: fallback_probes = old fallback_probes + a_count
			others_unchanged: shape_calls = old shape_calls and cache_hits = old cache_hits
				and cache_misses = old cache_misses and notes_emitted = old notes_emitted
			model_exact: counters_model |=| (old counters_model).replaced_at (4, old fallback_probes + a_count)
		end

	record_fallback_probe
			-- One coverage probe happened.
		do
			fallback_probes := fallback_probes + 1
		ensure
			counted: fallback_probes = old fallback_probes + 1
			others_unchanged: shape_calls = old shape_calls and cache_hits = old cache_hits
				and cache_misses = old cache_misses and notes_emitted = old notes_emitted
			model_exact: counters_model |=| (old counters_model).replaced_at (4, old fallback_probes + 1)
		end

	record_note
			-- One degradation note was emitted.
		do
			notes_emitted := notes_emitted + 1
		ensure
			counted: notes_emitted = old notes_emitted + 1
			others_unchanged: shape_calls = old shape_calls and cache_hits = old cache_hits
				and cache_misses = old cache_misses and fallback_probes = old fallback_probes
			model_exact: counters_model |=| (old counters_model).replaced_at (5, old notes_emitted + 1)
		end

	wipe
			-- Reset every counter (test isolation).
		do
			shape_calls := 0
			cache_hits := 0
			cache_misses := 0
			fallback_probes := 0
			notes_emitted := 0
		ensure
			zeroed: shape_calls = 0 and cache_hits = 0 and cache_misses = 0
				and fallback_probes = 0 and notes_emitted = 0
			model_zeroed: counters_model.is_constant (0)
		end

invariant
	counters_non_negative: shape_calls >= 0 and cache_hits >= 0 and cache_misses >= 0
		and fallback_probes >= 0 and notes_emitted >= 0
	model_arity: counters_model.count = 5

end
