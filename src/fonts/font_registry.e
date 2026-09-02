note
	description: "[
		Creates, caches, and (Phase 4) disposes SHAPING_FONTs for ONE facade
		on ONE processor (DR-012/OQ-1). Owns native lifetime: HFONT/HDC and
		backend handles live and die here, never in value classes (04).

		The ownership contract is statable and stated: every cached font's
		back-pointer names THIS registry (invariant), fixed at birth
		(SHAPING_FONT.make's owner_registered) - a font cannot lawfully
		migrate between processors.

		R1: Phase 4's realization step is where the existence probe runs;
		a missing family falls back to the effective list's next entry with
		one Note_family_missing.

		PHASE 4 TASK 2 - REALIZATION ON FIRST USE. `font' realizes the
		identity it just created (D-S03's chain, in SHAPING_FONT.realize) and
		`dispose_all' releases every handle before dropping the identities.
		The registry owns the ONE GDI32_API and the ONE DWRITE_API this
		processor's fonts realize through, so the native surfaces cannot
		multiply behind the confinement boundary.

		THE FACTORY OUTLIVES `dispose_all' ON PURPOSE. `dispose_all' releases
		faces, HFONTs and DCs but does NOT call DWRITE_API.close: the shim's
		factory, GdiInterop and TextAnalyzer are process-wide statics
		(Clib/simple_shaping_dwrite.h), and closing them would FreeLibrary
		dwrite.dll underneath any OTHER registry's live IDWriteFontFaces.
		`open' is idempotent, so a registry that is reused after
		`dispose_all' simply realizes again.

		R1 EXISTENCE PROBE (`family_exists'): a TRANSIENT realization -
		CreateFontIndirectW, a memory DC, SelectObject, GetTextFaceW, then
		every handle released before returning - whose verdict is memoized
		per family. Transient because the probe must not seed the registry
		with an identity nobody asked to shape with, and memoized because R5
		makes the facade ask repeatedly, inside assertion evaluation. The
		memo is a write-once benign side effect on a query - the same
		declared CQS exception EMOJI_ASSET_CATALOG.has_asset takes.
	]"
	author: "Larry Rix"

class
	FONT_REGISTRY

create
	make

feature {NONE} -- Initialization

	make
			-- Empty registry.
		do
			create fonts.make (8)
			create gdi.make
			create dwrite.make
			create family_verdicts.make (8)
		ensure
			registry_empty: fonts_model.is_empty
		end

feature -- Access

	count: INTEGER
			-- Realized identities held.
		do
			Result := fonts.count
		ensure
			non_negative: Result >= 0
		end

	font (a_family: READABLE_STRING_32; a_weight: INTEGER; a_italic: BOOLEAN;
			a_pixel_size: INTEGER): SHAPING_FONT
			-- The one SHAPING_FONT for this identity - created on first use,
			-- cached thereafter (same object every call; D-S03 demands one
			-- holder per identity so SCRIPT-level caches and faces never split).
			--
			-- TASK 2 (Phase 4): also REALIZED on first use, so the identity a
			-- client receives has already been offered to the machine. The
			-- realization is a benign memo on a query (declared CQS
			-- exception, 05) and it is attempted exactly ONCE per holder -
			-- a machine that refuses a family is not re-asked on every call.
		require
			family_not_empty: not a_family.is_empty
			weight_range: a_weight >= 1 and a_weight <= 1000
			size_positive: a_pixel_size > 0
		local
			l_key: STRING_32
		do
			l_key := registry_key (a_family, a_weight, a_italic, a_pixel_size)
			if attached fonts.item (l_key) as al_font then
				Result := al_font
			else
				create Result.make (a_family, a_weight, a_italic, a_pixel_size, Current)
				fonts.put (Result, l_key)
			end
			if not Result.is_realization_attempted then
				Result.realize (gdi, dwrite)
			end
		ensure
			identity: Result.family.same_string_general (a_family)
				and Result.weight = a_weight and Result.is_italic = a_italic
				and Result.pixel_size = a_pixel_size
			owned: Result.registry = Current
			registered: fonts_model.domain [registry_key (a_family, a_weight, a_italic, a_pixel_size)]
			cached_result: fonts_model [registry_key (a_family, a_weight, a_italic, a_pixel_size)] = Result
			model_exact: fonts_model |=| (old fonts_model).updated (
				registry_key (a_family, a_weight, a_italic, a_pixel_size), Result)
			growth_bounded: fonts_model.count <= old fonts_model.count + 1
			idempotent: (old fonts_model.domain [registry_key (a_family, a_weight, a_italic, a_pixel_size)])
				implies fonts_model.count = old fonts_model.count
			realized_on_first_use: Result.is_realization_attempted
				-- [ADDED Phase 4 Task 2 - REPORTED contract change, gate
				-- decision 2.] The Phase-1 body handed back an untouched
				-- identity; this clause makes "the registry realizes"
				-- STATABLE. It deliberately does NOT say `Result.is_ready':
				-- realization is a native operation that a machine may
				-- refuse, and promising its success would turn a GDI failure
				-- into a postcondition violation escaping `layout' - the one
				-- thing NFR-011 forbids and the reason GDI32_API returns
				-- default_pointer instead of raising. Callers read
				-- `is_ready' and degrade; this clause guarantees the answer
				-- is the machine's, not a missing call.
		end

	registry_key (a_family: READABLE_STRING_32; a_weight: INTEGER; a_italic: BOOLEAN;
			a_pixel_size: INTEGER): STRING_32
			-- Deterministic identity key (case-folded family | weight |
			-- italic | size).
		require
			family_not_empty: not a_family.is_empty
		do
			create Result.make (a_family.count + 12)
			Result.append_string_general (a_family.as_lower)
			Result.append_character ('|')
			Result.append_string_general (a_weight.out)
			Result.append_character ('|')
			if a_italic then
				Result.append_character ('1')
			else
				Result.append_character ('0')
			end
			Result.append_character ('|')
			Result.append_string_general (a_pixel_size.out)
		ensure
			never_empty: not Result.is_empty
		end

	family_exists (a_family: READABLE_STRING_32): BOOLEAN
			-- [ADDED Phase 4 Task 2] R1's EXISTENCE PROBE: will GDI realize
			-- `a_family' as ITSELF? A transient realization asks the machine
			-- and GetTextFaceW answers; every handle it created is released
			-- before this returns, so probing a policy costs no lasting
			-- handles. The verdict is memoized per family (case-folded) for
			-- the registry's lifetime: R5 has the facade asking this inside
			-- assertion evaluation, which must be cheap and deterministic.
		require
			family_not_empty: not a_family.is_empty
		local
			l_key: STRING_32
		do
			l_key := a_family.as_string_32.as_lower
			if family_verdicts.has (l_key) then
				Result := family_verdicts.item (l_key)
			else
				Result := probe_family (a_family)
				family_verdicts.put (Result, l_key)
			end
		ensure
			memoized: family_verdicts.has (a_family.as_string_32.as_lower)
			stable: Result = family_verdicts.item (a_family.as_string_32.as_lower)
		end

feature -- Commands

	dispose_all
			-- Release every font: IDWriteFontFace Release, restore the DC's
			-- original font, DeleteObject (HFONT), DeleteDC - in that order,
			-- inside SHAPING_FONT.dispose - BEFORE the identities are
			-- dropped, because dropping them first would strand every handle
			-- for the life of the process.
			--
			-- The memoized existence verdicts SURVIVE: they are facts about
			-- the machine, not about the fonts held.
		do
			across fonts as f loop
				f.dispose (gdi, dwrite)
			end
			fonts.wipe_out
		ensure
			emptied: fonts_model.is_empty
			count_zero: count = 0
		end

feature -- Model queries (simple_mml)

	fonts_model: MML_MAP [STRING_32, SHAPING_FONT]
			-- Identity key -> font as a mathematical map.
		local
			l_keys: ARRAY [STRING_32]
			i: INTEGER
		do
			create Result
			l_keys := fonts.current_keys
			from i := l_keys.lower until i > l_keys.upper loop
				Result := Result.updated (l_keys [i], fonts.definite_item (l_keys [i]))
				i := i + 1
			end
		end

feature {NONE} -- Implementation

	fonts: HASH_TABLE [SHAPING_FONT, STRING_32]
			-- Identity key -> the one holder.

	gdi: GDI32_API
			-- [ADDED Phase 4 Task 2] The ONE GDI surface this processor's
			-- fonts realize through.

	dwrite: DWRITE_API
			-- [ADDED Phase 4 Task 2] The ONE DirectWrite surface faces come
			-- from. Opened lazily at the first realization that needs it and
			-- deliberately never closed here (see the class note).

	family_verdicts: HASH_TABLE [BOOLEAN, STRING_32]
			-- [ADDED Phase 4 Task 2] Case-folded family -> R1 existence
			-- verdict; write-once per family, never invalidated (font
			-- installation mid-process is out of scope, A-C05).

	Probe_pixel_size: INTEGER = 16
			-- [ADDED Phase 4 Task 2] The size the existence probe realizes
			-- at. Existence is size-independent - GDI substitutes on the
			-- FAMILY - so one fixed size keeps the verdict deterministic and
			-- shared across every layout size.

	probe_family (a_family: READABLE_STRING_32): BOOLEAN
			-- [ADDED Phase 4 Task 2] Realize `a_family' transiently and ask
			-- GetTextFaceW what came back. False when GDI substituted, and
			-- False when GDI could not realize anything at all - a machine
			-- that cannot make the font is a machine that does not have it,
			-- which is exactly the answer R1 wants.
		require
			family_not_empty: not a_family.is_empty
		local
			l_font, l_dc, l_previous: POINTER
		do
			l_font := gdi.create_font (a_family, {SHAPING_FONT}.Weight_regular, False, Probe_pixel_size)
			if l_font /= default_pointer then
				l_dc := gdi.create_memory_dc
				if l_dc /= default_pointer then
					l_previous := gdi.select_font (l_dc, l_font)
					Result := gdi.realized_face_name (l_dc).is_case_insensitive_equal (a_family)
					if l_previous /= default_pointer then
						l_previous := gdi.select_font (l_dc, l_previous)
					end
					if gdi.delete_dc (l_dc) then
					end
				end
				if gdi.delete_handle (l_font) then
				end
			end
		end

invariant
	fonts_are_owned: across fonts as f all f.registry = Current end
	model_count_consistent: fonts_model.count = count

end
