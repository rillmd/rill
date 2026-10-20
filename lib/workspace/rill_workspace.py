#!/usr/bin/env python3
"""rill workspace -- workspace state machine and distill record.

Invoked by `bin/rill workspace ...` (cmd_workspace). Standard library only;
targets Python 3.9 (the macOS Command Line Tools interpreter).

Workspace `status` values
-------------------------
  active           being worked on (a waiting box stays active and carries
                   `snooze-until` + `snooze-reason`)
  distill-pending  closed; knowledge distillation not yet verified. The set of
                   distill-pending workspaces IS the distill queue
  completed        closed, and the distill record passed `verify`

`on-hold` is a legacy value. It is accepted only as the source state of
`close` and `reopen` (migration path) and is reported by `check`.

Transitions (every other change is refused):
  close     active | on-hold                         -> distill-pending
  reopen    distill-pending | completed | on-hold    -> active
  requeue   completed                                -> distill-pending
  complete  distill-pending                          -> completed (verify must pass)
  snooze / unsnooze                                     active only (fields)

Only `complete` writes `status: completed`, and only after `verify` passes.

Distill record (`workspace/{id}/_distill.md`)
---------------------------------------------
Written only by this helper. Each `close` / `requeue` starts a new round; each
round is an append-only JSONL event block. `verify` checks the latest round:

  0. the record parses and `_summary.md` exists
  1. the analysis-complete marker is present
  2. the analysis file list equals the coverage set, and every listed file has
     >= 1 candidate or a note saying why it yields none
  3. every candidate has exactly one outcome
  4. created / updated / EVERGREEN_DUPLICATE paths exist; created notes carry a
     `source:` inside this workspace
  5. every skip has a valid label and reason; MERGED_INTO_OTHER points at a
     candidate that was created or updated
  6. totals are recounted from the rows (never read from a summary line)

Coverage set (the files the analysis must account for): every `*.md` under the
workspace directory, recursively, except `_summary.md`, `_distill.md`, and
anything inside a dot-directory (e.g. `.view/`); plus every top-level `*.html`
that has no same-basename `.md` (HTML-canonical artifacts). Paths are relative
to the workspace directory.

Run state (lock) lives in `{vault}/.rill/state/distill/{id}.lock` (gitignored,
machine-local). Mutations are serialized with flock on `{id}.flock` and files
are replaced atomically (temp file + os.replace).
"""

import argparse
import datetime as _dt
import errno
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile

STATUS_VALUES = ("active", "distill-pending", "completed")
LEGACY_STATUS = ("on-hold",)
NOTE_TYPES = ("record", "insight", "reference")
SKIP_LABELS = (
    "EVERGREEN_DUPLICATE",
    "INTERMEDIATE_CONCLUSION",
    "IMPLEMENTATION_DETAIL",
    "MERGED_INTO_OTHER",
    "USER_DECLINED",
)
FORBIDDEN_REASONS = (
    "pragmatic",
    "save time",
    "not novel",
    "context budget",
    "sufficient coverage",
)
CLOSE_KINDS = ("done", "concluded", "abandoned", "superseded")
DISTILL_HINTS = ("full", "partial", "none")
RECORD_NAME = "_distill.md"
META_NAME = "_workspace.md"
META_NAMES = ("_workspace.md", "_session.md", "_project.md")  # priority order; legacy names are never renamed
SUMMARY_NAME = "_summary.md"
DEFAULT_STALE_HOURS = 3.0
STUCK_RUNS = 3
CID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_LOCKED = 3


class RillError(Exception):
    def __init__(self, message, code=EXIT_ERROR):
        super().__init__(message)
        self.code = code


# --------------------------------------------------------------------------
# time


def now():
    return _dt.datetime.now().astimezone().replace(second=0, microsecond=0)


def iso(ts):
    s = ts.strftime("%Y-%m-%dT%H:%M%z")
    return s[:-2] + ":" + s[-2:]


