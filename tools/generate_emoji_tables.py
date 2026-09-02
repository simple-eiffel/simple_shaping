#!/usr/bin/env python3
"""
generate_emoji_tables.py - build-time generator for EMOJI_DATA_TABLES (D-S08).

Reads the PINNED Unicode emoji data files that live beside this script and
REGENERATES src/emoji/generated/emoji_data_tables.e with:

  * `unicode_version'          - the pinned Unicode emoji version (DR-013);
  * `is_extended_pictographic' - the real UTS #51 Extended_Pictographic
                                 property, as merged ranges COMPILED INTO the
                                 class (no runtime parsing of UCD files);
  * the additive RGI-sequence lookups the EMOJI_SEGMENTER longest match needs
    (Phase 3 gate decision 4: the generator EMITS these queries);
  * every hand-held structural predicate reproduced BYTE-FOR-BYTE, contracts
    included - Phase 4 law: contracts are frozen.

Inputs (pinned; see tools/emoji-acquisition.md for the R4 record):
  emoji-data.txt           Extended_Pictographic ranges
  emoji-test.txt           the RGI set (status `fully-qualified')
  emoji-zwj-sequences.txt  the RGI ZWJ subset (unioned in)

Usage:  python tools/generate_emoji_tables.py [--check]

  --check  regenerate into memory and report whether the file on disk is
           already up to date (exit 1 if it is not); writes nothing.

Language note: research/04-DECISIONS.md D-S08 calls for a generator script in
tools/ and mandates no language, so this is Python. It is build-time only: it
never ships in the runnable folder and is never run by the library.
"""

import argparse
import datetime
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_PATH = os.path.join(ROOT, "src", "emoji", "generated", "emoji_data_tables.e")

# --- R4 acquisition pins -----------------------------------------------------
# These MIRROR tools/emoji-acquisition.md. Change both together (DR-013).
NOTO_TAG = "v2.051"
NOTO_RELEASE_TITLE = "Unicode 17.0 update mk1"
NOTO_ARCHIVE_URL = (
    "https://github.com/googlefonts/noto-emoji/archive/refs/tags/v2.051.tar.gz")
NOTO_ARCHIVE_SHA256 = (
    "04f3d1e5605edebebac00a7a0becb390a4a3ead015066905b27935b30c18e745")

INPUT_FILES = ("emoji-data.txt", "emoji-test.txt", "emoji-zwj-sequences.txt")

VS16 = 0xFE0F
TAB = "\t"
MAX_BLOB_LINE = 72
MAX_CHUNK_CHARS = 4000

# --- The FROZEN hand-held block, reproduced byte-for-byte ---------------------
# Copied verbatim from the Phase-1 class (commit 14a2d6d). Every `definition'
# ensure below is a contract: it must never be edited by this generator.
STRUCTURAL_BLOCK = """feature -- Structural facts (hand-held, real)

\tis_vs16 (a_codepoint: NATURAL_32): BOOLEAN
\t\t\t-- U+FE0F VARIATION SELECTOR-16 (emoji presentation)?
\t\tdo
\t\t\tResult := a_codepoint = 0xFE0F
\t\tensure
\t\t\tdefinition: Result = (a_codepoint = 0xFE0F)
\t\tend

\tis_zwj (a_codepoint: NATURAL_32): BOOLEAN
\t\t\t-- U+200D ZERO WIDTH JOINER?
\t\tdo
\t\t\tResult := a_codepoint = 0x200D
\t\tensure
\t\t\tdefinition: Result = (a_codepoint = 0x200D)
\t\tend

\tis_regional_indicator (a_codepoint: NATURAL_32): BOOLEAN
\t\t\t-- U+1F1E6 .. U+1F1FF (flag pair halves)?
\t\tdo
\t\t\tResult := a_codepoint >= 0x1F1E6 and a_codepoint <= 0x1F1FF
\t\tensure
\t\t\tdefinition: Result = (a_codepoint >= 0x1F1E6 and a_codepoint <= 0x1F1FF)
\t\tend

\tis_emoji_modifier (a_codepoint: NATURAL_32): BOOLEAN
\t\t\t-- U+1F3FB .. U+1F3FF (skin tones)?
\t\tdo
\t\t\tResult := a_codepoint >= 0x1F3FB and a_codepoint <= 0x1F3FF
\t\tensure
\t\t\tdefinition: Result = (a_codepoint >= 0x1F3FB and a_codepoint <= 0x1F3FF)
\t\tend

\tis_combining_enclosing_keycap (a_codepoint: NATURAL_32): BOOLEAN
\t\t\t-- U+20E3 (keycap sequences)?
\t\tdo
\t\t\tResult := a_codepoint = 0x20E3
\t\tensure
\t\t\tdefinition: Result = (a_codepoint = 0x20E3)
\t\tend
"""

