note
	description: "[
		THE production existence probe behind EMOJI_ASSET_CATALOG (Task 8):
		is this path a file on disk, or not?

		WHY IT IS AN OBJECT AND NOT A ROUTINE OF THE FACADE. The catalog
		resolves through an INJECTED function so that it never opens a file
		itself - which is what keeps it testable with pure predicates and
		keeps disk access out of its contracts. The facade must therefore
		hand it an agent, and the facade builds its catalog inside a
		CREATION procedure, where an agent closed on Current is illegal
		under void safety: Current is not properly set yet (VEVI - `catalog'
		and `segmenter' are precisely the attributes still unset on that
		line). A separate, stateless probe object, created first, closes the
		agent over ITSELF instead of over the half-built facade.

		NEVER RAISES (NFR-011): a malformed, unreachable or
		permission-denied path answers False; it does not fail. A False here
		is not an error - it is rung 3 of the FR-007 ladder, and
		EMOJI_SEGMENTER degrades that sequence to plain text with a
		Note_emoji_degraded.

		Stateless, so one instance per facade is plenty and SCOOP
		confinement costs nothing.
	]"
	author: "Larry Rix"

class
	EMOJI_FILE_PROBE

feature -- Status

	exists (a_path: READABLE_STRING_32): BOOLEAN
			-- Does `a_path' name a file that is really on disk? This is the
			-- ONE place in the library where the emoji assets are actually
			-- looked for.
		require
			path_not_empty: not a_path.is_empty
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			Result := l_file.exists
		end

end