def parse_iso(value):
    if not value:
        return None
    v = value.strip().strip('"').strip("'")
    for fmt in ("%Y-%m-%dT%H:%M%z", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            return _dt.datetime.strptime(v, fmt)
        except ValueError:
            pass
    try:
        ts = _dt.datetime.fromisoformat(v)
    except ValueError:
        return None
    return ts if ts.tzinfo else ts.astimezone()


# --------------------------------------------------------------------------
# filesystem helpers


def vault_root():
    home = os.environ.get("RILL_HOME", "")
    if not home or not os.path.isdir(home):
        raise RillError("no vault resolved -- run inside a vault or set RILL_HOME")
    return os.path.realpath(home)


def atomic_write(path, text):
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(path) + ".", suffix=".tmp", dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def state_dir(vault):
    d = os.path.join(vault, ".rill", "state", "distill")
    os.makedirs(d, exist_ok=True)
    return d


class Mutex(object):
    """flock on a sidecar file; the guarded files themselves are replaced."""

    def __init__(self, vault, ws_id):
        self.path = os.path.join(state_dir(vault), ws_id + ".flock")
        self.fh = None

    def __enter__(self):
        self.fh = open(self.path, "a+")
        fcntl.flock(self.fh.fileno(), fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        try:
            fcntl.flock(self.fh.fileno(), fcntl.LOCK_UN)
        finally:
            self.fh.close()
        return False


# --------------------------------------------------------------------------
# workspace + frontmatter


class Workspace(object):
    def __init__(self, vault, ws_id):
        self.vault = vault
        self.id = ws_id
        self.dir = os.path.join(vault, "workspace", ws_id)
        self.meta = os.path.join(self.dir, META_NAME)
        for name in META_NAMES:
            if os.path.isfile(os.path.join(self.dir, name)):
                self.meta = os.path.join(self.dir, name)
                break
        self.record = os.path.join(self.dir, RECORD_NAME)
        self.summary = os.path.join(self.dir, SUMMARY_NAME)
        self.lock = os.path.join(state_dir(vault), ws_id + ".lock")

    @property
    def rel(self):
        return "workspace/" + self.id


def resolve_workspace(vault, arg):
    a = arg.strip()
    if os.path.isabs(a):
        try:
            a = os.path.relpath(os.path.realpath(a), vault)
        except ValueError:
            pass
    a = a.rstrip("/")
    for name in META_NAMES:
        if a.endswith("/" + name):
            a = a[: -len(name) - 1]
            break
    if a.startswith("workspace/"):
        a = a[len("workspace/"):]
    if not a or "/" in a or a in (".", ".."):
        raise RillError("not a workspace id or path: %s" % arg)
    ws = Workspace(vault, a)
    if not os.path.isfile(ws.meta):
        raise RillError("no metadata file (%s) for workspace %s" % (" / ".join(META_NAMES), a))
    return ws


def split_frontmatter(text):
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        raise RillError("file has no frontmatter")
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return lines[1:i], lines[i + 1:]
    raise RillError("unterminated frontmatter")


def unquote(v):
    v = v.strip()
    if v and v[0] not in ("'", '"'):
        # YAML end-of-line comment: whitespace then '#'
        m = re.search(r"\s#", v)
        if m:
            v = v[: m.start()].rstrip()
        return v
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        if v[0] == '"':
            try:
                return json.loads(v)
            except ValueError:
                return v[1:-1]
        return v[1:-1].replace("''", "'")
    return v


def fm_get(fm_lines, key):
    prefix = key + ":"
    for line in fm_lines:
        if line.startswith(prefix):
            return unquote(line[len(prefix):])
    return None


def read_meta(ws):
    with open(ws.meta, encoding="utf-8") as fh:
        text = fh.read()
    fm, body = split_frontmatter(text)
    return fm, body


def meta_get(ws, key):
    fm, _ = read_meta(ws)
    return fm_get(fm, key)


def yaml_scalar(value):
    if re.match(r"^[A-Za-z0-9][A-Za-z0-9 ._:+/-]*$", value) and ": " not in value and not value.endswith(":"):
        return value
    return json.dumps(value, ensure_ascii=False)


def write_meta(ws, updates=None, removes=()):
    """Replace/insert simple top-level keys; new keys go right after `status:`."""
    updates = updates or {}
    fm, body = read_meta(ws)
    out = []
    pending = dict(updates)
    for line in fm:
        key = line.split(":", 1)[0] if (":" in line and not line.startswith((" ", "\t", "-"))) else None
        if key in removes and key not in pending:
            continue
        if key in pending:
            out.append("%s: %s" % (key, yaml_scalar(pending.pop(key))))
            continue
        out.append(line)
    if pending:
        idx = len(out)
        for i, line in enumerate(out):
            if line.startswith("status:"):
                idx = i + 1
                break
        for k in [k for k in updates if k in pending]:
            out.insert(idx, "%s: %s" % (k, yaml_scalar(pending[k])))
            idx += 1
    text = "---\n" + "\n".join(out) + "\n---\n" + "\n".join(body)
    atomic_write(ws.meta, text)


# --------------------------------------------------------------------------
# coverage


def coverage_files(ws):
    files = []
    for root, dirs, names in os.walk(ws.dir):
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d not in ("node_modules", "__pycache__"))
        for name in sorted(names):
            if name.startswith("."):
                continue
            rel = os.path.relpath(os.path.join(root, name), ws.dir)
            if name.endswith(".md"):
                if rel in (SUMMARY_NAME, RECORD_NAME):
                    continue
                files.append(rel)
            elif name.endswith(".html") and root == ws.dir:
                if not os.path.exists(os.path.join(ws.dir, name[:-5] + ".md")):
                    files.append(rel)
    return sorted(files)


def normalize_ws_path(ws, path):
    p = (path or "").strip()
    for prefix in ("workspace/%s/" % ws.id, "./"):
        if p.startswith(prefix):
            p = p[len(prefix):]
    return p


# --------------------------------------------------------------------------
# distill record


class Record(object):
    def __init__(self, ws, created=None, rounds=None):
        self.ws = ws
        self.created = created
        self.rounds = rounds or []  # list of event lists

    @classmethod
    def load(cls, ws):
        if not os.path.exists(ws.record):
            return cls(ws)
        with open(ws.record, encoding="utf-8") as fh:
            text = fh.read()
        try:
            fm, body = split_frontmatter(text)
        except RillError as e:
            raise RillError("%s: %s" % (RECORD_NAME, e))
        created = fm_get(fm, "created")
        rounds = []
        in_block = False
        current = None
        for n, line in enumerate(body, 1):
            if not in_block and re.match(r"^## Round \d+\s*$", line):
                current = []
                rounds.append(current)
                continue
            if current is not None and not in_block and line.strip() == "```jsonl":
                in_block = True
                continue
            if in_block and line.strip() == "```":
                in_block = False
                continue
            if in_block:
                if not line.strip():
                    continue
                try:
                    ev = json.loads(line)
                except ValueError:
                    raise RillError("%s is corrupted (bad JSON on body line %d) -- it is written only by `rill workspace`" % (RECORD_NAME, n))
                if not isinstance(ev, dict) or "event" not in ev:
                    raise RillError("%s is corrupted (event without type on body line %d)" % (RECORD_NAME, n))
                current.append(ev)
        if in_block:
            raise RillError("%s is corrupted (unterminated event block)" % RECORD_NAME)
        return cls(ws, created, rounds)

    # ---- queries on the latest round

    @property
    def round(self):
        return self.rounds[-1] if self.rounds else None

    def events(self, kind, rnd=None):
        r = self.round if rnd is None else rnd
        return [e for e in (r or []) if e.get("event") == kind]

    def analysis_complete(self):
        return bool(self.events("analysis-complete"))

    def candidates(self):
        return self.events("candidate")

    def outcomes(self):
        return self.events("outcome")

    def outcome_map(self):
        m = {}
        for o in self.outcomes():
            m.setdefault(o.get("id"), []).append(o)
        return m

    def effective_outcomes(self):
        """Latest outcome per candidate (an `amend` outcome supersedes the earlier one)."""
        eff = {}
        for o in self.outcomes():
            eff[o.get("id")] = o
        return eff

    def pending_candidates(self):
        done = self.outcome_map()
        return [c for c in self.candidates() if c.get("id") not in done]

    def runs(self, rnd=None):
        """List of dicts {run, start, end} for a round."""
        runs = {}
        order = []
        for e in (self.round if rnd is None else rnd) or []:
            if e.get("event") == "run-start":
                runs[e["run"]] = {"run": e["run"], "start": e, "end": None}
                order.append(e["run"])
            elif e.get("event") == "run-end" and e.get("run") in runs:
                runs[e["run"]]["end"] = e
        return [runs[k] for k in order]

    def all_runs(self):
        out = []
        for r in self.rounds:
            out.extend(self.runs(r))
        return out

    def open_run(self):
        runs = self.runs()
        if runs and runs[-1]["end"] is None:
            return runs[-1]
        return None

    def next_run_number(self):
        nums = [r["run"] for r in self.all_runs()]
        return (max(nums) + 1) if nums else 1

    def progress_since(self, run_no):
        seen = False
        count = 0
        for e in self.round or []:
            if e.get("event") == "run-start" and e.get("run") == run_no:
                seen = True
                continue
            if seen and e.get("event") in ("candidate", "outcome", "analysis-complete"):
                count += 1
        return count

    def consecutive_no_progress(self):
        n = 0
        for r in reversed(self.all_runs()):
            end = r["end"]
            if end is None:
                break
            if end.get("result") == "deferred":
                continue
            if end.get("result") == "completed" or end.get("progress", 0) > 0:
                break
            n += 1
        return n

    # ---- mutation

    def start_round(self, origin, extra=None):
        ev = {"event": "round", "round": len(self.rounds) + 1, "at": iso(now()), "origin": origin}
        if extra:
            ev.update(extra)
        self.rounds.append([ev])

    def append(self, *events):
        if not self.rounds:
            raise RillError("no distill round -- close or requeue the workspace first")
        for ev in events:
            self.rounds[-1].append(ev)

    def render(self):
        created = self.created or iso(now())
        lines = [
            "---",
            "created: %s" % created,
            "type: distill-record",
            "workspace: %s" % self.ws.id,
            "---",
            "",
            "# Distill record",
            "",
            "Written only by `rill workspace` subcommands -- do not edit by hand. "
            "`rill workspace verify %s` checks the latest round; `rill workspace distill show %s` summarizes it."
            % (self.ws.id, self.ws.id),
            "",
        ]
        lines.extend(self.summary_lines())
        for i, rnd in enumerate(self.rounds, 1):
            lines.append("")
            lines.append("## Round %d" % i)
            lines.append("")
            lines.append("```jsonl")
            for ev in rnd:
                lines.append(json.dumps(ev, ensure_ascii=False, sort_keys=False))
            lines.append("```")
        return "\n".join(lines) + "\n"

    def summary_lines(self):
        if not self.rounds:
            return ["## Current round", "", "- No round yet."]
        r0 = self.round[0] if self.round else {}
        cands = self.candidates()
        om = self.outcome_map()
        counts = {}
        for o in self.effective_outcomes().values():
            k = o.get("status")
            if k == "skipped":
                k = "skipped/" + str(o.get("label"))
            counts[k] = counts.get(k, 0) + 1
        runs = self.runs()
        out = [
            "## Current round",
            "",
            "- Round %d, started %s (%s)" % (len(self.rounds), r0.get("at", "?"), r0.get("origin", "?")),
        ]
        if self.analysis_complete():
            ac = self.events("analysis-complete")[-1]
            out.append("- Analysis: complete (%d files, %d candidates)" % (ac.get("files", 0), ac.get("candidates", 0)))
        else:
            out.append("- Analysis: not complete")
        out.append("- Outcomes: %d of %d candidates" % (sum(1 for c in cands if c.get("id") in om), len(cands)))
        for k in sorted(counts):
            out.append("  - %s: %d" % (k, counts[k]))
        if runs:
            last = runs[-1]
            if last["end"] is None:
                out.append("- Runs: %d (run %d in progress since %s)" % (len(runs), last["run"], last["start"].get("at")))
            else:
                e = last["end"]
                out.append(
                    "- Runs: %d (last: %s%s, progress %s)"
                    % (len(runs), e.get("result"), (", " + e["reason"]) if e.get("reason") else "", e.get("progress", 0))
                )
        else:
            out.append("- Runs: 0")
        if any(e.get("event") == "complete" for e in self.round):
            out.append("- Verified and completed: %s" % self.events("complete")[-1].get("at"))
        return out

    def save(self):
        if self.created is None:
            self.created = iso(now())
        atomic_write(self.ws.record, self.render())


# --------------------------------------------------------------------------
# lock


def read_lock(ws):
    try:
        with open(ws.lock, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {"started": None}
    except (IOError, OSError):
        return None
    except ValueError:
        return {"started": None}


def lock_age_hours(lock):
    started = parse_iso((lock or {}).get("started") or "")
    if started is None:
        return float("inf")
    return (now() - started).total_seconds() / 3600.0


def refuse_if_locked(ws, action):
    lock = read_lock(ws)
    if lock is not None:
        raise RillError(
            "%s refused: workspace %s is being distilled (run %s since %s; lock %s)"
            % (action, ws.id, lock.get("run"), lock.get("started"), ws.lock),
            EXIT_LOCKED,
        )


# --------------------------------------------------------------------------
# verify


def verify(ws, rec=None):
    """Return (failures, totals) for the latest round."""
    failures = []
    totals = {}
    try:
        rec = rec or Record.load(ws)
    except RillError as e:
        return [str(e)], totals
    if not rec.rounds:
        return ["no distill record (%s missing or empty)" % RECORD_NAME], totals
    if not os.path.isfile(ws.summary):
        failures.append("%s is missing" % SUMMARY_NAME)
    # 1
    if not rec.analysis_complete():
        failures.append("analysis did not finish (no analysis-complete marker in the latest round)")
        return failures, totals
    # 2
    listed = {}
    for f in rec.events("file"):
        listed[f.get("path")] = f
    cands = rec.candidates()
    by_source = {}
    for c in cands:
        by_source.setdefault(c.get("source"), []).append(c)
    actual = set(coverage_files(ws))
    missing = sorted(actual - set(listed))
    extra = sorted(set(listed) - actual)
    if missing:
        failures.append("analysis did not account for: %s" % ", ".join(missing))
    if extra:
        failures.append("analysis lists files that no longer exist: %s" % ", ".join(extra))
    for path, f in sorted(listed.items()):
        if not by_source.get(path) and not (f.get("note") or "").strip():
            failures.append("file %s has no candidates and no note" % path)
    # 3
    om = rec.outcome_map()
    ids = [c.get("id") for c in cands]
    dup_ids = sorted(set(i for i in ids if ids.count(i) > 1))
    if dup_ids:
        failures.append("duplicate candidate ids: %s" % ", ".join(dup_ids))
    no_outcome = [i for i in ids if i not in om]
    if no_outcome:
        failures.append("%d candidate(s) without an outcome: %s" % (len(no_outcome), ", ".join(no_outcome)))
    multi = sorted(i for i, v in om.items() if sum(1 for o in v if not o.get("amend")) > 1)
    if multi:
        failures.append("candidate(s) with more than one outcome: %s" % ", ".join(multi))
    orphan = sorted(i for i in om if i not in ids)
    if orphan:
        failures.append("outcome(s) for unknown candidates: %s" % ", ".join(orphan))
    # 4 + 5
    eff = rec.effective_outcomes()
    created_or_updated = set(i for i, o in eff.items() if o.get("status") in ("created", "updated"))
    for o in eff.values():
        failures.extend(check_outcome(ws, o, ids, created_or_updated))
    # 6
    totals = {"candidates": len(cands), "files": len(listed)}
    for o in eff.values():
        k = o.get("status")
        totals[k] = totals.get(k, 0) + 1
    totals["without_outcome"] = len(no_outcome)
    return failures, totals


def note_source_in_workspace(vault, ws, path):
    """True if the note's `source:` (scalar, inline list, or block list) names this workspace."""
    try:
        with open(os.path.join(vault, path), encoding="utf-8") as fh:
            fm, _ = split_frontmatter(fh.read())
    except (IOError, OSError, RillError):
        return False
    collected = []
    in_source = False
    for line in fm:
        if line.startswith("source:"):
            in_source = True
            collected.append(line[len("source:"):])
            continue
        if in_source:
            if line.startswith((" ", "\t", "-")):
                collected.append(line)
                continue
            break
    return ("workspace/%s/" % ws.id) in " ".join(collected)


def is_note_path(p):
    p = p or ""
    return (
        p.startswith("knowledge/notes/") and p.endswith(".md") and ".." not in p.split("/")
        and "/" not in p[len("knowledge/notes/"):]
    )


def check_outcome(ws, o, ids, created_or_updated):
    out = []
    cid = o.get("id")
    status = o.get("status")
    vault = ws.vault
    if status in ("created", "updated"):
        p = o.get("path") or ""
        if not is_note_path(p):
            out.append("%s: %s path must be a note in knowledge/notes/: %s" % (cid, status, p or "(no path)"))
        elif not os.path.isfile(os.path.join(vault, p)):
            out.append("%s: %s note does not exist: %s" % (cid, status, p))
        elif status == "created" and not note_source_in_workspace(vault, ws, p):
            out.append("%s: created note %s has no source inside workspace/%s/" % (cid, p, ws.id))
    elif status == "skipped":
        label = o.get("label")
        if label not in SKIP_LABELS:
            out.append("%s: invalid skip label %r" % (cid, label))
        if not (o.get("reason") or "").strip():
            out.append("%s: skipped without a reason" % cid)
        if label == "EVERGREEN_DUPLICATE":
            p = o.get("path") or ""
            if not is_note_path(p):
                out.append("%s: EVERGREEN_DUPLICATE path must be a note in knowledge/notes/: %s" % (cid, p or "(no path)"))
            elif not os.path.isfile(os.path.join(vault, p)):
                out.append("%s: EVERGREEN_DUPLICATE points at a missing note: %s" % (cid, p))
        if label == "MERGED_INTO_OTHER":
            into = o.get("into")
            if into not in ids:
                out.append("%s: MERGED_INTO_OTHER points at unknown candidate %r" % (cid, into))
            elif into not in created_or_updated:
                out.append("%s: MERGED_INTO_OTHER target %s was not created or updated" % (cid, into))
    else:
        out.append("%s: invalid outcome status %r" % (cid, status))
    return out


# --------------------------------------------------------------------------
# commands: state transitions


def current_status(ws):
    st = meta_get(ws, "status")
    return (st or "").strip()


def require_status(ws, allowed, action):
    st = current_status(ws)
    if st not in allowed:
        raise RillError(
            "%s refused: workspace %s is %r (allowed from: %s)" % (action, ws.id, st, ", ".join(allowed))
        )
    return st


def cmd_close(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    with Mutex(vault, ws.id):
        refuse_if_locked(ws, "close")
        prev = require_status(ws, ("active",) + LEGACY_STATUS, "close")
        if args.kind and args.kind not in CLOSE_KINDS:
            raise RillError("--kind must be one of: %s" % ", ".join(CLOSE_KINDS))
        if args.hint and args.hint not in DISTILL_HINTS:
            raise RillError("--hint must be one of: %s" % ", ".join(DISTILL_HINTS))
        ts = iso(now())
        updates = {"status": "distill-pending", "closed": ts}
        if args.kind:
            updates["close-kind"] = args.kind
        if args.hint:
            updates["distill-hint"] = args.hint
        rec = Record.load(ws)
        extra = {"from": prev}
        if args.hint:
            extra["hint"] = args.hint
        rec.start_round("close", extra)
        rec.save()
        write_meta(ws, updates, removes=("snooze-until", "snooze-reason", "distill-queue"))
    print("%s: %s -> distill-pending" % (ws.rel, prev))
    return EXIT_OK


def cmd_reopen(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    with Mutex(vault, ws.id):
        refuse_if_locked(ws, "reopen")
        prev = require_status(ws, ("distill-pending", "completed") + LEGACY_STATUS, "reopen")
        write_meta(ws, {"status": "active"}, removes=("closed", "close-kind", "distill-hint", "distill-queue"))
        rec = Record.load(ws)
        if rec.rounds:
            rec.append({"event": "reopen", "at": iso(now()), "from": prev})
            rec.save()
    print("%s: %s -> active" % (ws.rel, prev))
    return EXIT_OK


def cmd_requeue(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    with Mutex(vault, ws.id):
        refuse_if_locked(ws, "requeue")
        prev = require_status(ws, ("completed",), "requeue")
        updates = {"status": "distill-pending"}
        if args.backfill:
            updates["distill-queue"] = "backfill"
        rec = Record.load(ws)
        rec.start_round("requeue", {"from": prev, "backfill": bool(args.backfill)})
        rec.save()
        write_meta(ws, updates, removes=() if args.backfill else ("distill-queue",))
    print("%s: %s -> distill-pending%s" % (ws.rel, prev, " (backfill)" if args.backfill else ""))
    return EXIT_OK


def cmd_complete(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    with Mutex(vault, ws.id):
        require_status(ws, ("distill-pending",), "complete")
        rec = Record.load(ws)
        failures, totals = verify(ws, rec)
        if failures:
            print("complete refused: %s stays distill-pending" % ws.rel, file=sys.stderr)
            for f in failures:
                print("  - " + f, file=sys.stderr)
            return EXIT_ERROR
        ts = iso(now())
        rec.append({"event": "complete", "at": ts, "totals": totals})
        rec.save()
        write_meta(ws, {"status": "completed", "distilled": ts}, removes=("distill-queue",))
        append_processed(ws, [f.get("path") for f in rec.events("file")])
    print("%s: distill-pending -> completed (%s)" % (ws.rel, format_totals(totals)))
    return EXIT_OK


def append_processed(ws, names):
    path = os.path.join(ws.dir, ".processed")
    existing = []
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            existing = [l.rstrip("\n") for l in fh if l.strip()]
    have = set(l.split(":", 1)[0] for l in existing)
    add = [n for n in names if n and n not in have]
    if add:
        atomic_write(path, "\n".join(existing + add) + "\n")


def format_totals(t):
    keys = ["candidates", "created", "updated", "skipped", "without_outcome"]
    return ", ".join("%s %s" % (k.replace("_", " "), t.get(k, 0)) for k in keys)


def cmd_snooze(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    if not DATE_RE.match(args.until or ""):
        raise RillError("--until must be YYYY-MM-DD")
    try:
        _dt.date.fromisoformat(args.until)
    except ValueError:
        raise RillError("--until is not a valid date: %s" % args.until)
    if not (args.reason or "").strip():
        raise RillError("--reason is required (what the workspace is waiting for)")
    with Mutex(vault, ws.id):
        require_status(ws, ("active",), "snooze")
        write_meta(ws, {"snooze-until": args.until, "snooze-reason": args.reason.strip()})
    print("%s: snoozed until %s" % (ws.rel, args.until))
    return EXIT_OK


def cmd_unsnooze(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    with Mutex(vault, ws.id):
        require_status(ws, ("active",), "unsnooze")
        write_meta(ws, {}, removes=("snooze-until", "snooze-reason"))
    print("%s: snooze cleared" % ws.rel)
    return EXIT_OK


def cmd_verify(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    failures, totals = verify(ws)
    if args.json:
        print(json.dumps({"workspace": ws.id, "ok": not failures, "failures": failures, "totals": totals}, ensure_ascii=False))
    else:
        if failures:
            print("%s: verify FAILED" % ws.rel)
            for f in failures:
                print("  - " + f)
        else:
            print("%s: verify ok (%s)" % (ws.rel, format_totals(totals)))
    return EXIT_ERROR if failures else EXIT_OK


# --------------------------------------------------------------------------
# commands: distill record


def require_open_run(rec, action):
    if not rec.rounds:
        raise RillError("%s refused: no distill round (workspace was never closed)" % action)
    if rec.open_run() is None:
        raise RillError("%s refused: no run in progress -- call `rill workspace distill begin` first" % action)


def cmd_begin(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    with Mutex(vault, ws.id):
        require_status(ws, ("distill-pending",), "distill begin")
        rec = Record.load(ws)
        if not rec.rounds:
            rec.start_round("adopted", {"from": "distill-pending"})
        lock = read_lock(ws)
        if lock is not None:
            age = lock_age_hours(lock)
            if age < args.stale_hours:
                raise RillError(
                    "distill begin refused: run %s holds the lock since %s" % (lock.get("run"), lock.get("started")),
                    EXIT_LOCKED,
                )
        open_run = rec.open_run()
        ts = iso(now())
        if open_run is not None:
            rec.append({
                "event": "run-end", "run": open_run["run"], "at": ts, "result": "abandoned",
                "reason": "stale lock or crashed run", "progress": rec.progress_since(open_run["run"]),
            })
        run_no = rec.next_run_number()
        rec.append({"event": "run-start", "run": run_no, "at": ts, "mode": args.mode})
        rec.save()
        atomic_write(ws.lock, json.dumps({"pid": os.getppid(), "started": ts, "run": run_no}) + "\n")
    print(run_no)
    return EXIT_OK


def cmd_end(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    if args.result not in ("completed", "failed", "interrupted", "deferred"):
        raise RillError("--result must be completed, failed, interrupted, or deferred")
    with Mutex(vault, ws.id):
        rec = Record.load(ws)
        require_open_run(rec, "distill end")
        run = rec.open_run()
        if args.run != run["run"]:
            raise RillError(
                "distill end refused: run %d is not the open run (%d) -- it was abandoned and taken over"
                % (args.run, run["run"])
            )
        ev = {"event": "run-end", "run": run["run"], "at": iso(now()), "result": args.result,
              "progress": rec.progress_since(run["run"])}
        if args.reason:
            ev["reason"] = args.reason
        rec.append(ev)
        rec.save()
        try:
            os.unlink(ws.lock)
        except OSError as e:
            if e.errno != errno.ENOENT:
                raise
    print("%s: run %d ended (%s, progress %d)" % (ws.rel, ev["run"], ev["result"], ev["progress"]))
    return EXIT_OK


def cmd_analysis(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    try:
        with open(args.file, encoding="utf-8") as fh:
            data = json.load(fh)
    except (IOError, OSError) as e:
        raise RillError("cannot read analysis file: %s" % e)
    except ValueError as e:
        raise RillError("analysis file is not valid JSON: %s" % e)
    with Mutex(vault, ws.id):
        rec = Record.load(ws)
        require_open_run(rec, "distill analysis")
        if rec.analysis_complete():
            raise RillError("distill analysis refused: this round already has a complete analysis; resume the pending candidates instead")
        files, cands, errors = validate_analysis(ws, data)
        if errors:
            print("distill analysis refused (%d problem(s)); fix the analysis and submit again:" % len(errors), file=sys.stderr)
            for e in errors:
                print("  - " + e, file=sys.stderr)
            return EXIT_ERROR
        ts = iso(now())
        evs = []
        for f in files:
            evs.append(dict({"event": "file"}, **f))
        for c in cands:
            evs.append(dict({"event": "candidate"}, **c))
        for ia in data.get("invalidated_approaches") or []:
            if isinstance(ia, dict):
                evs.append(dict({"event": "invalidated"}, **ia))
        evs.append({"event": "analysis-complete", "at": ts, "files": len(files), "candidates": len(cands)})
        rec.append(*evs)
        rec.save()
    print("%s: analysis recorded (%d files, %d candidates)" % (ws.rel, len(files), len(cands)))
    return EXIT_OK


def validate_analysis(ws, data):
    errors = []
    if not isinstance(data, dict):
        return [], [], ["top level must be an object with `files` and `candidates`"]
    raw_files = data.get("files")
    raw_cands = data.get("candidates")
    if not isinstance(raw_files, list):
        errors.append("`files` must be a list")
        raw_files = []
    if not isinstance(raw_cands, list):
        errors.append("`candidates` must be a list")
        raw_cands = []
    files = []
    seen = set()
    for i, f in enumerate(raw_files):
        if isinstance(f, str):
            f = {"path": f}
        if not isinstance(f, dict) or not f.get("path"):
            errors.append("files[%d]: needs a `path`" % i)
            continue
        p = normalize_ws_path(ws, f["path"])
        if p in seen:
            errors.append("files: %s listed twice" % p)
            continue
        seen.add(p)
        entry = {"path": p}
        if (f.get("note") or "").strip():
            entry["note"] = f["note"].strip()
        files.append(entry)
    actual = set(coverage_files(ws))
    missing = sorted(actual - seen)
    extra = sorted(seen - actual)
    if missing:
        errors.append("files not accounted for (read them and list them): %s" % ", ".join(missing))
    if extra:
        errors.append("files listed that are not in the coverage set: %s" % ", ".join(extra))
    cands = []
    cids = set()
    sources = {}
    for i, c in enumerate(raw_cands):
        if not isinstance(c, dict):
            errors.append("candidates[%d]: must be an object" % i)
            continue
        cid = str(c.get("id") or "")
        if not CID_RE.match(cid):
            errors.append("candidates[%d]: bad or missing id %r" % (i, cid))
            continue
        if cid in cids:
            errors.append("candidate id %s used twice" % cid)
            continue
        cids.add(cid)
        src = normalize_ws_path(ws, c.get("source") or "")
        if src not in seen:
            errors.append("%s: source %r is not one of the listed files" % (cid, c.get("source")))
        if c.get("type") not in NOTE_TYPES:
            errors.append("%s: type must be one of %s" % (cid, ", ".join(NOTE_TYPES)))
        if not SLUG_RE.match(str(c.get("slug") or "")):
            errors.append("%s: slug must be kebab-case" % cid)
        entry = dict(c)
        entry["id"] = cid
        entry["source"] = src
        cands.append(entry)
        sources[src] = sources.get(src, 0) + 1
    for f in files:
        if not sources.get(f["path"]) and not f.get("note"):
            errors.append("%s: no candidates -- add a `note` saying why this file yields none" % f["path"])
    return files, cands, errors


def cmd_outcome(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    status = args.status
    ev = {"event": "outcome", "id": args.cid, "status": status}
    if status in ("created", "updated"):
        if not args.path:
            raise RillError("--path is required for %s" % status)
        ev["path"] = args.path
    elif status == "skipped":
        if args.label not in SKIP_LABELS:
            raise RillError("--label must be one of: %s" % ", ".join(SKIP_LABELS))
        if args.label == "USER_DECLINED" and os.environ.get("RILL_DISTILL_UNATTENDED") == "1":
            raise RillError("USER_DECLINED is not allowed in an unattended run")
        reason = (args.reason or "").strip()
        if not reason:
            raise RillError("--reason is required for skipped")
        low = reason.lower()
        for bad in FORBIDDEN_REASONS:
            if bad in low:
                raise RillError("forbidden skip reason (%r) -- distill the candidate or use a real label" % bad)
        ev["label"] = args.label
        ev["reason"] = reason
        if args.label == "EVERGREEN_DUPLICATE":
            if not args.path:
                raise RillError("--path (the existing note) is required for EVERGREEN_DUPLICATE")
            ev["path"] = args.path
        if args.label == "MERGED_INTO_OTHER":
            if not args.into:
                raise RillError("--into (the candidate id) is required for MERGED_INTO_OTHER")
            ev["into"] = args.into
        if args.ref:
            ev["ref"] = args.ref
    else:
        raise RillError("--status must be created, updated, or skipped")
    with Mutex(vault, ws.id):
        rec = Record.load(ws)
        require_open_run(rec, "distill outcome")
        if not rec.analysis_complete():
            raise RillError("distill outcome refused: the analysis is not recorded yet")
        run_mode = (rec.open_run() or {}).get("start", {}).get("mode")
        if ev.get("label") == "USER_DECLINED" and run_mode == "unattended":
            raise RillError("USER_DECLINED is not allowed in an unattended run")
        ids = [c.get("id") for c in rec.candidates()]
        if args.cid not in ids:
            raise RillError("distill outcome refused: unknown candidate %s" % args.cid)
        if args.amend:
            if args.cid not in rec.outcome_map():
                raise RillError("distill outcome refused: --amend but candidate %s has no outcome yet" % args.cid)
            ev["amend"] = True
        elif args.cid in rec.outcome_map():
            raise RillError("distill outcome refused: candidate %s already has an outcome (use --amend to supersede it)" % args.cid)
        if args.status == "skipped" and args.label == "MERGED_INTO_OTHER" and args.into == args.cid:
            raise RillError("a candidate cannot be merged into itself")
        problems = check_outcome(ws, ev, ids, set(ids))  # merged-target status is checked at verify
        if problems:
            raise RillError("; ".join(problems))
        ev["at"] = iso(now())
        rec.append(ev)
        rec.save()
    print("%s: %s %s" % (ws.rel, args.cid, status if status != "skipped" else "skipped " + args.label))
    return EXIT_OK


def cmd_summary(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    if not os.path.exists(ws.summary):
        text = "---\ncreated: %s\ntype: summary\ntopic: %s\n---\n" % (iso(now()), ws.id)
        with Mutex(vault, ws.id):
            if not os.path.exists(ws.summary):
                atomic_write(ws.summary, text)
    print("%s/%s" % (ws.rel, SUMMARY_NAME))
    return EXIT_OK


def cmd_show(vault, args):
    ws = resolve_workspace(vault, args.workspace)
    rec = Record.load(ws)
    st = current_status(ws)
    lock = read_lock(ws)
    info = {
        "workspace": ws.id,
        "status": st,
        "round": len(rec.rounds),
        "analysis_complete": rec.analysis_complete() if rec.rounds else False,
        "candidates": len(rec.candidates()) if rec.rounds else 0,
        "outcomes": len(rec.effective_outcomes()) if rec.rounds else 0,
        "pending": [dict(c, source_path="workspace/%s/%s" % (ws.id, c.get("source"))) for c in rec.pending_candidates()] if rec.rounds else [],
        "open_run": (rec.open_run() or {}).get("run") if rec.rounds else None,
        "no_progress_runs": rec.consecutive_no_progress(),
        "lock": lock,
        "coverage": coverage_files(ws),
        "hint": meta_get(ws, "distill-hint"),
    }
    if rec.rounds and rec.analysis_complete():
        info["invalidated"] = rec.events("invalidated")
    if args.json:
        print(json.dumps(info, ensure_ascii=False, indent=2))
        return EXIT_OK
    print("%s  status=%s  round=%d" % (ws.rel, st, info["round"]))
    if rec.rounds:
        for line in rec.summary_lines()[2:]:
            print(line)
        if info["pending"]:
            print("- Pending: " + ", ".join(c.get("id") for c in info["pending"]))
    if lock:
        print("- Lock: run %s since %s" % (lock.get("run"), lock.get("started")))
    return EXIT_OK


# --------------------------------------------------------------------------
# commands: vault-wide


def list_workspaces(vault):
    root = os.path.join(vault, "workspace")
    out = []
    missing = []
    if not os.path.isdir(root):
        return out, missing
    for name in sorted(os.listdir(root)):
        d = os.path.join(root, name)
        if name.startswith(".") or not os.path.isdir(d):
            continue
        if not any(os.path.isfile(os.path.join(d, m)) for m in META_NAMES):
            missing.append(name)
            continue
        out.append(Workspace(vault, name))
    return out, missing


def ws_info(ws):
    fm, _ = read_meta(ws)
    return {
        "id": ws.id,
        "status": (fm_get(fm, "status") or "").strip(),
        "created": fm_get(fm, "created") or "",
        "closed": fm_get(fm, "closed") or "",
        "queue": fm_get(fm, "distill-queue") or "normal",
        "snooze_until": fm_get(fm, "snooze-until") or "",
        "snooze_reason": fm_get(fm, "snooze-reason") or "",
    }


def queue_entries(vault, stale_hours):
    entries = []
    workspaces, _ = list_workspaces(vault)
    for ws in workspaces:
        info = ws_info(ws)
        if info["status"] != "distill-pending":
            continue
        try:
            rec = Record.load(ws)
            stuck = rec.consecutive_no_progress() >= STUCK_RUNS
            runs = len(rec.all_runs())
            corrupted = False
        except RillError:
            stuck, runs, corrupted = True, 0, True
        lock = read_lock(ws)
        size = 0
        for rel in coverage_files(ws):
            try:
                size += os.path.getsize(os.path.join(ws.dir, rel))
            except OSError:
                pass
        entries.append({
            "id": ws.id,
            "tier": "backfill" if info["queue"] == "backfill" else "normal",
            "closed": info["closed"],
            "created": info["created"],
            "has_summary": os.path.isfile(ws.summary),
            "locked": lock is not None and lock_age_hours(lock) < stale_hours,
            "stuck": stuck,
            "corrupted": corrupted,
            "runs": runs,
            "bytes": size,
        })

    def key(e):
        if e["tier"] == "normal":
            return (0, 0, e["closed"] or e["created"], e["id"])
        return (1, 1 if e["has_summary"] else 0, e["created"], e["id"])

    entries.sort(key=key)
    return entries


def cmd_queue(vault, args):
    entries = queue_entries(vault, args.stale_hours)
    if args.next:
        for e in entries:
            if not e["locked"] and not e["stuck"]:
                print(e["id"])
                return EXIT_OK
        return EXIT_ERROR
    if args.json:
        print(json.dumps(entries, ensure_ascii=False, indent=2))
        return EXIT_OK
    if not entries:
        print("distill queue is empty")
        return EXIT_OK
    for i, e in enumerate(entries, 1):
        flags = [f for f in ("locked", "stuck", "corrupted") if e[f]]
        print("%3d. [%s] %s%s" % (i, e["tier"], e["id"], ("  (" + ", ".join(flags) + ")") if flags else ""))
    return EXIT_OK


def recently_touched(vault, days):
    try:
        out = subprocess.run(
            ["git", "-C", vault, "log", "--since=%d.days" % days, "--name-only", "--format=", "--", "workspace/"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True, timeout=60,
        )
        if out.returncode != 0:
            return None
    except (OSError, subprocess.SubprocessError):
        return None
    touched = set()
    for line in out.stdout.splitlines():
        parts = line.split("/")
        if len(parts) >= 2 and parts[0] == "workspace":
            touched.add(parts[1])
    # uncommitted edits count as activity too
    try:
        st = subprocess.run(
            ["git", "-C", vault, "status", "--porcelain", "--", "workspace/"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True, timeout=60,
        )
        for line in st.stdout.splitlines():
            parts = line[3:].strip().strip('"').split("/")
            if len(parts) >= 2 and parts[0] == "workspace":
                touched.add(parts[1])
    except (OSError, subprocess.SubprocessError):
        pass
    return touched


def cmd_check(vault, args):
    workspaces, missing_meta = list_workspaces(vault)
    today = now().date()
    report = {
        "invalid_status": [],
        "legacy_on_hold": [],
        "completed_failing_verify": [],
        "completed_without_record": [],
        "stale_locks": [],
        "stuck": [],
        "snooze_expired": [],
        "idle_active": [],
        "missing_meta": missing_meta,
        "counts": {},
        "queue": {"normal": 0, "backfill": 0},
    }
    touched = recently_touched(vault, args.idle_days) if args.idle_days > 0 else set()
    for ws in workspaces:
        try:
            info = ws_info(ws)
        except RillError as e:
            report["invalid_status"].append({"id": ws.id, "status": "(unreadable: %s)" % e})
            continue
        st = info["status"]
        report["counts"][st] = report["counts"].get(st, 0) + 1
        if st in LEGACY_STATUS:
            report["legacy_on_hold"].append(ws.id)
            continue
        if st not in STATUS_VALUES:
            report["invalid_status"].append({"id": ws.id, "status": st})
            continue
        lock = read_lock(ws)
        if lock is not None and lock_age_hours(lock) >= args.stale_hours:
            report["stale_locks"].append({"id": ws.id, "started": lock.get("started")})
        if st == "completed":
            if not os.path.exists(ws.record):
                report["completed_without_record"].append(ws.id)
                continue
            failures, _ = verify(ws)
            if failures:
                report["completed_failing_verify"].append({"id": ws.id, "failures": failures})
        elif st == "distill-pending":
            report["queue"]["backfill" if info["queue"] == "backfill" else "normal"] += 1
            try:
                if Record.load(ws).consecutive_no_progress() >= STUCK_RUNS:
                    report["stuck"].append(ws.id)
            except RillError as e:
                report["stuck"].append(ws.id + " (" + str(e) + ")")
        elif st == "active":
            until = info["snooze_until"]
            if until:
                try:
                    if _dt.date.fromisoformat(until) <= today:
                        report["snooze_expired"].append({"id": ws.id, "until": until, "reason": info["snooze_reason"]})
                    continue
                except ValueError:
                    report["invalid_status"].append({"id": ws.id, "status": "active (bad snooze-until %r)" % until})
                    continue
            if touched is not None and args.idle_days > 0 and ws.id not in touched:
                report["idle_active"].append(ws.id)
    violations = (
        len(report["invalid_status"]) + len(report["completed_failing_verify"]) + len(report["stale_locks"])
        + len(report["stuck"]) + len(report["missing_meta"])
    )
    report["violations"] = violations
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print_check(report, args)
    return EXIT_ERROR if violations else EXIT_OK


def print_check(r, args):
    c = r["counts"]
    print("Workspaces: " + ", ".join("%s %d" % (k, c[k]) for k in sorted(c)))
    print("Distill queue: %d normal, %d backfill" % (r["queue"]["normal"], r["queue"]["backfill"]))
    sections = [
        ("Invalid status", ["%s (%s)" % (x["id"], x["status"]) for x in r["invalid_status"]]),
        ("Completed but failing verify", ["%s: %s" % (x["id"], "; ".join(x["failures"])) for x in r["completed_failing_verify"]]),
        ("Stale distill locks", ["%s (since %s)" % (x["id"], x["started"]) for x in r["stale_locks"]]),
        ("Stuck in the queue (%d runs without progress)" % STUCK_RUNS, r["stuck"]),
        ("Missing %s" % META_NAME, r["missing_meta"]),
        ("Legacy on-hold (migrate with close or reopen)", r["legacy_on_hold"]),
        ("Completed without a distill record (legacy; requeue --backfill)", r["completed_without_record"]),
        ("Snooze date reached", ["%s (%s: %s)" % (x["id"], x["until"], x["reason"]) for x in r["snooze_expired"]]),
        ("Active with no activity in %d days and no snooze" % args.idle_days, r["idle_active"]),
    ]
    for title, items in sections:
        if items:
            print("")
            print("%s: %d" % (title, len(items)))
            for it in items:
                print("  - " + it)
    print("")
    print("Violations: %d" % r["violations"])


# --------------------------------------------------------------------------
# argument parsing


def build_parser():
    p = argparse.ArgumentParser(prog="rill workspace", description="Workspace state machine and distill record.")
    sub = p.add_subparsers(dest="cmd")

    def ws(sp):
        sp.add_argument("workspace", help="workspace id or path")
        return sp

    sp = ws(sub.add_parser("close", help="active -> distill-pending"))
    sp.add_argument("--kind", help="|".join(CLOSE_KINDS))
    sp.add_argument("--hint", help="|".join(DISTILL_HINTS))
    sp.set_defaults(fn=cmd_close)
    sp = ws(sub.add_parser("reopen", help="distill-pending|completed -> active"))
    sp.set_defaults(fn=cmd_reopen)
    sp = ws(sub.add_parser("requeue", help="completed -> distill-pending"))
    sp.add_argument("--backfill", action="store_true")
    sp.set_defaults(fn=cmd_requeue)
    sp = ws(sub.add_parser("complete", help="distill-pending -> completed, only if verify passes"))
    sp.set_defaults(fn=cmd_complete)
    sp = ws(sub.add_parser("snooze", help="active: set snooze-until + snooze-reason"))
    sp.add_argument("--until", required=True)
    sp.add_argument("--reason", required=True)
    sp.set_defaults(fn=cmd_snooze)
    sp = ws(sub.add_parser("unsnooze", help="active: clear snooze fields"))
    sp.set_defaults(fn=cmd_unsnooze)
    sp = ws(sub.add_parser("verify", help="check the latest distill round"))
    sp.add_argument("--json", action="store_true")
    sp.set_defaults(fn=cmd_verify)
    sp = sub.add_parser("queue", help="list distill-pending workspaces in queue order")
    sp.add_argument("--json", action="store_true")
    sp.add_argument("--next", action="store_true", help="print the first runnable id (exit 1 if none)")
    sp.add_argument("--stale-hours", type=float, default=DEFAULT_STALE_HOURS)
    sp.set_defaults(fn=cmd_queue)
    sp = sub.add_parser("check", help="vault-wide invariant check (no AI)")
    sp.add_argument("--json", action="store_true")
    sp.add_argument("--idle-days", type=int, default=14)
    sp.add_argument("--stale-hours", type=float, default=DEFAULT_STALE_HOURS)
    sp.set_defaults(fn=cmd_check)

    d = sub.add_parser("distill", help="distill record subcommands")
    dsub = d.add_subparsers(dest="dcmd")
    sp = ws(dsub.add_parser("begin", help="take the run lock and record a run start"))
    sp.add_argument("--stale-hours", type=float, default=DEFAULT_STALE_HOURS)
    sp.add_argument("--mode", default="interactive", choices=("interactive", "unattended"))
    sp.set_defaults(fn=cmd_begin)
    sp = ws(dsub.add_parser("analysis", help="record the analysis (JSON file)"))
    sp.add_argument("--file", required=True)
    sp.set_defaults(fn=cmd_analysis)
    sp = ws(dsub.add_parser("outcome", help="record one candidate's outcome"))
    sp.add_argument("--cid", required=True)
    sp.add_argument("--status", required=True, choices=("created", "updated", "skipped"))
    sp.add_argument("--path")
    sp.add_argument("--label")
    sp.add_argument("--reason")
    sp.add_argument("--into")
    sp.add_argument("--ref")
    sp.add_argument("--amend", action="store_true", help="supersede this candidate's earlier outcome")
    sp.set_defaults(fn=cmd_outcome)
    sp = ws(dsub.add_parser("summary", help="create _summary.md (if missing) and print its path"))
    sp.set_defaults(fn=cmd_summary)
    sp = ws(dsub.add_parser("end", help="record the run end and release the lock"))
    sp.add_argument("--run", type=int, required=True, help="the run number printed by `distill begin`")
    sp.add_argument("--result", required=True)
    sp.add_argument("--reason")
    sp.set_defaults(fn=cmd_end)
    sp = ws(dsub.add_parser("show", help="summarize the latest round"))
    sp.add_argument("--json", action="store_true")
    sp.set_defaults(fn=cmd_show)
    return p, d


def main(argv):
    parser, dparser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "cmd", None):
        parser.print_help()
        return EXIT_ERROR
    if args.cmd == "distill" and not getattr(args, "dcmd", None):
        dparser.print_help()
        return EXIT_ERROR
    try:
        vault = vault_root()
        return args.fn(vault, args)
    except RillError as e:
        print("Error: %s" % e, file=sys.stderr)
        return e.code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
