note
	description: "[
		Headless test double for seam 2 (UC-005/AC-7): items split EXACTLY at
		bidi level changes (satisfying the intersection contract with a
		single opaque script id 0 - adjacent items then always differ in
		level), soft breaks after ASCII spaces. Deterministic wrap tests need
		nothing more; zero native calls.
	]"
	author: "Larry Rix"

class
	NULL_SCRIPT_ITEMIZER

inherit
	SCRIPT_ITEMIZER

feature -- Operations

	itemize (a_text: READABLE_STRING_32; a_start, a_count: INTEGER;
			a_bidi: BIDI_RESULT): ARRAYED_LIST [SCRIPT_ITEM]
			-- <Precursor>
		local
			i, l_run_start: INTEGER
			l_level: NATURAL_8
		do
			create Result.make (4)
			if a_count > 0 then
				l_run_start := a_start
				l_level := a_bidi.level (a_start)
				from i := a_start + 1 until i > a_start + a_count - 1 loop
					if a_bidi.level (i) /= l_level then
						Result.extend (create {SCRIPT_ITEM}.make (l_run_start, i - l_run_start,
							0, l_level, create {ARRAY [NATURAL_8]}.make_empty))
						l_run_start := i
						l_level := a_bidi.level (i)
					end
					i := i + 1
				end
				Result.extend (create {SCRIPT_ITEM}.make (l_run_start, a_start + a_count - l_run_start,
					0, l_level, create {ARRAY [NATURAL_8]}.make_empty))
			end
		ensure then
			single_opaque_script: across Result as it all it.script_code = 0 end
		end

	soft_breaks (a_text: READABLE_STRING_32; a_item: SCRIPT_ITEM): ARRAY [BOOLEAN]
			-- <Precursor>
		local
			i: INTEGER
		do
			create Result.make_filled (False, 1, a_item.count)
			from i := 2 until i > a_item.count loop
				if a_text.code (a_item.start_index + i - 2) = 32 then
					Result [i] := True
				end
				i := i + 1
			end
		ensure then
			breaks_only_after_spaces: across 2 |..| Result.count as k all
				Result [k] implies a_text.code (a_item.start_index + k - 2) = 32 end
		end

end
