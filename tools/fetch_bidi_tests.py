#!/usr/bin/env python3
"""fetch_bidi_tests.py - download the PINNED Unicode bidi conformance files.

The full files are NOT committed (they are ~7 MB and ~2 MB of generated data
that belongs to Unicode, Inc., and git is not their distribution channel).
They land in testing/fixtures/ which .gitignore excludes; the committed
artifacts are:

  tools/bidi-conformance.md              the pin: version + URL + sha256
  testing/test_data/BidiCharacterTest.sample.txt   the curated sample the
                                                   Phase-4 test runs

Usage
-----
  python tools/fetch_bidi_tests.py            download + verify the sha256
  python tools/fetch_bidi_tests.py --sample   also regenerate the sample
  python tools/fetch_bidi_tests.py --print-sha  report the sha256 and exit

Phase 4 Task 3 runs BIDI_CONFORMANCE_HARNESS over the committed sample on
every build. Phase 4 Task 12 runs it over the FULL files downloaded here:

  SIMPLE_SHAPING_BIDI_STRIDE=1 ./EIFGENs/simple_shaping_tests/F_code/simple_shaping.exe

Without that variable the two full-file tests run a documented stride
(every 18th / every 150th data line) so the routine suite stays fast. The
totals of the full run are in tools/bidi-conformance.md.
"""

import argparse
import hashlib
import os
import sys
import urllib.request

UNICODE_VERSION = "16.0.0"

