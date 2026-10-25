# Design scan (diff mode), simple_shaping since c63ebf1 (main 0c35497)

Read-only. Nothing compiled or run. Lines are src/pipeline/layout_cache.e unless stated. "Unverified" = needs a run.
Subjects: layout_cache.e, shaped_layout.e, emoji_surface_cache.e, emoji_asset_catalog.e, font_registry.e, bidi_result.e, bidi_resolver.e, glyph_shaper.e, shaped_item.e, null_glyph_shaper.e, simple_shaping.e.

Counts: HIGH 0, MEDIUM 4, LOW 5.

## Stamped LRU, command by command

State: `log_keys/log_stamps` (every use, oldest first), `stamps` (key to latest stamp), `head`. A log entry is live iff `stamps` holds its key at its stamp (352-359).

- put new, room (222-224): `storage.put`, `log_use` appends (key, ++clock), `skip_stale`. If the cache was empty, head was count+1 and now names the new, live entry; otherwise head stays on the oldest live. OK.
- put new, full (219-221): `evict_oldest` takes `log_keys.i_th (head)` (live by the previous command's guarantee), removes it from storage, digests and stamps, head+1, `skip_stale`. Then `log_use`. Capacity 1: storage empties, head runs to count+1, the new entry is appended at that index and is live. OK.
- put existing / touch / item_verified hit: a fresh stamp is appended. If the key was at head, its old entry is now stale and `skip_stale` (inside `log_use`) moves head on. If not at head, head stays live. OK.
- A stale duplicate cannot come alive: a key re-put after eviction gets a larger stamp, so its old entries never match.
- set_capacity (244-248): growth evicts nothing and compacts; shrink evicts until count <= capacity (storage non-empty inside the loop), then compacts. Log = live entries afterwards. OK.
- wipe (261-267): all five collections emptied, head 1 = count+1. `clock` is not reset; harmless.
- compact (385-406): walks from `head` (every earlier entry is stale, since head is the oldest live), keeps live entries in order, head := 1. Each live key has one live entry, so `only_live` holds. Empty storage gives head 1 = count+1.
- head_in_log (450): evict does head+1 from head <= count; skip_stale stops at count+1. OK.

Answers
- Head always on a live entry after every command? Yes, or count+1 when empty. Every command that can stale or remove the head entry (`log_use`, `evict_oldest`) ends with `skip_stale`; `compact` and `wipe` reset it.
- newest_key / oldest_key stale or evicted? `newest_key` is `log_keys.last`: the last appended entry is the latest use of its key, and a key is evicted only as the oldest, which with the newest being that key means the only live entry, so storage is empty and the answer is Void (135). `oldest_key` is `log_keys.i_th (head)`, live as above. Neither returns an evicted key. Between `evict_oldest` and `log_use` inside `put`, `newest_key` can be momentarily stale, but only non-exported code runs there.
- log_bounded (451) after every exported command, including growth? `log_use` appends one and compacts above 2*cap+16, leaving at most cap. `set_capacity` compacts last, after `capacity` is assigned (244). `wipe` empties. Yes.
- keys_model (311-326): live entries from head in log order is LRU order, oldest first; `same_count` holds. Its `set_capacity` clause `keys_model |=| (old keys_model).tail (old count - count + 1)` is right for shrink and growth (tail 1 = all).
- compact often enough, never during iteration? It fires above 2*cap+16 and leaves at most cap, so at least cap+16 uses lie between compactions: O(1) amortized. The only loops over the log (`keys_model`, `compact`, `skip_stale`) call no mutator.
- Duplicate key in the live set? No: `storage.has` gates `put`, `stamps` is a map, and `stamps_aligned` ties its count to storage.
- New put/evict/touch/item_verified postconditions: re-read, all true as written (`lru_victim_gone` is vacuous when the key existed; `room_keeps_the_oldest` holds because an append never moves head).

Findings (LRU)
- LOW, 364: `clock` is a 32-bit INTEGER; at 1,000 uses a frame and 60 Hz it wraps in about 10 hours. Only equality is compared and the log holds just the last ~2*capacity uses, so a stale entry cannot share a stamp with a live one: harmless, but say so in the note. Unverified (no wrap test).
- LOW, 213-216: `to_string_8` on a STRING_8 returns the same object, so storage, digests, stamps and the log all hold the caller's key object. A caller that reuses or mutates its key buffer now corrupts four structures at once (two before). Check the facade builds a fresh key per call (unverified), or `twin` in the miss branch of `put`.
- LOW: no test covers the stamped LRU itself; the new lib_tests are cost tests (test_long_paragraph_hit_cost_follows_its_length, test_first_shaping_cost_follows_the_text, test_line_offset_cost_does_not_grow_with_the_layout, test_emoji_surface_hit_cost_does_not_grow). Add: capacity 3, touch the head past 2*cap+16 uses so compaction fires, assert `keys_model` and eviction order against a plain list; capacity 1; set_capacity growth then shrink.

## O(1) postconditions

- emoji_surface_cache.surface (emoji_surface_cache.e:116-123): `write_once` is true if a hit returns the held surface and nothing replaces it; `memo_only_grows`, `growth_bounded`, `miss_memoizes_nothing` over `count` are true when a failed decode stores nothing. The dropped invariant `only_paintable_surfaces_held` is now covered by `decoded_is_valid` only while `surface` is the sole inserter. LOW.
- emoji_asset_catalog.has_asset (emoji_asset_catalog.e:161-167): `under_the_directory` checks only this key (the path written this call); the dropped invariant covered all entries, true while `has_asset` is the only way in. `verdict_write_once` is true when a positive verdict is never overwritten. MEDIUM: the contract says a MISSING asset is never memoized (`negative_no_memo`), so every call for a missing emoji re-probes the disk (`file_probe.exists`); in a grid of emoji rows that is a probe per cluster per facade-cache miss. Not a contract fault; check the facade cache bounds it (unverified).
- font_registry.font (font_registry.e:104-111): `same_holder_again`, `idempotent`, `growth_bounded` true if the body returns the existing entry. `fonts_are_owned` rests on `owned` of the sole inserter. OK.
- SHAPED_LAYOUT (shaped_layout.e:57-59; invariant 202-212): `coverage_holds`, `height_is_sum`, `same_n_closed` moved to `make`'s postcondition. True at creation (they held at the end of `make` before, because the invariant ran there). Loss: `lines` is an exported ARRAYED_LIST kept by reference (`lines_kept: lines = a_lines`, line 54), so the creator or any client can still mutate it, and the invariant used to catch that on the next call. LOW: document "never mutate" or export a read-only view.
- bidi_result `levels_copied` (38-42) compares arrays: true. `all_levels_bounded`, `clusters_non_decreasing/increasing`, `all_advances_non_negative` are O(n) over the item's own arrays and say what the model clauses said. bidi_resolver, glyph_shaper and null_glyph_shaper postconditions are equivalent counts.
- MEDIUM, simple_shaping.e:249-250: `layout` (212-218) now guards `coverage` and `width_respected` with `not old is_cached`, so a hit is not re-walked. The sibling `layout_default` (246-250) keeps `coverage: Result.covers_all_characters` and `width_respected` unguarded, and the styles path has the same: each call walks every line and run, O(layout) per call on a per-frame path for any consumer using it (Strong's numbers, interlinear). Make them the same guarded form.

## policy_revision

Bumped in: set_default_fonts (simple_shaping.e:397), set_asset_directory (418), forget_font_answers (615, reached through load_font_file at 599), clear_cache (626). Not bumped: `set_cache_capacity` (changes no layout answer; correct) and the creation. All four paths that wipe the cache or change fonts are covered.
- MEDIUM, 579-599: `load_font_file` is process-wide (`registry.load_private_font_file`) but only THIS facade's revision moves. Another facade's clients keep stale layouts and stale existence verdicts. The comment says so (593-594); simple_widgets makes one facade per SW_SHAPING, so two windows hit it. A process-wide revision (a once counter added to each facade's) closes it.
- MEDIUM, 396-398: `set_default_fonts` bumps the revision even when the new list equals the old, so a client memo is dropped for nothing (the cache is kept by the `cache_untouched_when_equal` clause). Wasteful, not wrong; guard with `not (default_fonts ~ a_fonts)`.
- LOW: `forget_font_answers` bumps although its comment (606-612) says cached layouts stay valid; a conservative signal, consistent with "can make ... differ".