COMPOSITION_BLOCK = """feature -- Composition

\tis_emoji_starter (a_codepoint: NATURAL_32): BOOLEAN
\t\t\t-- Can `a_codepoint' START an emoji sequence (segmentation
\t\t\t-- trigger)? Inert joiners/selectors/modifiers without a base are
\t\t\t-- NOT starters.
\t\tdo
\t\t\tResult := is_extended_pictographic (a_codepoint)
\t\t\t\tor is_regional_indicator (a_codepoint)
\t\tensure
\t\t\tdefinition: Result = (is_extended_pictographic (a_codepoint)
\t\t\t\tor is_regional_indicator (a_codepoint))
\t\tend
"""


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 16), b""):
            digest.update(block)
    return digest.hexdigest()


def file_version(path):
    """The `# Version:' line every UTS #51 data file carries."""
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("# Version:"):
                return line.split(":", 1)[1].strip()
    raise SystemExit("no '# Version:' header in " + path)


def data_lines(path):
    """Yield the field list of every non-comment, non-blank data line."""
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.split("#", 1)[0].strip()
            if line:
                yield [part.strip() for part in line.split(";")]


def extended_pictographic_ranges(path):
    """Sorted, merged (lo, hi) ranges of Extended_Pictographic."""
    ranges = []
    for fields in data_lines(path):
        if len(fields) < 2 or fields[1] != "Extended_Pictographic":
            continue
        field = fields[0]
        if ".." in field:
            low, high = field.split("..")
            ranges.append((int(low, 16), int(high, 16)))
        else:
            value = int(field, 16)
            ranges.append((value, value))
    ranges.sort()
    merged = []
    for low, high in ranges:
        if merged and low <= merged[-1][1] + 1:
            merged[-1][1] = max(merged[-1][1], high)
        else:
            merged.append([low, high])
    return [(low, high) for low, high in merged]


def canonical(codes):
    """The catalog's key form: VS16 is not significant."""
    return tuple(code for code in codes if code != VS16)


def rgi_sequences(test_path, zwj_path):
    """
    The RGI set: emoji-test.txt `fully-qualified' entries, unioned with
    emoji-zwj-sequences.txt. Stored in CANONICAL (VS16-free) form so that
    every lawful spelling of a sequence - fully-qualified, minimally-qualified
    or unqualified - answers the same, and so that the key matches
    EMOJI_ASSET_CATALOG.asset_key one for one.
    """
    fully_qualified = set()
    max_raw = 0
    for fields in data_lines(test_path):
        if len(fields) < 2:
            continue
        codes = [int(code, 16) for code in fields[0].split()]
        max_raw = max(max_raw, len(codes))
        if fields[1] == "fully-qualified":
            fully_qualified.add(canonical(codes))
    zwj = set()
    for fields in data_lines(zwj_path):
        if len(fields) < 2 or ".." in fields[0]:
            continue
        codes = [int(code, 16) for code in fields[0].split()]
        max_raw = max(max_raw, len(codes))
        zwj.add(canonical(codes))
    sequences = sorted(item for item in (fully_qualified | zwj) if item)
    return sequences, max_raw


def wrap_tokens(tokens, width=MAX_BLOB_LINE):
    lines, current = [], ""
    for token in tokens:
        if current and len(current) + 1 + len(token) > width:
            lines.append(current)
            current = token
        else:
            current = token if not current else current + " " + token
    if current:
        lines.append(current)
    return lines


def verbatim(tokens, indent):
    """An Eiffel left-aligned verbatim string constant holding `tokens'."""
    pad = TAB * indent
    body = "\n".join(pad + line for line in wrap_tokens(tokens))
    return '"[\n' + body + "\n" + pad + ']"'


