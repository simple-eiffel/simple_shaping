note
	description: "[
		Bounded LRU of immutable SHAPED_LAYOUTs keyed by the facade's digest
		of (text, width, pixel size, fonts digest, asset directory).

		R8 (Q11): a digest can collide, and painting another message's layout
		would be a silent correctness failure - so every HIT IS VERIFIED
		against the stored layout's own (source_text, width_pixels,
		pixel_size) AND against the FONTS DIGEST the entry was built under;
		a mismatch on any of the four is demoted to a miss and the caller
		reshapes. `layout''s source_kept postcondition is thereby true BY
		CONSTRUCTION on every path, and the digest is free to be fast.

		R8 IS NOW BOUND, NOT ASPIRATIONAL (Phase 2 / ISSUE 2): R8 listed the
		fonts digest in the entry tuple, but the entry carried only the
		layout, so verification covered text/width/size and the FONT POLICY
		went unchecked - a colliding key could serve a layout computed under
		a different policy, invisibly. `put' now takes the fonts digest,
		`digests' stores it beside the layout, and `item_verified' /
		`has_verified' compare it. The facade's key is separately injective
		(FONT_LIST.digest length-prefixing), so this is belt AND braces - by
		design, since the key is the fast path and this is the honest one.

		Q2: plain LRU, default capacity 512 (~2.5x a 200-message scrollback).
		Confinement (DR-012): one cache per facade per processor; layouts are
		shared only WITHIN the owning processor.

		CQS note: `item_verified' touches LRU recency on a hit - recency is
		not model-visible state (05), so the query stays contract-pure:
		cache_model is unchanged.

		MODEL DECISION (Phase 1m): `cache_model' (key -> layout map) is THE
		abstract state; LRU recency is deliberately NOT part of it (05).
		`keys_model' (LRU order, oldest first) is a specification WITNESS:
		eviction and rebound postconditions name their victims through it,
		and `item_verified' may reorder it on a hit (the one lawful benign
		effect). Frame conditions are therefore stated over `cache_model'
		always, and over `keys_model' only where the LRU discipline itself
		is the promise (`set_capacity', `wipe').

		HOT FEATURES STATE THEIR CONTRACTS OVER THE STORE (2026-10-25).
		`item_verified', `has_verified', `put', `touch' and `evict_oldest'
		run on every shaped string, every frame. Their postconditions used
		to rebuild `cache_model' and compare it with `old cache_model';
		MML_MAP is list-based, so a build is O(n^2) and a comparison O(n^2),
		and under assertions a hit cost 1.8 ms with 20 entries and 418 ms
		with 400 (test_cache_hit_cost_does_not_grow_with_the_cache):
		simple_widgets' 100,000-row grid took seconds a frame and grew
		slower every frame. They now say the same things through O(1)
		queries - `has', `stored', `digest_of', `newest_key', `oldest_key'
		and `count' - and the full-model clauses stay on the rare commands
		(`make', `wipe', `set_capacity'). What the old clauses said beyond
		this (that no OTHER entry changed) follows from the bodies touching
		one key each; it is no longer checked at run time.
	]"
	author: "Larry Rix"

class
	LAYOUT_CACHE

inherit
	SHAPING_CONSTANTS

create
	make

feature {NONE} -- Initialization

	make (a_capacity: INTEGER)
			-- Empty cache bounded by `a_capacity'.
		require
			capacity_positive: a_capacity > 0
		do
			capacity := a_capacity
			create storage.make (a_capacity)
			create digests.make (a_capacity)
			create order.make (a_capacity)
			order.compare_objects
		ensure
			capacity_set: capacity = a_capacity
			empty: count = 0
			model_empty: cache_model.is_empty and keys_model.count = 0
			digests_empty: digests_model.is_empty
		end

