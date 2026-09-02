note
	description: "[
		THE PAINT HALF (FR-010, Task 13): walk a finished SHAPED_LAYOUT and
		put it on a CAIRO_CONTEXT. The only class in simple_shaping that
		knows cairo exists besides SHAPING_FONT's face, and the reason
		`src/bridge/' is its own cluster: a future renderer ignores it
		cleanly.

		CAIRO NEVER RE-MEASURES. Every number painted here was decided by the
		shaper: glyph ids are physical indices of the run's own HFONT, and
		the positions handed to `show_glyphs' are ABSOLUTE user-space
		baselines computed as pen + the run's own x/y positions. No
		`show_text', no `text_extents', no font selection by family name -
		re-measuring would silently re-shape, which is exactly what a
		shaping library exists to prevent.

		THE SAME-N TRAP, AND WHY `prepare_context' IS NOT DECORATION. Shaping
		runs at pixel size N and painting must therefore call
		`set_font_size (N)' on a face built from an HFONT of that same size
		(DR-009). Measured on cairo 1.17.2 / win64: at exactly that
		coincidence, and with the DEFAULT font antialias mode, cairo's win32
		backend reuses the caller's HFONT as its own internal SCALED font -
		which it builds at 32 x N - so glyphs render at about 1/32 size and
		NOTHING reports an error. Same-N is the one case a shaping caller is
		always in. `prepare_context' sets an explicit mode
		(`Antialias_subpixel', which keeps ClearType) before any glyph is
		drawn, which forces cairo to build a properly scaled font of its own.
		See CAIRO_FONT_FACE's note in simple_cairo 1.3.0 and
		`test_bridge_real_backend_paints_full_size_glyphs' here, whose ink
		bounding box is this library's own tripwire.

		DEGRADATION IS A COUNTER, NOT AN EXCEPTION (NFR-011). A run whose
		font never realized, whose cairo face came back invalid, or whose
		emoji asset will not decode is SKIPPED: `skipped_runs' rises and
		`last_skip_note' says why. Painting a layout can therefore never
		fail, only paint less - and `every_run_accounted' states that every
		run was either painted or counted as skipped, so a run can never be
		silently dropped.

		WHERE AN IMAGE BOX SITS. An IMAGE_RUN's box is placed with its BOTTOM
		EDGE ON THE BASELINE and scaled from the asset's own pixel size into
		`width' x `height' - the box the segmenter/facade already fixed
		(FR-007). The bridge honors a box; it never resizes one.

		CONSUMERS NEVER TOUCH GLYPH ARRAYS. `draw_layout' is the whole API a
		painter needs; the `attached {GLYPH_RUN}' / `attached {IMAGE_RUN}'
		dispatch over SHAPED_RUN's two closed heirs lives here and nowhere
		else.
	]"
	author: "Larry Rix"

class
	SHAPING_CAIRO_BRIDGE

create
	make, make_with_cache

