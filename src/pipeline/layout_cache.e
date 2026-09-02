note
	description: "[
		Bounded LRU of immutable SHAPED_LAYOUTs keyed by the facade's digest
		of (text, width, pixel size, fonts digest, asset directory).

		R8 (Q11): a digest can collide, and painting another message's layout
		would be a silent correctness failure - so every HIT IS VERIFIED
		against the stored layout's own (source_text, width_pixels,
		pixel_size); a mismatch is demoted to a miss and the caller reshapes.
		`layout''s source_kept postcondition is thereby true BY CONSTRUCTION
		on every path, and the digest is free to be fast.

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
		is the promise (`put', `set_capacity', `wipe', miss paths).
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
			create order.make (a_capacity)
			order.compare_objects
		ensure
			capacity_set: capacity = a_capacity
			empty: count = 0
			model_empty: cache_model.is_empty and keys_model.count = 0
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

	item_verified (a_key: READABLE_STRING_8; a_text: READABLE_STRING_32;
			a_width_pixels, a_pixel_size: INTEGER): detachable SHAPED_LAYOUT
			-- The layout stored under `a_key' IF it really is a layout of
			-- (`a_text', `a_width_pixels', `a_pixel_size') - else Void
			-- (R8 demotion). Touches LRU recency on a hit.
		local
			l_key: STRING_8
		do
			l_key := a_key.to_string_8
			if attached storage.item (l_key) as al_layout
				and then al_layout.source_text.same_string_general (a_text)
				and then al_layout.width_pixels = a_width_pixels
				and then al_layout.pixel_size = a_pixel_size
			then
				touch (l_key)
				Result := al_layout
			end
		ensure
			verified_hit: attached Result as al_hit implies
				(al_hit.source_text.same_string_general (a_text)
				and al_hit.width_pixels = a_width_pixels
				and al_hit.pixel_size = a_pixel_size)
			from_store: attached Result implies cache_model.domain [a_key.to_string_8]
			model_unchanged: cache_model |=| old cache_model
			recency_touched_on_hit: attached Result implies
				(keys_model.count > 0 and then keys_model.last ~ a_key.to_string_8)
			no_touch_on_miss: Result = Void implies keys_model |=| old keys_model
		end

	has_verified (a_key: READABLE_STRING_8; a_text: READABLE_STRING_32;
			a_width_pixels, a_pixel_size: INTEGER): BOOLEAN
			-- Would `item_verified' answer non-Void? Pure: no recency touch.
		do
			Result := attached storage.item (a_key.to_string_8) as al_layout
				and then al_layout.source_text.same_string_general (a_text)
				and then al_layout.width_pixels = a_width_pixels
				and then al_layout.pixel_size = a_pixel_size
		ensure
			model_unchanged: cache_model |=| old cache_model
			order_untouched: keys_model |=| old keys_model
		end

feature -- Commands

	put (a_key: READABLE_STRING_8; a_layout: SHAPED_LAYOUT)
			-- Store `a_layout' under `a_key' (replacing any previous value),
			-- evicting the least recently used entry if full.
		local
			l_key: STRING_8
		do
			l_key := a_key.to_string_8
			if storage.has (l_key) then
				storage.force (a_layout, l_key)
				touch (l_key)
			else
				if storage.count >= capacity then
					evict_oldest
				end
				storage.put (a_layout, l_key)
				order.extend (l_key)
			end
		ensure
			stored: cache_model.domain [a_key.to_string_8]
			stored_value: cache_model [a_key.to_string_8] = a_layout
			others_kept_when_room: (old cache_model.count < capacity) implies
				cache_model |=| old cache_model.updated (a_key.to_string_8, a_layout)
			replace_is_exact: (old cache_model.domain [a_key.to_string_8]) implies
				cache_model |=| (old cache_model).updated (a_key.to_string_8, a_layout)
			evict_is_exact: (not old cache_model.domain [a_key.to_string_8]
				and old cache_model.count >= capacity) implies
				cache_model |=| (old cache_model).removed ((old keys_model).first)
					.updated (a_key.to_string_8, a_layout)
			lru_victim_gone: (not old cache_model.domain [a_key.to_string_8]
				and old cache_model.count >= capacity) implies
				not cache_model.domain [(old keys_model).first]
			count_exact: cache_model.count = (if old cache_model.domain [a_key.to_string_8]
				then old cache_model.count else (old cache_model.count + 1).min (capacity) end)
			key_now_most_recent: keys_model.count > 0 and then keys_model.last ~ a_key.to_string_8
			bounded_after: cache_model.count <= capacity
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
			newest_survive: keys_model |=| (old keys_model).tail (
				old cache_model.count - cache_model.count + 1)
		end

	wipe
			-- Drop every entry.
		do
			storage.wipe_out
			order.wipe_out
		ensure
			emptied: count = 0
			model_empty: cache_model.is_empty and keys_model.count = 0
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

	order: ARRAYED_LIST [STRING_8]
			-- Keys, oldest first (object comparison for value pruning).

	touch (a_key: STRING_8)
			-- Move `a_key' to most-recent.
		require
			known: order.has (a_key)
		do
			order.prune (a_key)
			order.extend (a_key)
		ensure
			count_kept: order.count = old order.count
			now_most_recent: order.last = a_key
			map_untouched: cache_model |=| old cache_model
		end

	evict_oldest
			-- Drop the least recently used entry.
		do
			if not order.is_empty then
				storage.remove (order.first)
				order.start
				order.remove
			end
		ensure
			one_fewer_or_was_empty: (old order.is_empty and order.is_empty)
				or (order.count = old order.count - 1 and storage.count = old storage.count - 1)
			victim_was_oldest: (not old order.is_empty) implies
				not cache_model.domain [(old keys_model).first]
		end

invariant
	bounded: count <= capacity
	capacity_positive: capacity > 0
	order_aligned: storage.count = order.count
	model_count_consistent: cache_model.count = count
	order_witness_aligned: keys_model.count = count

end
