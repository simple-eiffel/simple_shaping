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
		end

	wipe
			-- Drop every entry.
		do
			storage.wipe_out
			order.wipe_out
		ensure
			emptied: count = 0
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
		do
			order.prune (a_key)
			order.extend (a_key)
		end

	evict_oldest
			-- Drop the least recently used entry.
		do
			if not order.is_empty then
				storage.remove (order.first)
				order.start
				order.remove
			end
		end

invariant
	bounded: count <= capacity
	capacity_positive: capacity > 0
	order_aligned: storage.count = order.count

end