feature {NONE} -- Initialization

	make
			-- A bridge with its own emoji surface cache.
		do
			create surfaces.make
		ensure
			own_cache_empty: surfaces.count = 0
			nothing_painted: painted_runs = 0 and skipped_runs = 0
			no_note: last_skip_note.is_empty
		end

	make_with_cache (a_cache: EMOJI_SURFACE_CACHE)
			-- A bridge sharing `a_cache' - the shape a facade wants, so one
			-- decoded robot serves every pane on the processor.
		do
			surfaces := a_cache
		ensure
			cache_shared: surfaces = a_cache
			nothing_painted: painted_runs = 0 and skipped_runs = 0
			no_note: last_skip_note.is_empty
		end

feature -- Access

	surfaces: EMOJI_SURFACE_CACHE
			-- Where emoji artwork is decoded and held (A-C08).

	painted_runs: INTEGER
			-- Runs actually put on a context since the last `reset_counters'.

	skipped_runs: INTEGER
			-- Runs that DEGRADED (no realized font, no valid face, no
			-- surface) since the last `reset_counters'. Never an exception;
			-- see the class note.

	last_skip_note: STRING_8
			-- Why the most recent skip happened; empty when none has.
		attribute
			create Result.make_empty
		end

	run_count (a_layout: SHAPED_LAYOUT): INTEGER
			-- How many runs `draw_layout' would visit in `a_layout' - the
			-- witness `every_run_accounted' is stated against.
		do
			across a_layout.lines as l loop
				Result := Result + l.runs.count
			end
		ensure
			non_negative: Result >= 0
		end

feature -- Painting

	draw_layout (a_context: CAIRO_CONTEXT; a_layout: SHAPED_LAYOUT; a_x, a_y: REAL_64)
			-- Paint every line of `a_layout' with its TOP-LEFT corner at
			-- (`a_x', `a_y'), stacking lines by their own heights. Each
			-- line's baseline is its top plus its `ascent', which is the
			-- placement rule SHAPED_LINE documents.
		require
			context_valid: a_context.is_valid
		local
			l_top: REAL_64
		do
			prepare_context (a_context)
			l_top := a_y
			across a_layout.lines as l loop
				draw_line (a_context, l, a_x, l_top + l.ascent)
				l_top := l_top + l.height
			end
		ensure
			context_survives: a_context.is_valid
			every_run_accounted: painted_runs + skipped_runs
				= old painted_runs + old skipped_runs + run_count (a_layout)
			painted_only_grows: painted_runs >= old painted_runs
			skipped_only_grows: skipped_runs >= old skipped_runs
		end

	draw_line (a_context: CAIRO_CONTEXT; a_line: SHAPED_LINE; a_x, a_baseline_y: REAL_64)
			-- Paint `a_line''s runs in VISUAL order from `a_x', on the
			-- baseline `a_baseline_y', advancing a pen by each run's own
			-- advance width. The pen is the only arithmetic here: the runs
			-- arrive already reordered (UAX #9 L2) and already positioned.
		require
			context_valid: a_context.is_valid
		local
			l_pen: REAL_64
		do
			prepare_context (a_context)
			l_pen := a_x
			across a_line.runs as r loop
				if attached {GLYPH_RUN} r as al_glyphs then
					draw_glyph_run (a_context, al_glyphs, l_pen, a_baseline_y)
				elseif attached {IMAGE_RUN} r as al_image then
					draw_image_run (a_context, al_image, l_pen, a_baseline_y)
				else
						-- SHAPED_RUN is closed over exactly two heirs by
						-- design (I-002/G3). A third one would be a design
						-- breach, so it degrades rather than raising.
					note_skip ("run is neither GLYPH_RUN nor IMAGE_RUN")
				end
				l_pen := l_pen + r.advance_width
			end
		ensure
			context_survives: a_context.is_valid
			every_run_accounted: painted_runs + skipped_runs
				= old painted_runs + old skipped_runs + a_line.runs.count
			painted_only_grows: painted_runs >= old painted_runs
			skipped_only_grows: skipped_runs >= old skipped_runs
		end

feature -- Commands

	reset_counters
			-- Forget what the last paint did.
		do
			painted_runs := 0
			skipped_runs := 0
			create last_skip_note.make_empty
		ensure
			zeroed: painted_runs = 0 and skipped_runs = 0
			cleared: last_skip_note.is_empty
		end

feature {NONE} -- Implementation

	prepare_context (a_context: CAIRO_CONTEXT)
			-- THE SAME-N WORKAROUND, one line, before any glyph is drawn.
			-- Read the class note before touching this: without an EXPLICIT
			-- antialias mode, cairo's win32 backend renders same-N glyphs at
			-- about 1/32 size and reports no error at all. Subpixel keeps
			-- ClearType, so the fix costs no rendering quality. Idempotent,
			-- so `draw_layout' and `draw_line' may both call it.
		require
			context_valid: a_context.is_valid
		do
			a_context.set_font_antialias (a_context.Antialias_subpixel).do_nothing
		ensure
			context_survives: a_context.is_valid
		end

	draw_glyph_run (a_context: CAIRO_CONTEXT; a_run: GLYPH_RUN; a_pen_x, a_baseline_y: REAL_64)
			-- `a_run''s physical glyph ids through its OWN font's cairo
			-- face, at its OWN pixel size (same-N, DR-009), at absolute
			-- positions pen + the run's own offsets.
		require
			context_valid: a_context.is_valid
		local
			l_font: SHAPING_FONT
			l_face: CAIRO_FONT_FACE
			l_xs, l_ys: ARRAY [REAL_64]
			i, n: INTEGER
		do
			l_font := a_run.font
			if not l_font.is_ready then
					-- No HFONT means no face can exist. A headless layout
					-- (NULL seams) and a disposed registry both land here.
				note_skip ("glyph run's font is not realized - there is no HFONT to build a face from")
			else
				l_face := l_font.cairo_face
				if not l_face.is_valid then
					note_skip ("cairo face unusable, status " + l_face.status.out)
				else
					a_context.set_font_face (l_face).do_nothing
					a_context.set_font_size (a_run.pixel_size.to_double).do_nothing
					n := a_run.glyph_ids.count
					create l_xs.make_filled (0.0, 1, n)
					create l_ys.make_filled (0.0, 1, n)
					from i := 1 until i > n loop
						l_xs [i] := a_pen_x + a_run.x_positions [a_run.x_positions.lower + i - 1]
						l_ys [i] := a_baseline_y + a_run.y_positions [a_run.y_positions.lower + i - 1]
						i := i + 1
					end
						-- An empty run is a lawful no-op, not a cairo error.
					a_context.show_glyphs (a_run.glyph_ids, l_xs, l_ys).do_nothing
					painted_runs := painted_runs + 1
				end
			end
		ensure
			one_run_accounted: painted_runs + skipped_runs
				= old painted_runs + old skipped_runs + 1
			context_survives: a_context.is_valid
		end

	draw_image_run (a_context: CAIRO_CONTEXT; a_run: IMAGE_RUN; a_pen_x, a_baseline_y: REAL_64)
			-- `a_run''s emoji artwork, scaled from the asset's own pixel
			-- size into the run's box and placed with the box's BOTTOM EDGE
			-- ON THE BASELINE. Clipped to the box so a scaled blit can never
			-- ink a neighbouring run.
		require
			context_valid: a_context.is_valid
		local
			l_top, l_scale_x, l_scale_y: REAL_64
		do
			if attached surfaces.surface (a_run.asset_path) as al_surface and then
				(al_surface.width > 0 and al_surface.height > 0)
			then
				l_top := a_baseline_y - a_run.height
				l_scale_x := a_run.width / al_surface.width.to_double
				l_scale_y := a_run.height / al_surface.height.to_double
				a_context.save.do_nothing
				a_context.clip_rectangle (a_pen_x, l_top, a_run.width, a_run.height).do_nothing
				a_context.translate (a_pen_x, l_top).scale (l_scale_x, l_scale_y).do_nothing
				a_context.set_source_surface (al_surface, 0.0, 0.0).paint.do_nothing
				a_context.restore.do_nothing
				painted_runs := painted_runs + 1
			else
					-- DR-006 promises the asset was RESOLVED when the run was
					-- built; a file deleted since, or a decoder that refuses
					-- it, still cannot be allowed to raise (NFR-011).
				note_skip ("no surface for asset " + a_run.asset_key)
			end
		ensure
			one_run_accounted: painted_runs + skipped_runs
				= old painted_runs + old skipped_runs + 1
			context_survives: a_context.is_valid
		end

	note_skip (a_reason: STRING_8)
			-- Count one degraded run and record `a_reason'.
		require
			reason_not_empty: not a_reason.is_empty
		do
			skipped_runs := skipped_runs + 1
			last_skip_note := a_reason.twin
		ensure
			counted: skipped_runs = old skipped_runs + 1
			nothing_painted: painted_runs = old painted_runs
			recorded: last_skip_note.same_string (a_reason)
		end

invariant
	counters_non_negative: painted_runs >= 0 and skipped_runs >= 0

end
