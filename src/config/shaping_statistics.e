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

feature -- Commands

	record_shape_call
			-- One run-producing shape happened.
		do
			shape_calls := shape_calls + 1
		ensure
			counted: shape_calls = old shape_calls + 1
			others_unchanged: cache_hits = old cache_hits and cache_misses = old cache_misses
				and fallback_probes = old fallback_probes and notes_emitted = old notes_emitted
		end

	record_cache_hit
			-- One verified cache hit happened.
		do
			cache_hits := cache_hits + 1
		ensure
			counted: cache_hits = old cache_hits + 1
			others_unchanged: shape_calls = old shape_calls and cache_misses = old cache_misses
				and fallback_probes = old fallback_probes and notes_emitted = old notes_emitted
		end

	record_cache_miss
			-- One cache miss (or R8 demotion) happened.
		do
			cache_misses := cache_misses + 1
		ensure
			counted: cache_misses = old cache_misses + 1
			others_unchanged: shape_calls = old shape_calls and cache_hits = old cache_hits
				and fallback_probes = old fallback_probes and notes_emitted = old notes_emitted
		end

	record_fallback_probe
			-- One coverage probe happened.
		do
			fallback_probes := fallback_probes + 1
		ensure
			counted: fallback_probes = old fallback_probes + 1
			others_unchanged: shape_calls = old shape_calls and cache_hits = old cache_hits
				and cache_misses = old cache_misses and notes_emitted = old notes_emitted
		end

	record_note
			-- One degradation note was emitted.
		do
			notes_emitted := notes_emitted + 1
		ensure
			counted: notes_emitted = old notes_emitted + 1
			others_unchanged: shape_calls = old shape_calls and cache_hits = old cache_hits
				and cache_misses = old cache_misses and fallback_probes = old fallback_probes
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
		end

invariant
	counters_non_negative: shape_calls >= 0 and cache_hits >= 0 and cache_misses >= 0
		and fallback_probes >= 0 and notes_emitted >= 0

end