feature -- Access

	capacity: INTEGER
			-- Maximum number of cached layouts.

	count: INTEGER
			-- Cached layouts now.
		do
			Result := storage.count
		ensure
			non_negative: Result >= 0
		end

	has (a_key: READABLE_STRING_8): BOOLEAN
			-- Is something stored under `a_key'? O(1).
		do
			Result := storage.has (a_key.to_string_8)
		end

	stored (a_key: READABLE_STRING_8): detachable SHAPED_LAYOUT
			-- The layout under `a_key', unverified; Void when none. O(1); no
			-- recency touch.
		do
			Result := storage.item (a_key.to_string_8)
		ensure
			void_iff_absent: (Result = Void) = not has (a_key)
		end

	digest_of (a_key: READABLE_STRING_8): detachable STRING_8
			-- The fonts digest the layout under `a_key' was built under. O(1).
		do
			Result := digests.item (a_key.to_string_8)
		end

	newest_key: detachable STRING_8
			-- The most recently used key; Void when empty. O(1).
		do
			if not order.is_empty then
				Result := order.last
			end
		end

	oldest_key: detachable STRING_8
			-- The least recently used key, the next to go; Void when empty.
		do
			if not order.is_empty then
				Result := order.first
			end
		end

	item_verified (a_key: READABLE_STRING_8; a_text: READABLE_STRING_32;
			a_width_pixels, a_pixel_size: INTEGER;
			a_fonts_digest: READABLE_STRING_8): detachable SHAPED_LAYOUT
			-- The layout stored under `a_key' IF it really is a layout of
			-- (`a_text', `a_width_pixels', `a_pixel_size') built under
			-- `a_fonts_digest' - else Void (R8 demotion). Touches LRU
			-- recency on a hit.
		local
			l_key: STRING_8
		do
			l_key := a_key.to_string_8
			if attached storage.item (l_key) as al_layout
				and then al_layout.source_text.same_string_general (a_text)
				and then al_layout.width_pixels = a_width_pixels
				and then al_layout.pixel_size = a_pixel_size
				and then attached digests.item (l_key) as al_digest
				and then al_digest.same_string (a_fonts_digest)
			then
				touch (l_key)
				Result := al_layout
			end
		ensure
			verified_hit: attached Result as al_hit implies
				(al_hit.source_text.same_string_general (a_text)
				and al_hit.width_pixels = a_width_pixels
				and al_hit.pixel_size = a_pixel_size)
			policy_verified: attached Result implies
				(attached digest_of (a_key) as al_d and then al_d.same_string (a_fonts_digest))
			from_store: attached Result implies stored (a_key) = Result
			count_unchanged: count = old count
			recency_touched_on_hit: attached Result implies
				(attached newest_key as al_k and then al_k.same_string (a_key))
			no_touch_on_miss: Result = Void implies
				(newest_key ~ old newest_key and oldest_key ~ old oldest_key)
		end

	has_verified (a_key: READABLE_STRING_8; a_text: READABLE_STRING_32;
			a_width_pixels, a_pixel_size: INTEGER;
			a_fonts_digest: READABLE_STRING_8): BOOLEAN
			-- Would `item_verified' answer non-Void? Pure: no recency touch.
		do
			Result := attached storage.item (a_key.to_string_8) as al_layout
				and then al_layout.source_text.same_string_general (a_text)
				and then al_layout.width_pixels = a_width_pixels
				and then al_layout.pixel_size = a_pixel_size
				and then attached digests.item (a_key.to_string_8) as al_digest
				and then al_digest.same_string (a_fonts_digest)
		ensure
			count_unchanged: count = old count
			order_untouched: newest_key ~ old newest_key and oldest_key ~ old oldest_key
		end

