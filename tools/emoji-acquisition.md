# Emoji acquisition record (R4 / DR-013)

**Acquired 2026-09-02** for Phase 4, Task 6, on branch `phase4/assets`.
This is the pin. `src/emoji/generated/emoji_data_tables.e` carries the same
facts in its class note, and `EMOJI_ASSET_CATALOG`'s invariant
`tables_and_assets_pinned_together` compares the version string at run time -
so assets and tables cannot drift apart silently (DR-013, RISK-005).

**Refreshing later is one commit:** swap the assets, re-run
`python tools/generate_emoji_tables.py`, update this file, commit together.
`python tools/generate_emoji_tables.py --check` fails (exit 1) when the
generated class is stale with respect to the pinned inputs.

---

## 1. The artwork

| Field | Value |
| --- | --- |
| Project | googlefonts/noto-emoji |
| Tag | `v2.051` |
| Release title | **Unicode 17.0 update mk1** (published 2025-09-15T22:43:24Z) |
| Tag commit | `8998f5dd683424a73e2314a8c1f1e359c19e8742` (2025-09-12T20:07:20Z) |
| Archive URL | `https://github.com/googlefonts/noto-emoji/archive/refs/tags/v2.051.tar.gz` |
| Archive sha256 | `04f3d1e5605edebebac00a7a0becb390a4a3ead015066905b27935b30c18e745` |
| Archive size | 210,291,735 bytes |
| Extracted | `png/128/` only, into `assets/noto-emoji/png/128/` |
| Files kept | **3,768 PNG** (0 non-PNG) |
| Bytes kept | **21,196,457** (20.21 MiB); largest single file 19,584 bytes |

`v2.051` is the newest tag in the repository (checked with
`gh api repos/googlefonts/noto-emoji/tags`), and it carries a populated
`png/128` set. The archive is NOT committed; only the extracted PNGs are.

GitHub source archives are not guaranteed byte-stable across server changes,
so the sha256 above records what was actually downloaded on the date above.
The authoritative pin for anyone auditing this tree is the committed PNG bytes.

### Where the "Unicode emoji version" claim comes from

The release does **not** ship any UCD data file, and its `README.md` names no
version, so the citation is the **GitHub release title for the tag**:

    gh api repos/googlefonts/noto-emoji/releases/tags/v2.051 --jq '.name'
    -> "Unicode 17.0 update mk1"

Corroborated on disk: the extracted set contains the Emoji-17.0 additions, e.g.
`emoji_u1fa88.png` (U+1FA88), `emoji_u1fa89.png` (U+1FA89), `emoji_u1fa8a.png`.

So the DR-013 constant emitted by the generator is **`"17.0"`**, and the
matching Unicode data files below are the Emoji 17.0 files.

"mk1" is upstream's own wording for a first pass at the 17.0 artwork: coverage
of Emoji 17.0 may be incomplete. That is not a defect here - the FR-007 ladder
degrades an unresolvable sequence to per-codepoint images and then to PLAIN
with a `Note_emoji_degraded` - but it is recorded so nobody reads a missing
image as a bug in the segmenter.

### Coverage facts worth knowing (verified on the extracted set)

- `emoji_u1f916.png`, `emoji_u00a9.png`, `emoji_u00ae.png`,
  `emoji_u0023_20e3.png` all EXIST; `emoji_ua9.png`, `emoji_uae.png` and
  `emoji_u23_20e3.png` DO NOT. The ISSUE-5 four-hex-digit minimum padding is
  therefore the real Noto scheme, not a guess, and
  `EMOJI_ASSET_CATALOG.lower_hex`'s `noto_minimum_padding` is right.
- All twelve keycaps are present with padded bases
  (`emoji_u0023_20e3`, `emoji_u002a_20e3`, `emoji_u0030_20e3` ..
  `emoji_u0039_20e3`).
- ZWJ families and skin-tone sequences have full-sequence images
  (`emoji_u1f469_200d_1f4bb.png`, `emoji_u1f469_1f3fd.png`,
  `emoji_u1f468_200d_1f469_200d_1f466.png`).
