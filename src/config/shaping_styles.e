note
	description: "[
		How one paragraph's characters are SET beyond its policy: spans
		that shrink, raise or small-cap a stretch (GW-08, for simple_bible:
		Strong's numbers raised small after a word, LORD in small capitals),
		or set it bold, italic or in another ink (GW-13: the emphasis and
		links of a rich document). A span changes size, baseline, weight,
		slant and ink; the family list and the direction stay the policy's.

		    scale       a fraction of the layout's pixel size
		                (`Min_scale' .. 1.0)
		    rise        baseline shift UP, as a fraction of the layout's
		                pixel size (`Min_rise' .. `Max_rise'); negative
		                lowers (a subscript)
		    small caps  lowercase letters are set as capitals at
		                `Small_caps_scale' of the span's size; capitals
		                stay full size. The SOURCE text never changes, so
		                search, copy and the caret still see "Lord".
		    weight      1 .. 1000 (700 bold); 0 keeps the policy's
		    italic      set the stretch italic; False keeps the policy's
		    ink         a number the HOST maps to a colour (0: the host's
		                default). The shaper never paints; it only cuts
		                the runs where the ink changes, so every run has
		                one ink and a paint hook can colour it
		                (SHAPING_CAIRO_BRIDGE.draw_layout_aligned_with).

		Where spans overlap, the one added later wins. A style change
		inside a word never makes a line-break opportunity: the facade
		glues the runs on either side (SHAPED_RUN.joins_next) unless the
		text itself could break there. A combining mark takes its base's
		style, so one cluster is never set at two sizes.
	]"
	author: "Larry Rix"

class
	SHAPING_STYLES

create
	make

feature {NONE} -- Initialization

	make
			-- No spans: every character set as the policy says.
		do
			create starts.make (4)
			create counts.make (4)
			create scales.make (4)
			create rises.make (4)
			create small_caps_flags.make (4)
			create weights.make (4)
			create italic_flags.make (4)
			create inks.make (4)
		ensure
			empty: is_empty
		end

feature -- Constants

	Superscript_scale: REAL_64 = 0.62
			-- `add_superscript''s size, of the layout's.

	Superscript_rise: REAL_64 = 0.38
			-- `add_superscript''s lift, of the layout's size.

	Small_caps_scale: REAL_64 = 0.78
			-- A small capital's size, of the span's.

	Min_scale: REAL_64 = 0.3

	Min_rise: REAL_64 = -0.5

	Max_rise: REAL_64 = 0.8

	Weight_bold: INTEGER = 700
			-- `add_bold''s weight.

feature -- Access

	count: INTEGER
			-- Spans held.
		do
			Result := starts.count
		ensure
			non_negative: Result >= 0
		end

	is_empty: BOOLEAN
		do
			Result := starts.is_empty
		ensure
			definition: Result = (count = 0)
		end

	span_start (a_k: INTEGER): INTEGER
		require
			in_range: a_k >= 1 and a_k <= count
		do
			Result := starts.i_th (a_k)
		end

	span_count (a_k: INTEGER): INTEGER
		require
			in_range: a_k >= 1 and a_k <= count
		do
			Result := counts.i_th (a_k)
		end

	scale_at (a_i: INTEGER): REAL_64
			-- The size character `a_i' is set at, of the layout's, before
			-- small caps; 1.0 where no span covers it.
		local
			k: INTEGER
		do
			k := span_covering (a_i)
			if k > 0 then
				Result := scales.i_th (k)
			else
				Result := 1.0
			end
		ensure
			in_range: Result >= Min_scale and Result <= 1.0
		end

	rise_at (a_i: INTEGER): REAL_64
			-- Character `a_i''s baseline lift, of the layout's size.
		local
			k: INTEGER
		do
			k := span_covering (a_i)
			if k > 0 then
				Result := rises.i_th (k)
			end
		ensure
			in_range: Result >= Min_rise and Result <= Max_rise
		end

	is_small_caps_at (a_i: INTEGER): BOOLEAN
			-- Is character `a_i' in a small-caps span?
		local
			k: INTEGER
		do
			k := span_covering (a_i)
			Result := k > 0 and then small_caps_flags.i_th (k)
		end

	weight_at (a_i: INTEGER): INTEGER
			-- The weight character `a_i' is set at; 0 where the policy's
			-- weight holds.
		local
			k: INTEGER
		do
			k := span_covering (a_i)
			if k > 0 then
				Result := weights.i_th (k)
			end
		ensure
			in_range: Result >= 0 and Result <= 1000
		end

	is_italic_at (a_i: INTEGER): BOOLEAN
			-- Is character `a_i' set italic by a span?
		local
			k: INTEGER
		do
			k := span_covering (a_i)
			Result := k > 0 and then italic_flags.i_th (k)
		end

	ink_at (a_i: INTEGER): INTEGER
			-- Character `a_i''s ink; 0 where no span gives one.
		local
			k: INTEGER
		do
			k := span_covering (a_i)
			if k > 0 then
				Result := inks.i_th (k)
			end
		ensure
			non_negative: Result >= 0
		end

	has_small_caps: BOOLEAN
			-- Does any span set small capitals?
		do
			Result := across small_caps_flags as f some f end
		end

	covers_any (a_from, a_count: INTEGER): BOOLEAN
			-- Does some span touch characters `a_from' .. `a_from' + `a_count' - 1?
		local
			k: INTEGER
		do
			from
				k := 1
			until
				k > count or Result
			loop
				Result := starts.i_th (k) < a_from + a_count
					and then starts.i_th (k) + counts.i_th (k) > a_from
				k := k + 1
			end
		end

	slice (a_from, a_count: INTEGER): SHAPING_STYLES
			-- The spans over characters `a_from' .. `a_from' + `a_count' - 1,
			-- cut to that stretch and numbered from 1, in the same order (so
			-- the later span still wins): the styles of one piece of a
			-- longer text, for a host that lays a text out one LF-separated
			-- piece at a time.
		require
			from_valid: a_from >= 1
			count_non_negative: a_count >= 0
		local
			k, lo, hi: INTEGER
		do
			create Result.make
			from
				k := 1
			until
				k > count
			loop
				lo := starts.i_th (k).max (a_from)
				hi := (starts.i_th (k) + counts.i_th (k) - 1).min (a_from + a_count - 1)
				if lo <= hi then
					Result.add_setting (lo - a_from + 1, hi - lo + 1, scales.i_th (k), rises.i_th (k),
						small_caps_flags.i_th (k), weights.i_th (k), italic_flags.i_th (k), inks.i_th (k))
				end
				k := k + 1
			end
		ensure
			never_more: Result.count <= count
		end

	digest: STRING_8
			-- Every span, in order: two style sets with the same digest
			-- set every character the same. Empty when `is_empty'.
		local
			k: INTEGER
		do
			create Result.make (count * 24)
			from
				k := 1
			until
				k > count
			loop
				Result.append_integer (starts.i_th (k))
				Result.append_character (',')
				Result.append_integer (counts.i_th (k))
				Result.append_character (',')
				Result.append (scales.i_th (k).out)
				Result.append_character (',')
				Result.append (rises.i_th (k).out)
				if small_caps_flags.i_th (k) then
					Result.append_character ('c')
				end
				if weights.i_th (k) /= 0 then
					Result.append_character ('w')
					Result.append_integer (weights.i_th (k))
				end
				if italic_flags.i_th (k) then
					Result.append_character ('i')
				end
				if inks.i_th (k) /= 0 then
					Result.append_character ('k')
					Result.append_integer (inks.i_th (k))
				end
				Result.append_character (';')
				k := k + 1
			end
		ensure
			empty_iff_no_spans: Result.is_empty = is_empty
		end

feature -- Element change

	add (a_start, a_count: INTEGER; a_scale, a_rise: REAL_64; a_small_caps: BOOLEAN)
			-- Set characters `a_start' .. `a_start' + `a_count' - 1 at
			-- `a_scale', lifted by `a_rise', small-capped or not.
		require
			start_valid: a_start >= 1
			count_positive: a_count > 0
			scale_valid: a_scale >= Min_scale and a_scale <= 1.0
			rise_valid: a_rise >= Min_rise and a_rise <= Max_rise
		do
			add_setting (a_start, a_count, a_scale, a_rise, a_small_caps, 0, False, 0)
		ensure
			one_more: count = old count + 1
			wins_at_its_start: scale_at (a_start) = a_scale and rise_at (a_start) = a_rise
				and is_small_caps_at (a_start) = a_small_caps
			policy_weight_and_ink: weight_at (a_start) = 0 and not is_italic_at (a_start)
				and ink_at (a_start) = 0
		end

	add_setting (a_start, a_count: INTEGER; a_scale, a_rise: REAL_64; a_small_caps: BOOLEAN;
			a_weight: INTEGER; a_italic: BOOLEAN; a_ink: INTEGER)
			-- [GW-13] Set characters `a_start' .. `a_start' + `a_count' - 1
			-- in every respect at once: size, lift, small capitals, weight
			-- (0: the policy's), italic and ink (0: the host's default). A
			-- host that layers styles (a bold link inside a superscript)
			-- flattens them and gives each stretch its whole setting here.
		require
			start_valid: a_start >= 1
			count_positive: a_count > 0
			scale_valid: a_scale >= Min_scale and a_scale <= 1.0
			rise_valid: a_rise >= Min_rise and a_rise <= Max_rise
			weight_valid: a_weight = 0 or (a_weight >= 1 and a_weight <= 1000)
			ink_non_negative: a_ink >= 0
		do
			starts.extend (a_start)
			counts.extend (a_count)
			scales.extend (a_scale)
			rises.extend (a_rise)
			small_caps_flags.extend (a_small_caps)
			weights.extend (a_weight)
			italic_flags.extend (a_italic)
			inks.extend (a_ink)
		ensure
			one_more: count = old count + 1
			wins_at_its_start: scale_at (a_start) = a_scale and rise_at (a_start) = a_rise
				and is_small_caps_at (a_start) = a_small_caps and weight_at (a_start) = a_weight
				and is_italic_at (a_start) = a_italic and ink_at (a_start) = a_ink
		end

	add_bold (a_start, a_count: INTEGER)
			-- [GW-13] Bold, at full size.
		require
			start_valid: a_start >= 1
			count_positive: a_count > 0
		do
			add_setting (a_start, a_count, 1.0, 0.0, False, Weight_bold, False, 0)
		ensure
			one_more: count = old count + 1
			bold: weight_at (a_start) = Weight_bold
		end

	add_italic (a_start, a_count: INTEGER)
			-- [GW-13] Italic, at full size.
		require
			start_valid: a_start >= 1
			count_positive: a_count > 0
		do
			add_setting (a_start, a_count, 1.0, 0.0, False, 0, True, 0)
		ensure
			one_more: count = old count + 1
			italic: is_italic_at (a_start)
		end

	add_ink (a_start, a_count, a_ink: INTEGER)
			-- [GW-13] Ink `a_ink', at full size: a link.
		require
			start_valid: a_start >= 1
			count_positive: a_count > 0
			ink_positive: a_ink > 0
		do
			add_setting (a_start, a_count, 1.0, 0.0, False, 0, False, a_ink)
		ensure
			one_more: count = old count + 1
			inked: ink_at (a_start) = a_ink
		end

	add_superscript (a_start, a_count: INTEGER)
			-- Raised small: a Strong's number after its word.
		require
			start_valid: a_start >= 1
			count_positive: a_count > 0
		do
			add (a_start, a_count, Superscript_scale, Superscript_rise, False)
		ensure
			one_more: count = old count + 1
			raised: rise_at (a_start) = Superscript_rise
		end

	add_small_caps (a_start, a_count: INTEGER)
			-- Small capitals: "Lord" set as the KJV sets LORD.
		require
			start_valid: a_start >= 1
			count_positive: a_count > 0
		do
			add (a_start, a_count, 1.0, 0.0, True)
		ensure
			one_more: count = old count + 1
			small_caps: is_small_caps_at (a_start)
		end

	wipe_out
		do
			starts.wipe_out
			counts.wipe_out
			scales.wipe_out
			rises.wipe_out
			small_caps_flags.wipe_out
			weights.wipe_out
			italic_flags.wipe_out
			inks.wipe_out
		ensure
			empty: is_empty
		end

	clamp_to (a_text_count: INTEGER)
			-- Fit a text now `a_text_count' characters long: spans past
			-- its end go, a span over its end is cut there.
		require
			non_negative: a_text_count >= 0
		local
			k: INTEGER
		do
			from
				k := count
			until
				k < 1
			loop
				if starts.i_th (k) > a_text_count then
					remove_span (k)
				elseif starts.i_th (k) + counts.i_th (k) - 1 > a_text_count then
					counts.put_i_th (a_text_count - starts.i_th (k) + 1, k)
				end
				k := k - 1
			end
		ensure
			never_more: count <= old count
		end

feature {NONE} -- Implementation

	starts, counts: ARRAYED_LIST [INTEGER]
	scales, rises: ARRAYED_LIST [REAL_64]
	small_caps_flags: ARRAYED_LIST [BOOLEAN]
	weights, inks: ARRAYED_LIST [INTEGER]
	italic_flags: ARRAYED_LIST [BOOLEAN]

	span_covering (a_i: INTEGER): INTEGER
			-- The LAST span covering character `a_i'; 0 for none.
		local
			k: INTEGER
		do
			from
				k := count
			until
				k < 1 or Result > 0
			loop
				if a_i >= starts.i_th (k) and then a_i < starts.i_th (k) + counts.i_th (k) then
					Result := k
				end
				k := k - 1
			end
		ensure
			in_range: Result >= 0 and Result <= count
		end

	remove_span (a_k: INTEGER)
		require
			in_range: a_k >= 1 and a_k <= count
		do
			starts.go_i_th (a_k)
			starts.remove
			counts.go_i_th (a_k)
			counts.remove
			scales.go_i_th (a_k)
			scales.remove
			rises.go_i_th (a_k)
			rises.remove
			small_caps_flags.go_i_th (a_k)
			small_caps_flags.remove
			weights.go_i_th (a_k)
			weights.remove
			italic_flags.go_i_th (a_k)
			italic_flags.remove
			inks.go_i_th (a_k)
			inks.remove
		ensure
			one_fewer: count = old count - 1
		end

invariant
	parallel: counts.count = starts.count and scales.count = starts.count
		and rises.count = starts.count and small_caps_flags.count = starts.count
		and weights.count = starts.count and italic_flags.count = starts.count
		and inks.count = starts.count

end