def chunk(tokens, limit=MAX_CHUNK_CHARS):
    out, current, size = [], [], 0
    for token in tokens:
        if current and size + len(token) + 1 > limit:
            out.append(current)
            current, size = [], 0
        current.append(token)
        size += len(token) + 1
    if current:
        out.append(current)
    return out


def build(inputs):
    data_path = os.path.join(HERE, "emoji-data.txt")
    test_path = os.path.join(HERE, "emoji-test.txt")
    zwj_path = os.path.join(HERE, "emoji-zwj-sequences.txt")

    versions = {name: file_version(os.path.join(HERE, name))
                for name in INPUT_FILES}
    distinct = set(versions.values())
    if len(distinct) != 1:
        raise SystemExit("pinned data files disagree on version: %r" % versions)
    version = distinct.pop()

    ranges = extended_pictographic_ranges(data_path)
    sequences, max_raw = rgi_sequences(test_path, zwj_path)
    max_canonical = max(len(item) for item in sequences)

    range_tokens = []
    for low, high in ranges:
        range_tokens.append("%x" % low)
        range_tokens.append("%x" % high)
    sequence_tokens = ["_".join("%x" % code for code in item)
                       for item in sequences]
    chunks = chunk(sequence_tokens)

    today = datetime.date.today().isoformat()
    lines = []
    add = lines.append

    add("note")
    add(TAB + 'description: "[')
    add(TAB * 2 + "Pinned UTS #51 emoji data (D-S08). GENERATED FILE - DO NOT EDIT BY")
    add(TAB * 2 + "HAND: re-run tools/generate_emoji_tables.py and commit the result")
    add(TAB * 2 + "TOGETHER WITH the assets it matches (DR-013 / RISK-005: tables and")
    add(TAB * 2 + "assets move in lockstep, one commit).")
    add("")
    add(TAB * 2 + "`unicode_version' is the Unicode emoji version of the acquired Noto")
    add(TAB * 2 + "Emoji release (R4); EMOJI_ASSET_CATALOG's invariant")
    add(TAB * 2 + "`tables_and_assets_pinned_together' compares it with the catalog's")
    add(TAB * 2 + "`expected_unicode_version', so the two cannot drift apart silently.")
    add("")
    add(TAB * 2 + "STRUCTURAL FACTS (fixed codepoints and ranges - VS16, ZWJ, regional")
    add(TAB * 2 + "indicators, skin-tone modifiers, the keycap combiner) are hand-held")
    add(TAB * 2 + "and reproduced here byte for byte, contracts included.")
    add("")
    add(TAB * 2 + "SET MEMBERSHIP is generated and COMPILED IN - no UCD file is ever")
    add(TAB * 2 + "read at run time (D-S08). `is_extended_pictographic' is a binary")
    add(TAB * 2 + "search over %d merged ranges; the RGI set is %d sequences decoded"
        % (len(ranges), len(sequences)))
    add(TAB * 2 + "once per object from the compiled-in blobs at the bottom.")
    add("")
    add(TAB * 2 + "RGI KEYS ARE CANONICAL: VS16 is dropped before lookup, exactly as")
    add(TAB * 2 + "EMOJI_ASSET_CATALOG.asset_key drops it, so every lawful spelling of")
    add(TAB * 2 + "a sequence - fully-qualified, minimally-qualified or unqualified -")
    add(TAB * 2 + "answers the same and maps to the one asset name. A sequence that is")
    add(TAB * 2 + "NOT RGI (a bare keycap base, a lone ZWJ) is absent from the set, so")
    add(TAB * 2 + "the segmenter's longest match lawfully finds nothing there and the")
    add(TAB * 2 + "FR-007 ladder degrades it.")
    add(TAB + ']"')
    add(TAB + 'generated_by: "tools/generate_emoji_tables.py"')
    add(TAB + 'generated_on: "%s"' % today)
    add(TAB + 'unicode_emoji_version: "%s"' % version)
    add(TAB + 'noto_release: "googlefonts/noto-emoji %s (%s)"'
        % (NOTO_TAG, NOTO_RELEASE_TITLE))
    add(TAB + 'noto_archive_url: "%s"' % NOTO_ARCHIVE_URL)
    add(TAB + 'noto_archive_sha256: "%s"' % NOTO_ARCHIVE_SHA256)
    for name in INPUT_FILES:
        key = name.replace("-", "_").replace(".txt", "")
        add(TAB + 'input_%s: "version %s, sha256 %s"'
            % (key, versions[name], inputs[name]))
    add(TAB + 'acquisition_record: "tools/emoji-acquisition.md"')
    add(TAB + 'author: "tools/generate_emoji_tables.py (generated); '
              'Larry Rix (structural facts)"')
    add("")
    add("class")
    add(TAB + "EMOJI_DATA_TABLES")
    add("")
    add("feature -- Version (DR-013)")
    add("")
    add(TAB + 'unicode_version: STRING_8 = "%s"' % version)
    add(TAB * 3 + "-- The acquired Noto release's Unicode emoji version (R4).")
    add("")
    lines.extend(STRUCTURAL_BLOCK.rstrip("\n").split("\n"))
    add("")
    add("feature -- Generated membership")
    add("")
    add(TAB + "is_extended_pictographic (a_codepoint: NATURAL_32): BOOLEAN")
    add(TAB * 3 + "-- Extended_Pictographic property (UTS #51 emoji-data.txt)?")
    add(TAB * 3 + "-- Binary search over the %d merged, compiled-in ranges;"
        % len(ranges))
    add(TAB * 3 + "-- allocation-free per call, because this runs inside")
    add(TAB * 3 + "-- `is_emoji_starter''s `definition' postcondition.")
    add(TAB * 2 + "local")
    add(TAB * 3 + "l_low, l_high, l_middle: INTEGER")
    add(TAB * 3 + "l_ranges: ARRAYED_LIST [NATURAL_32]")
    add(TAB * 2 + "do")
    add(TAB * 3 + "l_ranges := extended_pictographic_ranges")
    add(TAB * 3 + "l_low := 1")
    add(TAB * 3 + "l_high := l_ranges.count // 2")
    add(TAB * 3 + "from until l_low > l_high or Result loop")
    add(TAB * 4 + "l_middle := (l_low + l_high) // 2")
    add(TAB * 4 + "if a_codepoint < l_ranges [2 * l_middle - 1] then")
    add(TAB * 5 + "l_high := l_middle - 1")
    add(TAB * 4 + "elseif a_codepoint <= l_ranges [2 * l_middle] then")
    add(TAB * 5 + "Result := True")
    add(TAB * 4 + "else")
    add(TAB * 5 + "l_low := l_middle + 1")
    add(TAB * 4 + "end")
    add(TAB * 3 + "end")
    add(TAB * 2 + "end")
    add("")
    lines.extend(COMPOSITION_BLOCK.rstrip("\n").split("\n"))
    add("")
    add("feature -- Generated RGI sequences (Phase 3 gate decision 4: additive)")
    add("")
    add(TAB + "Rgi_sequence_count: INTEGER = %d" % len(sequences))
    add(TAB * 3 + "-- How many RGI sequences the compiled-in set holds.")
    add("")
    add(TAB + "Max_rgi_sequence_length: INTEGER = %d" % max_canonical)
    add(TAB * 3 + "-- Longest RGI sequence in CANONICAL (VS16-free) codepoints.")
    add("")
    add(TAB + "Max_rgi_prefix_length: INTEGER = %d" % max_raw)
    add(TAB * 3 + "-- Longest RGI sequence AS WRITTEN (VS16 included): the bound")
    add(TAB * 3 + "-- on how far `longest_rgi_prefix_length' ever looks ahead.")
    add("")
    add(TAB + "is_rgi_sequence (a_codes: ARRAY [NATURAL_32]): BOOLEAN")
    add(TAB * 3 + "-- Is `a_codes' an RGI emoji sequence (the UTS #51")
    add(TAB * 3 + "-- emoji-test.txt `fully-qualified' set, unioned with")
    add(TAB * 3 + "-- emoji-zwj-sequences.txt)? VS16 is NOT significant:")
    add(TAB * 3 + "-- `a_codes' is canonicalized by `without_vs16' first,")
    add(TAB * 3 + "-- exactly as EMOJI_ASSET_CATALOG.asset_key canonicalizes.")
    add(TAB * 2 + "require")
    add(TAB * 3 + "nonempty: not a_codes.is_empty")
    add(TAB * 2 + "do")
    add(TAB * 3 + "Result := rgi_index.has (rgi_key (a_codes))")
    add(TAB * 2 + "ensure")
    add(TAB * 3 + "canonical_nonempty: Result implies not without_vs16 (a_codes).is_empty")
    add(TAB * 3 + "bounded: Result implies without_vs16 (a_codes).count <= Max_rgi_sequence_length")
    add(TAB * 3 + "vs16_insensitive: Result = rgi_index.has (rgi_key (without_vs16 (a_codes)))")
    add(TAB * 2 + "end")
    add("")
    add(TAB + "longest_rgi_prefix_length (a_text: READABLE_STRING_32; a_start: INTEGER): INTEGER")
    add(TAB * 3 + "-- Length, in characters of `a_text', of the LONGEST RGI")
    add(TAB * 3 + "-- sequence starting at `a_start'; 0 when none starts there.")
    add(TAB * 3 + "-- This is the segmenter's longest match (FR-007 rung 1). It")
    add(TAB * 3 + "-- is deliberately NOT restricted to `is_emoji_starter'")
    add(TAB * 3 + "-- positions: keycap bases ('#', '*', '0'..'9') are")
    add(TAB * 3 + "-- Emoji_Component, not Extended_Pictographic, yet they do")
    add(TAB * 3 + "-- start RGI keycap sequences.")
    add(TAB * 2 + "require")
    add(TAB * 3 + "valid_start: a_start >= 1 and a_start <= a_text.count")
    add(TAB * 2 + "local")
    add(TAB * 3 + "l_length, l_limit: INTEGER")
    add(TAB * 2 + "do")
    add(TAB * 3 + "l_limit := a_text.count - a_start + 1")
    add(TAB * 3 + "if l_limit > Max_rgi_prefix_length then")
    add(TAB * 4 + "l_limit := Max_rgi_prefix_length")
    add(TAB * 3 + "end")
    add(TAB * 3 + "from l_length := l_limit until l_length < 1 or Result > 0 loop")
    add(TAB * 4 + "if rgi_index.has (text_key (a_text, a_start, l_length)) then")
    add(TAB * 5 + "Result := l_length")
    add(TAB * 4 + "end")
    add(TAB * 4 + "l_length := l_length - 1")
    add(TAB * 3 + "end")
    add(TAB * 2 + "ensure")
    add(TAB * 3 + "non_negative: Result >= 0")
    add(TAB * 3 + "within_text: a_start + Result - 1 <= a_text.count")
    add(TAB * 3 + "bounded: Result <= Max_rgi_prefix_length")
    add(TAB * 3 + "match_is_rgi: Result > 0 implies is_rgi_sequence (codepoints_of (a_text, a_start, Result))")
    add(TAB * 2 + "end")
    add("")
    add("feature -- Pure helpers (contract-usable)")
    add("")
    add(TAB + "without_vs16 (a_codes: ARRAY [NATURAL_32]): ARRAY [NATURAL_32]")
    add(TAB * 3 + "-- `a_codes' with every U+FE0F removed: the canonical form")
    add(TAB * 3 + "-- this class and EMOJI_ASSET_CATALOG.asset_key share.")
    add(TAB * 2 + "local")
    add(TAB * 3 + "i, l_next, l_kept: INTEGER")
    add(TAB * 2 + "do")
    add(TAB * 3 + "from i := a_codes.lower until i > a_codes.upper loop")
    add(TAB * 4 + "if not is_vs16 (a_codes [i]) then")
    add(TAB * 5 + "l_kept := l_kept + 1")
    add(TAB * 4 + "end")
    add(TAB * 4 + "i := i + 1")
    add(TAB * 3 + "end")
    add(TAB * 3 + "create Result.make_filled (0, 1, l_kept)")
    add(TAB * 3 + "l_next := 1")
    add(TAB * 3 + "from i := a_codes.lower until i > a_codes.upper loop")
    add(TAB * 4 + "if not is_vs16 (a_codes [i]) then")
    add(TAB * 5 + "Result [l_next] := a_codes [i]")
    add(TAB * 5 + "l_next := l_next + 1")
    add(TAB * 4 + "end")
    add(TAB * 4 + "i := i + 1")
    add(TAB * 3 + "end")
    add(TAB * 2 + "ensure")
    add(TAB * 3 + "lower_is_one: Result.lower = 1")
    add(TAB * 3 + "no_longer: Result.count <= a_codes.count")
    add(TAB * 3 + "no_vs16_left: across Result as c all not is_vs16 (c) end")
    add(TAB * 2 + "end")
    add("")
    add(TAB + "codepoints_of (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): ARRAY [NATURAL_32]")
    add(TAB * 3 + "-- The `a_count' codepoints of `a_text' from `a_start'.")
    add(TAB * 2 + "require")
    add(TAB * 3 + "range_valid: a_start >= 1 and a_count >= 1 and a_start + a_count - 1 <= a_text.count")
    add(TAB * 2 + "local")
    add(TAB * 3 + "i: INTEGER")
    add(TAB * 2 + "do")
    add(TAB * 3 + "create Result.make_filled (0, 1, a_count)")
    add(TAB * 3 + "from i := 1 until i > a_count loop")
    add(TAB * 4 + "Result [i] := a_text.code (a_start + i - 1)")
    add(TAB * 4 + "i := i + 1")
    add(TAB * 3 + "end")
    add(TAB * 2 + "ensure")
    add(TAB * 3 + "lower_is_one: Result.lower = 1")
    add(TAB * 3 + "counted: Result.count = a_count")
    add(TAB * 3 + "codes_copied: across 1 |..| a_count as k all Result [k] = a_text.code (a_start + k - 1) end")
    add(TAB * 2 + "end")
    add("")
    add("feature {NONE} -- Implementation (generated tables)")
    add("")
    add(TAB + "extended_pictographic_ranges: ARRAYED_LIST [NATURAL_32]")
    add(TAB * 3 + "-- The merged Extended_Pictographic ranges, flattened as")
    add(TAB * 3 + "-- lo, hi, lo, hi ..., decoded once per object.")
    add(TAB * 2 + "attribute")
    add(TAB * 3 + "Result := decoded_codepoints (Extended_pictographic_data)")
    add(TAB * 2 + "end")
    add("")
    add(TAB + "rgi_index: HASH_TABLE [BOOLEAN, STRING_32]")
    add(TAB * 3 + "-- Canonical RGI keys, decoded once per object from the")
    add(TAB * 3 + "-- compiled-in blobs (D-S08: no UCD file is read here).")
    add(TAB * 2 + "attribute")
    add(TAB * 3 + "create Result.make (Rgi_sequence_count + Rgi_sequence_count // 2)")
    for index in range(1, len(chunks) + 1):
        add(TAB * 3 + "add_sequences (Result, Rgi_data_%d)" % index)
    add(TAB * 2 + "end")
    add("")
    add(TAB + "rgi_key (a_codes: ARRAY [NATURAL_32]): STRING_32")
    add(TAB * 3 + "-- The canonical lookup key of `a_codes' (VS16 dropped).")
    add(TAB * 2 + "local")
    add(TAB * 3 + "i: INTEGER")
    add(TAB * 2 + "do")
    add(TAB * 3 + "create Result.make (a_codes.count)")
    add(TAB * 3 + "from i := a_codes.lower until i > a_codes.upper loop")
    add(TAB * 4 + "if not is_vs16 (a_codes [i]) then")
    add(TAB * 5 + "Result.append_code (a_codes [i])")
    add(TAB * 4 + "end")
    add(TAB * 4 + "i := i + 1")
    add(TAB * 3 + "end")
    add(TAB * 2 + "end")
    add("")
    add(TAB + "text_key (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): STRING_32")
    add(TAB * 3 + "-- The canonical lookup key of `a_text' [`a_start' ..")
    add(TAB * 3 + "-- `a_start' + `a_count' - 1], built without an intermediate")
    add(TAB * 3 + "-- array (this runs once per candidate length per position).")
    add(TAB * 2 + "require")
    add(TAB * 3 + "range_valid: a_start >= 1 and a_count >= 1 and a_start + a_count - 1 <= a_text.count")
    add(TAB * 2 + "local")
    add(TAB * 3 + "i: INTEGER")
    add(TAB * 3 + "l_code: NATURAL_32")
    add(TAB * 2 + "do")
    add(TAB * 3 + "create Result.make (a_count)")
    add(TAB * 3 + "from i := a_start until i > a_start + a_count - 1 loop")
    add(TAB * 4 + "l_code := a_text.code (i)")
    add(TAB * 4 + "if not is_vs16 (l_code) then")
    add(TAB * 5 + "Result.append_code (l_code)")
    add(TAB * 4 + "end")
    add(TAB * 4 + "i := i + 1")
    add(TAB * 3 + "end")
    add(TAB * 2 + "end")
    add("")
    add(TAB + "add_sequences (a_table: HASH_TABLE [BOOLEAN, STRING_32]; a_data: STRING_8)")
    add(TAB * 3 + "-- Decode one compiled-in blob into `a_table'. A token is")
    add(TAB * 3 + "-- lowercase hex codepoints joined by '_'; any other")
    add(TAB * 3 + "-- character ends the sequence.")
    add(TAB * 2 + "local")
    add(TAB * 3 + "i: INTEGER")
    add(TAB * 3 + "c: CHARACTER_8")
    add(TAB * 3 + "l_value: NATURAL_32")
    add(TAB * 3 + "l_key: STRING_32")
    add(TAB * 3 + "l_in_digits: BOOLEAN")
    add(TAB * 2 + "do")
    add(TAB * 3 + "create l_key.make (Max_rgi_sequence_length)")
    add(TAB * 3 + "from i := 1 until i > a_data.count + 1 loop")
    add(TAB * 4 + "if i > a_data.count then")
    add(TAB * 5 + "c := ' '")
    add(TAB * 4 + "else")
    add(TAB * 5 + "c := a_data [i]")
    add(TAB * 4 + "end")
    add(TAB * 4 + "if is_hex_digit (c) then")
    add(TAB * 5 + "l_value := l_value * 16 + hex_value (c)")
    add(TAB * 5 + "l_in_digits := True")
    add(TAB * 4 + "else")
    add(TAB * 5 + "if l_in_digits then")
    add(TAB * 6 + "l_key.append_code (l_value)")
    add(TAB * 6 + "l_value := 0")
    add(TAB * 6 + "l_in_digits := False")
    add(TAB * 5 + "end")
    add(TAB * 5 + "if c /= '_' and then not l_key.is_empty then")
    add(TAB * 6 + "a_table.force (True, l_key)")
    add(TAB * 6 + "create l_key.make (Max_rgi_sequence_length)")
    add(TAB * 5 + "end")
    add(TAB * 4 + "end")
    add(TAB * 4 + "i := i + 1")
    add(TAB * 3 + "end")
    add(TAB * 2 + "end")
    add("")
    add(TAB + "decoded_codepoints (a_data: STRING_8): ARRAYED_LIST [NATURAL_32]")
    add(TAB * 3 + "-- Whitespace-separated lowercase hex in `a_data', decoded.")
    add(TAB * 2 + "local")
    add(TAB * 3 + "i: INTEGER")
    add(TAB * 3 + "c: CHARACTER_8")
    add(TAB * 3 + "l_value: NATURAL_32")
    add(TAB * 3 + "l_in_digits: BOOLEAN")
    add(TAB * 2 + "do")
    add(TAB * 3 + "create Result.make (64)")
    add(TAB * 3 + "from i := 1 until i > a_data.count + 1 loop")
    add(TAB * 4 + "if i > a_data.count then")
    add(TAB * 5 + "c := ' '")
    add(TAB * 4 + "else")
    add(TAB * 5 + "c := a_data [i]")
    add(TAB * 4 + "end")
    add(TAB * 4 + "if is_hex_digit (c) then")
    add(TAB * 5 + "l_value := l_value * 16 + hex_value (c)")
    add(TAB * 5 + "l_in_digits := True")
    add(TAB * 4 + "elseif l_in_digits then")
    add(TAB * 5 + "Result.extend (l_value)")
    add(TAB * 5 + "l_value := 0")
    add(TAB * 5 + "l_in_digits := False")
    add(TAB * 4 + "end")
    add(TAB * 4 + "i := i + 1")
    add(TAB * 3 + "end")
    add(TAB * 2 + "ensure")
    add(TAB * 3 + "paired: Result.count \\\\ 2 = 0")
    add(TAB * 2 + "end")
    add("")
    add(TAB + "is_hex_digit (a_character: CHARACTER_8): BOOLEAN")
    add(TAB * 3 + "-- Is `a_character' one of 0..9, a..f?")
    add(TAB * 2 + "do")
    add(TAB * 3 + "Result := (a_character >= '0' and a_character <= '9')")
    add(TAB * 4 + "or (a_character >= 'a' and a_character <= 'f')")
    add(TAB * 2 + "ensure")
    add(TAB * 3 + "definition: Result = ((a_character >= '0' and a_character <= '9')")
    add(TAB * 4 + "or (a_character >= 'a' and a_character <= 'f'))")
    add(TAB * 2 + "end")
    add("")
    add(TAB + "hex_value (a_character: CHARACTER_8): NATURAL_32")
    add(TAB * 3 + "-- Numeric value of the hex digit `a_character'.")
    add(TAB * 2 + "require")
    add(TAB * 3 + "hex: is_hex_digit (a_character)")
    add(TAB * 2 + "do")
    add(TAB * 3 + "if a_character <= '9' then")
    add(TAB * 4 + "Result := (a_character.code - ('0').code).to_natural_32")
    add(TAB * 3 + "else")
    add(TAB * 4 + "Result := (a_character.code - ('a').code + 10).to_natural_32")
    add(TAB * 3 + "end")
    add(TAB * 2 + "ensure")
    add(TAB * 3 + "in_range: Result <= 15")
    add(TAB * 2 + "end")
    add("")
    add("feature {NONE} -- Generated data blobs")
    add("")
    add(TAB + "Extended_pictographic_data: STRING_8 = " + verbatim(range_tokens, 2))
    add(TAB * 3 + "-- %d merged Extended_Pictographic ranges: lo hi lo hi ..."
        % len(ranges))
    for index, tokens in enumerate(chunks, start=1):
        first = sum(len(item) for item in chunks[:index - 1]) + 1
        last = sum(len(item) for item in chunks[:index])
        add("")
        add(TAB + "Rgi_data_%d: STRING_8 = %s" % (index, verbatim(tokens, 2)))
        add(TAB * 3 + "-- RGI sequences %d .. %d of %d (canonical, VS16-free)."
            % (first, last, len(sequences)))
    add("")
    add("end")
    add("")

    stats = {
        "version": version,
        "ranges": len(ranges),
        "sequences": len(sequences),
        "chunks": len(chunks),
        "max_canonical": max_canonical,
        "max_raw": max_raw,
    }
    # CRLF everywhere, including inside the multi-line verbatim blobs.
    text = "\n".join(lines).replace("\r\n", "\n").replace("\n", "\r\n")
    return text, stats