- **Flag PAIRS have no PNG in this release.** The individual regional-indicator
  letters are present (`emoji_u1f1e6.png` .. `emoji_u1f1ff.png`, 41 files
  matching `1f1`), but the waved flags live upstream only as SVG under
  `third_party/region-flags/waved-svg/`. So `emoji_u1f1fa_1f1f8.png` does not
  exist and a flag sequence lands on rung 2 of the FR-007 ladder: two letter
  tiles, which is the Unicode-recommended fallback rendering.

### License - READ THIS BEFORE SHIPPING

The Phase-0/1 intent (G3) and Task 6's acceptance line both say "Apache-2.0".
**At tag `v2.051` that is no longer unambiguous**, and the discrepancy is
upstream's, not ours:

- the repository's root `LICENSE` at `v2.051` is the **SIL OFL 1.1**
  (sha256 `500bb1ccf43df7bbb522112f9133a52b16e1c35e809632f5d8609b179152de5b`),
  changed by upstream commit `254596e5` "Update LICENSE to OFL" on 2024-07-29;
- the `README.md` at that same tag still reads *"Tools and most image resources
  are under the Apache license, version 2.0"* and links `./LICENSE` - the file
  that is now OFL.

`LICENSE-ASSETS.md` at the repository root therefore ships the FULL TEXT OF
BOTH licenses plus the upstream copyright notice, which satisfies the stricter
reading. Neither license imposes an attribution-UI requirement, so NFR-009/AC-9
("a license file beside the exe") is met.

**Open for Larry:** if a single unambiguous license is wanted, re-pin to tag
`v2.042` ("Unicode 15.1, take 3", 2023-11-30), whose root `LICENSE` **is**
Apache-2.0 and whose README is coherent - at the cost of Unicode emoji 15.1
instead of 17.0, and of re-pinning the data files to
`https://www.unicode.org/Public/emoji/15.1/`. This is a data decision, so it
is named here rather than taken.

---

## 2. The Unicode data files (inputs to Task 7)

Committed under `tools/`, byte-exact as downloaded (`.gitattributes` marks them
`-text` so git never rewrites their line endings and the checksums stay true).

| File | Version | Bytes | sha256 | Source URL |
| --- | --- | --- | --- | --- |
| `tools/emoji-test.txt` | 17.0 (dated 2025-08-04) | 669,326 | `1d8a944f88d7952f7ef7c5167fef3c67995bcae24543949710231b03a201acda` | `https://www.unicode.org/Public/emoji/latest/emoji-test.txt` |
| `tools/emoji-zwj-sequences.txt` | 17.0 (dated 2025-01-08) | 277,215 | `5b25441daed2322b068c5e70cda522946a4f0274df864445a1965a92e5fc5cad` | `https://www.unicode.org/Public/emoji/latest/emoji-zwj-sequences.txt` |
| `tools/emoji-data.txt` | 17.0 (dated 2025-07-25) | 107,324 | `2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b` | `https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt` |

`emoji-data.txt` is the Extended_Pictographic source; the other two are the RGI
set. All three state `# Version: 17.0` in their own headers, and the generator
REFUSES to run if they ever disagree with each other.

**Why `latest/` and not `17.0/`:** `https://www.unicode.org/Public/emoji/17.0/`
returns 404 - Unicode has not created a numbered directory for Emoji 17.0, and
`Public/17.0.0/ucd/emoji/` holds only `emoji-data.txt` and
`emoji-variation-sequences.txt`. On 2026-09-02, `Public/emoji/latest/` served
Version 17.0, which is what the checksums above cover. Because `latest/` moves,
the checksums plus the committed files - not the URL - are the pin.

---

## 3. What the generator produced

`python tools/generate_emoji_tables.py` ->
`src/emoji/generated/emoji_data_tables.e`

| Quantity | Value |
| --- | --- |
| `unicode_version` | `"17.0"` |
| Extended_Pictographic | 156 merged ranges (from 451 raw entries) |
| RGI sequences | 3,944 (emoji-test.txt `fully-qualified`, unioned with all 1,614 emoji-zwj-sequences.txt entries - the ZWJ file adds nothing new, which is itself a cross-check) |
| `Max_rgi_sequence_length` | 9 (canonical, VS16 removed) |
| `Max_rgi_prefix_length` | 10 (as written, VS16 included) |
| Compiled-in blobs | 1 range blob + 16 sequence blobs |

Everything is compiled into the class (D-S08): no UCD file is opened at run
time, and the library ships no data file.