FILES = {
    "BidiCharacterTest.txt": {
        "url": "https://www.unicode.org/Public/16.0.0/ucd/BidiCharacterTest.txt",
        "sha256": "d04a51a90052dcd71c4e91ee5b3a9d973ee35c12406b5a99875ac8163c8f2804",
        "size": 6880649,
    },
    "BidiTest.txt": {
        "url": "https://www.unicode.org/Public/16.0.0/ucd/BidiTest.txt",
        "sha256": "93e5eb9d88ca89dcf895f5576486a3363762ad2aa8f2db2fa56fe60cb82b9520",
        "size": 7959988,
    },
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = os.path.join(ROOT, "testing", "fixtures")
SAMPLE = os.path.join(ROOT, "testing", "test_data", "BidiCharacterTest.sample.txt")

# ---------------------------------------------------------------------------
# Sampling rule (STATED, so nothing is excluded silently)
# ---------------------------------------------------------------------------
# BidiCharacterTest.txt is 91,707 data lines, and the great majority of them
# are machine-generated paired-bracket cases: only 129 of the 91,707 contain a
# digit at all, and only 28 use the "auto" paragraph direction. A plain stride
# through the file would therefore have produced a sample that was almost
# entirely brackets. The committed sample is built from FIVE ADDITIVE BLOCKS -
# every rule below only ADDS cases, none removes any:
#
#   A. the first HEAD_CASES data lines of the file (the worked examples
#      transcribed from UAX #9 itself, "car MEANS CAR." and friends);
#   B. paragraph direction 0 (LTR) - SAMPLE_PER_STRATUM cases at a fixed
#      stride through the whole stratum, in file order;
#   C. paragraph direction 1 (RTL) - likewise;
#   D. paragraph direction 2 (auto / first strong) - ALL of them (28);
#   E. NUMBER_CASES cases containing an EN (U+0030..U+0039) or AN
#      (U+0660..U+0669) code point, at a stride through that whole set.
#
# Duplicates between blocks are dropped, first occurrence wins, and file order
# is preserved inside each block. No case is dropped for being hard: bracket
# pairs, isolates, explicit embedding codes and X9-removed positions are all
# in. What the backend gets wrong is REPORTED in the evidence, never sampled
# away.
SAMPLE_PER_STRATUM = 150
HEAD_CASES = 45
NUMBER_CASES = 45


def data_lines(text):
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("@"):
            continue
        yield line


def build_sample(source_text):
    lines = list(data_lines(source_text))
    cases = [l for l in lines if len(l.split(";")) == 5]

    def stride_pick(pool, wanted):
        if not pool:
            return []
        stride = max(1, len(pool) // wanted)
        return pool[::stride][:wanted]

    def has_number(line):
        for token in line.split(";")[0].split():
            code = int(token, 16)
            if 0x0030 <= code <= 0x0039 or 0x0660 <= code <= 0x0669:
                return True
        return False

    blocks = []
    blocks.append(("A: the first %d cases of the file (UAX #9 worked examples)" % HEAD_CASES,
                   cases[:HEAD_CASES]))
    for direction, label in (("0", "LTR"), ("1", "RTL"), ("2", "auto / first strong")):
        pool = [l for l in cases if l.split(";")[1].strip() == direction]
        wanted = len(pool) if direction == "2" else SAMPLE_PER_STRATUM
        picked = stride_pick(pool, wanted)
        blocks.append(("%s: paragraph direction %s (%s) - %d of %d, stride %d"
                       % ("BCD"[int(direction)], direction, label, len(picked), len(pool),
                          max(1, len(pool) // wanted) if pool else 1), picked))
    numbers = [l for l in cases if has_number(l)]
    blocks.append(("E: cases containing EN or AN digits - %d of %d"
                   % (min(NUMBER_CASES, len(numbers)), len(numbers)),
                   stride_pick(numbers, NUMBER_CASES)))

    seen = set()
    out = []
    for label, picked in blocks:
        fresh = [l for l in picked if l not in seen]
        seen.update(fresh)
        out.append("# ---- block %s; %d new ----" % (label, len(fresh)))
        out.extend(fresh)
    return out


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(name, spec):
    os.makedirs(FIXTURES, exist_ok=True)
    target = os.path.join(FIXTURES, name)
    if not os.path.exists(target):
        print("downloading %s -> %s" % (spec["url"], target))
        with urllib.request.urlopen(spec["url"], timeout=120) as response:
            payload = response.read()
        with open(target, "wb") as handle:
            handle.write(payload)
    digest = sha256_of(target)
    expected = spec.get("sha256") or ""
    status = "OK" if (not expected or digest == expected) else "MISMATCH"
    print("%-26s %10d bytes  sha256 %s  %s"
          % (name, os.path.getsize(target), digest, status))
    if expected and digest != expected:
        return None
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", action="store_true",
                        help="regenerate testing/test_data/BidiCharacterTest.sample.txt")
    parser.add_argument("--print-sha", action="store_true",
                        help="print the sha256 of each downloaded file and exit")
    args = parser.parse_args()

    print("Unicode %s bidi conformance files" % UNICODE_VERSION)
    paths = {}
    for name, spec in FILES.items():
        path = download(name, spec)
        if path is None:
            print("ERROR: %s does not match the pinned sha256" % name)
            return 2
        paths[name] = path

    if args.print_sha:
        return 0

    if args.sample:
        with open(paths["BidiCharacterTest.txt"], "r", encoding="utf-8") as handle:
            source = handle.read()
        lines = build_sample(source)
        header = [
            "# BidiCharacterTest.sample.txt - a CURATED SAMPLE of the Unicode",
            "# %s BidiCharacterTest.txt (see tools/bidi-conformance.md for the" % UNICODE_VERSION,
            "# pinned URL and sha256; the full file is not committed).",
            "#",
            "# Format, verbatim from the source file:",
            "#   codepoints ; paragraph-direction ; paragraph-level ; levels ; visual-order",
            "#   paragraph-direction: 0 = LTR, 1 = RTL, 2 = auto (first strong)",
            "#   levels: 'x' marks a position removed by rule X9",
            "#   visual-order: 0-based input indices of the KEPT positions, left to right",
            "#",
            "# Sampling rule (deterministic, five ADDITIVE blocks - see the comment",
            "# in tools/fetch_bidi_tests.py and tools/bidi-conformance.md): the UAX #9",
            "# worked examples at the head of the file, then a fixed stride through",
            "# each paragraph-direction stratum, ALL 28 auto cases, and a stride",
            "# through the cases that contain digits. Nothing is filtered out for",
            "# being hard - bracket pairs, isolates, explicit embedding codes and",
            "# X9-removed positions are all in.",
            "#",
        ]
        with open(SAMPLE, "w", encoding="utf-8", newline="\n") as handle:
            handle.write("\n".join(header + lines) + "\n")
        print("sample: %d lines -> %s" % (len(lines), SAMPLE))

    return 0


if __name__ == "__main__":
    sys.exit(main())