feature -- Commands

	put (a_key: READABLE_STRING_8; a_layout: SHAPED_LAYOUT;
			a_fonts_digest: READABLE_STRING_8)
			-- Store `a_layout' under `a_key' (replacing any previous value),
			-- remembering the FONT POLICY digest it was built under (R8,
			-- bound at Phase 2), evicting the least recently used entry if
			-- full.
		local
			l_key: STRING_8
		do
			l_key := a_key.to_string_8
			if storage.has (l_key) then
				storage.force (a_layout, l_key)
				digests.force (a_fonts_digest.to_string_8, l_key)
				touch (l_key)
			else
				if storage.count >= capacity then
					evict_oldest
				end
				storage.put (a_layout, l_key)
				digests.put (a_fonts_digest.to_string_8, l_key)
				order.extend (l_key)
			end
		ensure
			stored: has (a_key)
			stored_value: stored (a_key) = a_layout
			digest_stored: attached digest_of (a_key) as al_d and then al_d.same_string (a_fonts_digest)
			lru_victim_gone: (not old has (a_key) and old count >= capacity) implies
				(attached (old oldest_key) as al_victim implies not has (al_victim))
			count_exact: count = (if old has (a_key) then old count else (old count + 1).min (capacity) end)
			key_now_most_recent: attached newest_key as al_k and then al_k.same_string (a_key)
			bounded_after: count <= capacity
		end

	set_capacity (a_capacity: INTEGER)
			-- Rebound to `a_capacity', evicting LRU entries as needed.
		require
			capacity_positive: a_capacity > 0
		do
			capacity := a_capacity
			from until storage.count <= capacity loop
				evict_oldest
			end
		ensure
			capacity_set: capacity = a_capacity
			bounded_after: cache_model.count <= capacity
			count_exact: cache_model.count = (old cache_model.count).min (a_capacity)
			survivors_kept: cache_model |=| ((old cache_model) | cache_model.domain)
			digest_domain_matches: digests_model.domain |=| cache_model.domain
			newest_survive: keys_model |=| (old keys_model).tail (
				old cache_model.count - cache_model.count + 1)
		end

	wipe
			-- Drop every entry.
		do
			storage.wipe_out
			digests.wipe_out
			order.wipe_out
		ensure
			emptied: count = 0
			model_empty: cache_model.is_empty and keys_model.count = 0
			digests_empty: digests_model.is_empty
			capacity_kept: capacity = old capacity
		end

feature -- Model queries (simple_mml)

	cache_model: MML_MAP [STRING_8, SHAPED_LAYOUT]
			-- Key -> layout as a mathematical map (LRU order is NOT model
			-- state - deliberately, 05).
		local
			l_keys: ARRAY [STRING_8]
			i: INTEGER
		do
			create Result
			l_keys := storage.current_keys
			from i := l_keys.lower until i > l_keys.upper loop
				Result := Result.updated (l_keys [i], storage.definite_item (l_keys [i]))
				i := i + 1
			end
		end

	digests_model: MML_MAP [STRING_8, STRING_8]
			-- Key -> the FONT_LIST digest that key's layout was built under
			-- (R8's entry tuple, bound at Phase 2 / ISSUE 2). Its domain is
			-- `cache_model''s domain by invariant: every entry knows its
			-- policy, so no hit can cross a policy boundary.
		local
			l_keys: ARRAY [STRING_8]
			i: INTEGER
		do
			create Result
			l_keys := digests.current_keys
			from i := l_keys.lower until i > l_keys.upper loop
				Result := Result.updated (l_keys [i], digests.definite_item (l_keys [i]))
				i := i + 1
			end
		ensure
			same_count: Result.count = count
		end

	keys_model: MML_SEQUENCE [STRING_8]
			-- Keys in LRU order (oldest first) - eviction-order witness.
		do
			create Result
			across order as k loop
				Result := Result & k
			end
		ensure
			same_count: Result.count = count
		end

feature {NONE} -- Implementation

	storage: HASH_TABLE [SHAPED_LAYOUT, STRING_8]
			-- Key -> layout.

	digests: HASH_TABLE [STRING_8, STRING_8]
			-- Key -> the fonts digest the layout was built under (R8).

	order: ARRAYED_LIST [STRING_8]
			-- Keys, oldest first (object comparison for value pruning).

	touch (a_key: STRING_8)
			-- Move `a_key' to most-recent.
			-- `order.start' first: ARRAYED_LIST.prune searches only from the
			-- cursor onward, and the cursor stays wherever the previous
			-- prune left it. Without the reset, a key behind the cursor was
			-- not removed and `extend' appended a duplicate - the order list
			-- outgrew the table, and eviction later dropped keys whose
			-- layouts were already gone, so the cache was no longer bounded.
		require
			known: order.has (a_key)
		do
			order.start
			order.prune (a_key)
			order.extend (a_key)
		ensure
			count_kept: order.count = old order.count
			now_most_recent: order.last = a_key
			map_untouched: count = old count and stored (a_key) = old stored (a_key)
		end

	evict_oldest
			-- Drop the least recently used entry.
		do
			if not order.is_empty then
				storage.remove (order.first)
				digests.remove (order.first)
				order.start
				order.remove
			end
		ensure
			one_fewer_or_was_empty: (old order.is_empty and order.is_empty)
				or (order.count = old order.count - 1 and storage.count = old storage.count - 1)
			victim_was_oldest: attached (old oldest_key) as al_victim implies not has (al_victim)
		end

invariant
	-- Per-element and model clauses were removed 2026-09-11: an
	-- invariant runs on every feature call, so a clause that walks
	-- the collection or builds its MML model makes every call O(n)
	-- and a walk over the collection O(n^2) (simple_json read a
	-- 1434-element array in 158 s under DBC). Models belong in
	-- postconditions of the features that change them.
	bounded: count <= capacity
	capacity_positive: capacity > 0
	order_aligned: storage.count = order.count
	digests_aligned: digests.count = storage.count

end
