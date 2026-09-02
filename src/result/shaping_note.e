note
	description: "[
		One degradation/diagnostic record (NFR-011 observability channel).

		A layout cannot fail - it degrades, and every degradation is one of
		these facts: code, human-readable message, and the logical source
		range it concerns. Immutable value; the invariant is the frame.
	]"
	author: "Larry Rix"

class
	SHAPING_NOTE

inherit
	SHAPING_CONSTANTS

create
	make

feature {NONE} -- Initialization

	make (a_code: INTEGER; a_message: READABLE_STRING_32; a_source_start, a_source_count: INTEGER)
			-- Record degradation `a_code` about characters
			-- `a_source_start` .. `a_source_start + a_source_count - 1`.
		require
			code_known: is_valid_note_code (a_code)
			message_not_empty: not a_message.is_empty
			range_sane: a_source_start >= 0 and a_source_count >= 0
		do
			code := a_code
			create message.make_from_string_general (a_message)
			source_start := a_source_start
			source_count := a_source_count
		ensure
			code_set: code = a_code
			message_kept: message.same_string_general (a_message)
			range_set: source_start = a_source_start and source_count = a_source_count
		end

feature -- Access

	code: INTEGER
			-- One of SHAPING_CONSTANTS' Note_* codes.

	message: IMMUTABLE_STRING_32
			-- Human-readable specifics.

	source_start: INTEGER
			-- First concerned character (1-based; 0 = whole paragraph).

	source_count: INTEGER
			-- Number of concerned characters (0 = not range-specific).

	code_name: STRING_8
			-- Stable name for `code` (log-friendly).
		do
			inspect code
			when 1 then Result := "fallback_exhausted"
			when 2 then Result := "emoji_degraded"
			when 3 then Result := "backend_error_recovered"
			when 4 then Result := "family_missing"
			when 5 then Result := "asset_missing"
			else Result := "unknown"
			end
		ensure
			never_empty: not Result.is_empty
		end

invariant
	code_known: is_valid_note_code (code)
	message_not_empty: not message.is_empty
	range_sane: source_start >= 0 and source_count >= 0

end
