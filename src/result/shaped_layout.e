note
	description: "[
		One paragraph's finished layout: lines (each with runs in visual
		order), total size, base direction, and degradation notes.

		TOTAL-FUNCTION RESULT (NFR-011): a layout is ALWAYS paintable; it
		cannot fail, only degrade, and every degradation is a SHAPING_NOTE.
		There is deliberately no is_success query and no XOR error pattern.

		Immutable value - safely shared WITHIN one processor (the cache hands
		the same object out repeatedly); never passed `separate` (DR-012).
		Consumers size bubbles from `total_height` ALWAYS (R10); `line_height`
		on the facade is only for empty-message minimums.
	]"
	author: "Larry Rix"

class
	SHAPED_LAYOUT

inherit
	SHAPING_CONSTANTS

create
	make

feature {NONE} -- Initialization

	make (a_source_text: READABLE_STRING_32; a_width_pixels, a_pixel_size: INTEGER;
			a_base_direction: INTEGER; a_lines: ARRAYED_LIST [SHAPED_LINE];
			a_notes: ARRAYED_LIST [SHAPING_NOTE])
			-- Layout of `a_source_text` at `a_width_pixels`/`a_pixel_size`.
		require
			parameters_sane: a_width_pixels >= 0 and a_pixel_size > 0
			direction_resolved: a_base_direction = Direction_ltr or a_base_direction = Direction_rtl
			at_least_one_line: not a_lines.is_empty
			lines_cover_source: lines_partition_text (a_lines, a_source_text.count)
		do
			create source_text.make_from_string_general (a_source_text)
			width_pixels := a_width_pixels
			pixel_size := a_pixel_size
			base_direction := a_base_direction
			lines := a_lines
			notes := a_notes
			across a_lines as l loop
				total_height := total_height + l.height
				if l.width > total_width then
					total_width := l.width
				end
			end
		ensure
			source_kept: source_text.same_string_general (a_source_text)
			parameters_kept: width_pixels = a_width_pixels and pixel_size = a_pixel_size
			direction_kept: base_direction = a_base_direction
			lines_kept: lines = a_lines
			notes_kept: notes = a_notes
		end

feature -- Access

	source_text: IMMUTABLE_STRING_32
			-- The paragraph this layout renders.

	width_pixels: INTEGER
			-- Wrap width this layout was computed for (No_wrap = 0).

	pixel_size: INTEGER
			-- Pixel size this layout was shaped at.

	base_direction: INTEGER
			-- Resolved paragraph direction (first-strong or forced).

	lines: ARRAYED_LIST [SHAPED_LINE]
			-- The visual lines, top to bottom.

	notes: ARRAYED_LIST [SHAPING_NOTE]
			-- Every degradation that happened producing this layout.

	total_width: REAL_64
			-- Widest line's width.

	total_height: REAL_64
			-- Sum of line heights.

	sum_of_line_heights: REAL_64
			-- Fold of line heights, in order (invariant witness).
		do
			across lines as l loop
				Result := Result + l.height
			end
		ensure
			non_negative: Result >= 0.0
		end

feature -- Status

	has_notes: BOOLEAN
			-- Did anything degrade?
		do
			Result := not notes.is_empty
		ensure
			definition: Result = not notes.is_empty
		end

	covers_all_characters: BOOLEAN
			-- Do the lines cover every source character exactly once, in
			-- order (DR-008)? The definition query `layout`'s contract uses.
		do
			Result := lines_partition_text (lines, source_text.count)
		ensure
			definition: Result = lines_partition_text (lines, source_text.count)
		end

	respects_width: BOOLEAN
			-- Does every line fit `width_pixels`, or carry the overflow flag?
			-- (Meaningful when width_pixels > 0; vacuously True at No_wrap.)
		do
			Result := True
			if width_pixels > 0 then
				across lines as l loop
					Result := Result and (l.width <= width_pixels.to_double or l.is_overflowing)
				end
			end
		end

feature -- Model queries (simple_mml)

	lines_model: MML_SEQUENCE [SHAPED_LINE]
			-- Lines as a mathematical sequence.
		do
			create Result
			across lines as l loop
				Result := Result & l
			end
		ensure
			same_count: Result.count = lines.count
		end

	notes_model: MML_SEQUENCE [SHAPING_NOTE]
			-- Notes as a mathematical sequence.
		do
			create Result
			across notes as n loop
				Result := Result & n
			end
		ensure
			same_count: Result.count = notes.count
		end

invariant
	at_least_one_line: not lines.is_empty
	coverage_holds: covers_all_characters
	sizes_non_negative: total_width >= 0.0 and total_height >= 0.0
	height_is_sum: total_height = sum_of_line_heights
	parameters_positive: pixel_size > 0 and width_pixels >= 0
	direction_resolved: base_direction = Direction_ltr or base_direction = Direction_rtl

end