def main():
    parser = argparse.ArgumentParser(description="Generate EMOJI_DATA_TABLES.")
    parser.add_argument("--check", action="store_true",
                        help="report whether the generated file is up to date")
    args = parser.parse_args()

    inputs = {}
    for name in INPUT_FILES:
        path = os.path.join(HERE, name)
        if not os.path.exists(path):
            raise SystemExit("missing pinned input: " + path)
        inputs[name] = sha256_of(path)

    text, stats = build(inputs)
    payload = text.encode("utf-8")

    if args.check:
        if os.path.exists(OUT_PATH):
            with open(OUT_PATH, "rb") as handle:
                current = handle.read()
        else:
            current = b""
        if current == payload:
            print("up to date: " + OUT_PATH)
            return 0
        print("STALE: " + OUT_PATH)
        return 1

    with open(OUT_PATH, "wb") as handle:
        handle.write(payload)
    print("wrote %s" % OUT_PATH)
    print("  unicode emoji version : %s" % stats["version"])
    print("  Extended_Pictographic : %d merged ranges" % stats["ranges"])
    print("  RGI sequences         : %d in %d blobs"
          % (stats["sequences"], stats["chunks"]))
    print("  max canonical / raw   : %d / %d"
          % (stats["max_canonical"], stats["max_raw"]))
    for name in INPUT_FILES:
        print("  %-24s %s" % (name, inputs[name]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
