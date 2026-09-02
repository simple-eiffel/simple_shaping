note
	description: "[
		Asset path -> decoded CAIRO_SURFACE, memoized (Task 13, A-C08).

		ZERO WIC, ZERO COM (A-C08/OQ-4). Emoji artwork is decoded by
		`CAIRO_SURFACE.make_from_png' - a function simple_cairo already
		bound before this task existed - so the paint bridge adds no image
		pipeline, no COM apartment and no upward dependency on a consumer's
		decoder. simple_chat may still WIC-decode its own attachments;
		emoji never touch WIC.

		UNBOUNDED, AND DELIBERATELY SO. This cache never evicts. A chat pane
		touches a few dozen distinct emoji in a session and a Noto png/128
		surface is 128 x 128 x 4 = 64 KiB, so a hundred of them cost about
		6.4 MiB - cheaper than the alternative, which is not memory but
		LIFETIME: an evicted surface is one a repaint is about to decode
		again, and destroying a surface some context still holds as its
		source is a use-after-free that cairo reports as a poisoned status,
		not as an exception. `dispose_all' is the ONE release point, and its
		caller (the facade, one per processor - DR-012) owns it.

		WRITE-ONCE MEMO, contracted the way EMOJI_ASSET_CATALOG.has_asset is:
		the map only ever GROWS, by at most one entry per call, and an entry
		already in it is never rewritten (`surfaces_write_once'). So the
		object handed back for a path is the SAME object on every later ask,
		which is what lets a bridge blit it without re-decoding.

		NEVER RAISES (NFR-011), AND THAT COSTS A RESCUE. A path that names
		no file, names an unreadable file, or holds a byte cairo's PNG
		loader refuses answers Void from `surface' and False from
		`has_surface'; nothing is memoized for it.

		Two defenses, because one is not enough. The FIRST is a cheap
		existence-and-readability gate, so the ordinary miss - an asset that
		simply is not there - never reaches cairo at all. The SECOND is
		`surface''s rescue, and the reason it must exist is a supplier
		contract this library cannot change: `cairo_image_surface_create_-
		from_png' answers a failed load with a STATIC ERROR SURFACE - a
		non-null handle whose status is non-zero - and CAIRO_SURFACE's own
		invariant, `destroyed_implies_null: not is_valid implies handle =
		default_pointer', is violated the instant such a surface leaves its
		creation procedure. So a corrupt-but-present PNG raises inside the
		supplier, before any query of ours can inspect it, and every
		qualified call on that object - `is_valid' and `destroy' included -
		raises too. The rescue turns that into one counted failure and a Void
		answer, which is what NFR-011 requires of everything below the
		facade. An error surface is therefore never destroyed here: there is
		nothing to free (cairo's is static) and the attempt would itself
		raise.
	]"
	author: "Larry Rix"

class
	EMOJI_SURFACE_CACHE

create
	make

feature {NONE} -- Initialization

	make
			-- Empty cache.
		do
			create cached.make (32)
		ensure
			nothing_cached: cached_model.is_empty
			counters_zero: decode_count = 0 and failure_count = 0
		end

feature -- Access

	surface (a_path: READABLE_STRING_32): detachable CAIRO_SURFACE
			-- The decoded artwork at `a_path', decoded on the FIRST ask and
			-- handed back unchanged on every later one; Void when `a_path'
			-- names nothing this machine can read as a PNG.
			--
			-- The Void answer is the whole degradation story (NFR-011): the
			-- bridge skips that run and records why, and nothing raises.
		require
			path_not_empty: not a_path.is_empty
		local
			l_key: STRING_32
			l_new: CAIRO_SURFACE
			l_decode_raised: BOOLEAN
		do
			l_key := a_path.as_string_32
			if attached cached.item (l_key) as al_cached then
				Result := al_cached
			elseif l_decode_raised then
					-- The retry pass: the decode below raised, the miss is
					-- already counted, and the answer is Void.
			elseif a_path.is_valid_as_string_8 and then is_readable_file (a_path) then
					-- cairo's PNG loader takes a NARROW path, so a path this
					-- machine cannot narrow is a miss rather than an
					-- exception; and the file must actually be readable, so
					-- the ordinary miss never reaches the loader at all.
				decode_count := decode_count + 1
				create l_new.make_from_png (a_path)
				if l_new.is_valid then
					cached.put (l_new, l_key)
					Result := l_new
				else
						-- Only reachable with invariant checking OFF: with it
						-- on, CAIRO_SURFACE's `destroyed_implies_null' fires
						-- first and the rescue below catches it. Either way an
						-- unusable surface is never cached - and never
						-- `destroy'ed, because cairo's failed-load surface is
						-- a static object and a qualified call on it is
						-- precisely what that invariant refuses.
					failure_count := failure_count + 1
				end
			else
				failure_count := failure_count + 1
			end
		ensure
			decoded_is_valid: attached Result implies Result.is_valid
			hit_is_cached: attached Result implies cached_model.domain [a_path.as_string_32]
			hit_is_the_cached_one: attached Result implies
				cached_model [a_path.as_string_32] = Result
			memo_only_grows: cached_model.count >= old cached_model.count
			growth_bounded: cached_model.count <= old cached_model.count + 1
			domain_monotone: (old cached_model).domain <= cached_model.domain
			surfaces_write_once: (cached_model | (old cached_model).domain) |=| old cached_model
			miss_memoizes_nothing: Result = Void implies cached_model |=| old cached_model
			one_decode_at_most: decode_count <= old decode_count + 1
			failures_only_grow: failure_count >= old failure_count
		rescue
				-- CONTAINMENT (NFR-011): a PNG cairo refuses raises inside
				-- the supplier's own invariant, which no contract of ours can
				-- prevent. Count it once, answer Void, and let a SECOND
				-- failure propagate rather than spin.
			if not l_decode_raised then
				l_decode_raised := True
				failure_count := failure_count + 1
				retry
			end
		end

	count: INTEGER
			-- Surfaces held.
		do
			Result := cached.count
		ensure
			non_negative: Result >= 0
		end

	decode_count: INTEGER
			-- How many times a PNG was actually handed to cairo. A second
			-- ask for a path already held must NOT move this - that is what
			-- "cached" means, stated as a number a test can read.

	failure_count: INTEGER
			-- How many asks produced no surface (missing file, unreadable
			-- file, a path cairo's narrow loader cannot take).

feature -- Status

	has_surface (a_path: READABLE_STRING_32): BOOLEAN
			-- Can `a_path' be painted? Decodes on the first ask, exactly as
			-- `surface' does, and answers False - never raises - when it
			-- cannot.
		require
			path_not_empty: not a_path.is_empty
		do
			Result := attached surface (a_path)
		ensure
			definition: Result = cached_model.domain [a_path.as_string_32]
		end

	is_cached (a_path: READABLE_STRING_32): BOOLEAN
			-- Is `a_path' ALREADY decoded? A pure question: unlike
			-- `has_surface' it never touches the disk and never memoizes.
		require
			path_not_empty: not a_path.is_empty
		do
			Result := cached.has (a_path.as_string_32)
		ensure
			definition: Result = cached_model.domain [a_path.as_string_32]
			memo_unchanged: cached_model |=| old cached_model
			nothing_decoded: decode_count = old decode_count
		end

feature -- Commands

	dispose_all
			-- Destroy every held surface. THE one release point (see the
			-- class note): call it when the owning facade goes, never while
			-- a context may still hold one of these as its source.
		do
			across cached as s loop
				s.destroy
			end
			cached.wipe_out
		ensure
			emptied: cached_model.is_empty
			count_zero: count = 0
		end

feature -- Model queries (simple_mml)

	cached_model: MML_MAP [STRING_32, CAIRO_SURFACE]
			-- Path -> surface as a mathematical map.
		local
			l_keys: ARRAY [STRING_32]
			i: INTEGER
		do
			create Result
			l_keys := cached.current_keys
			from i := l_keys.lower until i > l_keys.upper loop
				Result := Result.updated (l_keys [i], cached.definite_item (l_keys [i]))
				i := i + 1
			end
		end

feature {NONE} -- Implementation

	cached: HASH_TABLE [CAIRO_SURFACE, STRING_32]
			-- Absolute path -> the decoded surface.

	is_readable_file (a_path: READABLE_STRING_32): BOOLEAN
			-- Is there a readable file at `a_path'? The cheap gate that
			-- keeps the ordinary miss - an asset that simply is not there -
			-- from ever reaching cairo's loader (see the class note).
		require
			path_not_empty: not a_path.is_empty
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			Result := l_file.exists and then l_file.is_readable
		end

invariant
	counters_non_negative: decode_count >= 0 and failure_count >= 0
	only_paintable_surfaces_held: across cached as s all s.is_valid end

end
