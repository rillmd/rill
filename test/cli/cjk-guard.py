#!/usr/bin/env python3
"""CJK guard -- block CJK (Hiragana / Katakana / Han) outside the allowlist.

This repo is English-only (SPEC): CJK characters are allowed only where
test/cjk-allowlist.txt explicitly permits them, line by line.

Modes:
  (default)  Tree mode. Scan every git-tracked text file; a line containing
             CJK is a violation unless an allowlist entry has (1) a path equal
             to the file AND (2) a regex matching the line.
  --raw      Tree mode without the allowlist: print every CJK hit as
             path:lineno:line and exit 0. Used for the parity check against
             the reference scan documented in test/cjk-allowlist.txt:
               git ls-files -z | xargs -0 rg -n --no-messages \
                 '[\\p{Hiragana}\\p{Katakana}\\p{Han}]'
  --stdin    Read raw text from stdin (e.g. commit messages). ANY CJK line is
             a violation -- no allowlist applies; commit messages must be
             CJK-free, period.

Exit codes: 0 clean, 1 violations found, 2 usage / internal error.
Stdlib only -- no third-party dependencies (CI runs it on a bare runner).
"""

import os
import re
import subprocess
import sys

ALLOWLIST_PATH = "test/cjk-allowlist.txt"


def _chdir_repo_root():
    """Paths (allowlist, git ls-files) are repo-root-relative; run from anywhere."""
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                         capture_output=True).stdout.decode().strip()
    os.chdir(top)

# Unicode Script ranges for Hiragana, Katakana and Han, mirrored from UCD
# Scripts.txt so the hit-set matches rg's [\p{Hiragana}\p{Katakana}\p{Han}].
# (Python's re has no \p{Script=...}; these ranges are the stdlib equivalent.)
_CJK_RANGES = [
    # Script=Hiragana
    (0x3041, 0x3096), (0x309D, 0x309F), (0x1B001, 0x1B11F), (0x1B132, 0x1B132),
    (0x1B150, 0x1B152), (0x1F200, 0x1F200),
    # Script=Katakana
    (0x30A1, 0x30FA), (0x30FD, 0x30FF), (0x31F0, 0x31FF), (0x32D0, 0x32FE),
    (0x3300, 0x3357), (0xFF66, 0xFF9D), (0x1AFF0, 0x1AFF3), (0x1AFF5, 0x1AFFB),
    (0x1AFFD, 0x1AFFE), (0x1B000, 0x1B000), (0x1B120, 0x1B122),
    (0x1B155, 0x1B155), (0x1B164, 0x1B167),
    # Script=Han
    (0x2E80, 0x2E99), (0x2E9B, 0x2EF3), (0x2F00, 0x2FD5), (0x3005, 0x3005),
    (0x3007, 0x3007), (0x3021, 0x3029), (0x3038, 0x303B), (0x3400, 0x4DBF),
    (0x4E00, 0x9FFF), (0xF900, 0xFA6D), (0xFA70, 0xFAD9), (0x20000, 0x2A6DF),
    (0x2A700, 0x2B739), (0x2B740, 0x2B81D), (0x2B820, 0x2CEA1),
    (0x2CEB0, 0x2EBE0), (0x2EBF0, 0x2EE5D), (0x2F800, 0x2FA1D),
    (0x30000, 0x3134A), (0x31350, 0x323AF),
]

CJK_RE = re.compile(
    "[" + "".join(f"{chr(lo)}-{chr(hi)}" for lo, hi in _CJK_RANGES) + "]"
)


def load_allowlist():
    """Return [(path, compiled_regex, reason)] from test/cjk-allowlist.txt."""
    entries = []
    try:
        with open(ALLOWLIST_PATH, encoding="utf-8") as f:
            for n, raw in enumerate(f, 1):
                line = raw.rstrip("\n")
                if not line or line.lstrip().startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) < 3:
                    print(f"{ALLOWLIST_PATH}:{n}: malformed entry "
                          f"(need <path>\\t<regex>\\t<reason>)", file=sys.stderr)
                    sys.exit(2)
                try:
                    entries.append((parts[0], re.compile(parts[1]), parts[2]))
                except re.error as e:
                    print(f"{ALLOWLIST_PATH}:{n}: bad regex: {e}", file=sys.stderr)
                    sys.exit(2)
    except FileNotFoundError:
        pass  # no allowlist -> every hit is a violation
    return entries


def tracked_files():
    out = subprocess.run(["git", "ls-files", "-z"], check=True,
                         capture_output=True).stdout
    return [p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p]


def iter_tree_hits():
    """Yield (path, lineno, line_text) for every CJK hit in tracked text files."""
    for path in tracked_files():
        try:
            with open(path, "rb") as f:
                data = f.read()
        except (OSError, IsADirectoryError):
            continue
        if b"\0" in data[:8192]:
            continue  # binary, same heuristic rg uses
        for lineno, raw in enumerate(data.split(b"\n"), 1):
            text = raw.decode("utf-8", "replace").rstrip("\r")
            if CJK_RE.search(text):
                yield path, lineno, text


def main(argv):
    mode = argv[1] if len(argv) > 1 else "tree"
    if mode not in ("tree", "--raw", "--stdin"):
        print(__doc__, file=sys.stderr)
        return 2

    if mode != "--stdin":
        _chdir_repo_root()

    if mode == "--stdin":
        violations = [
            f"(stdin):{n}:{line}"
            for n, line in enumerate(sys.stdin.read().splitlines(), 1)
            if CJK_RE.search(line)
        ]
        for v in violations:
            print(v)
        if violations:
            print(f"cjk-guard: {len(violations)} CJK line(s) in stdin "
                  f"(no allowlist applies here)", file=sys.stderr)
            return 1
        return 0

    if mode == "--raw":
        for path, lineno, text in iter_tree_hits():
            print(f"{path}:{lineno}:{text}")
        return 0

    allowlist = load_allowlist()
    used = set()
    violations = []
    for path, lineno, text in iter_tree_hits():
        allowed = False
        for i, (apath, aregex, _reason) in enumerate(allowlist):
            if path == apath and aregex.search(text):
                allowed = True
                used.add(i)
                break
        if not allowed:
            violations.append(f"{path}:{lineno}:{text}")
    for v in violations:
        print(v)
    for i, (apath, aregex, reason) in enumerate(allowlist):
        if i not in used:
            print(f"cjk-guard: note: unused allowlist entry "
                  f"{apath} / {aregex.pattern!r} ({reason})", file=sys.stderr)
    if violations:
        print(f"cjk-guard: {len(violations)} unallowlisted CJK line(s); "
              f"add an entry to {ALLOWLIST_PATH} only if the CJK is deliberate",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
