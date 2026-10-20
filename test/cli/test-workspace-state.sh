#!/bin/bash
# test/cli/test-workspace-state.sh — Pure-shell tests for `rill workspace`
# (lib/workspace/rill_workspace.py): the workspace state machine and the
# distill record that gates `completed`.
#
# Frozen here:
#   - every transition outside the table is refused (complete from active,
#     requeue from distill-pending, ...); legacy on-hold is accepted only as
#     the source of close / reopen
#   - `complete` writes completed only when verify passes; each verify check
#     fails on its own (no analysis marker, coverage gap, file without
#     candidates or note, candidate without outcome, missing note, note
#     without a source in the workspace, missing _summary.md)
#   - record writes need an open run; one outcome per candidate; forbidden
#     skip reasons and USER_DECLINED in unattended runs are refused
#   - the run lock: a fresh lock refuses begin/reopen (exit 3); a stale lock
#     is recorded as an abandoned run and taken over
#   - concurrent outcome writers all land (flock + atomic replace)
#   - queue order: normal tier by closed time, then backfill with
#     no-_summary.md first
#
# Usage: bash test/cli/test-workspace-state.sh
# Requires: bash, python3 (>= 3.9), git. No claude CLI, no network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RILL="$REPO_ROOT/bin/rill"

# shellcheck source=test/assertions/lib.sh
source "$SCRIPT_DIR/../assertions/lib.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

VAULT="$WORK/vault"
mkdir -p "$VAULT/.rill" "$VAULT/workspace" "$VAULT/knowledge/notes"
echo "1" > "$VAULT/.rill/version"
git -C "$VAULT" init -q
git -C "$VAULT" config user.email test@localhost
git -C "$VAULT" config user.name test

# assert_match HAYSTACK GLOB MSG -- glob match without eval (outputs contain backticks)
assert_match() {
  local hay="$1" pat="$2" msg="$3"
  _TOTAL=$((_TOTAL + 1))
  # shellcheck disable=SC2053
  if [[ "$hay" == $pat ]]; then
    _PASS=$((_PASS + 1)); printf "  ${_GREEN}PASS${_NC}: %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1)); _FAILURES+=("$msg")
    printf "  ${_RED}FAIL${_NC}: %s\n" "$msg"; printf "    output was: %.600s\n" "$hay"
  fi
}

w() { RILL_HOME="$VAULT" RILL_SOURCE="$REPO_ROOT" "$RILL" workspace "$@"; }
# rc CMD... -> prints the exit code, never fails the script
rc() { local r=0; "$@" >/dev/null 2>&1 || r=$?; echo "$r"; }
out() { "$@" 2>&1 || true; }
status_of() { sed -n 's/^status: *//p' "$VAULT/workspace/$1/_workspace.md" | head -1; }

mkws() {
  local id="$1" st="$2"
  mkdir -p "$VAULT/workspace/$id"
  cat > "$VAULT/workspace/$id/_workspace.md" <<EOF
---
created: 2026-01-0${3:-1}T10:00+09:00
type: workspace
id: $id
name: Test $id
status: $st
tags: [testing]
---

# Test $id
EOF
}

mknote() {
  local slug="$1" src="$2"
  cat > "$VAULT/knowledge/notes/$slug.md" <<EOF
---
created: 2026-01-01T10:00+09:00
type: insight
source: $src
tags: [testing]
---

# $slug
EOF
}

# --- fixture: ws-a with every coverage case ---------------------------------
mkws ws-a active
A="$VAULT/workspace/ws-a"
mkdir -p "$A/tasks" "$A/.view"
printf -- '---\ntype: decision\n---\n# Design\n' > "$A/001-design.md"
printf '<p>derived twin</p>\n' > "$A/001-design.html"
printf -- '---\ntype: progress\n---\n# Notes\n' > "$A/002-notes.md"
printf '<p>mock</p>\n' > "$A/003-mock.html"
printf -- '---\ntype: log\n---\n# Log\n' > "$A/_log.md"
printf -- '---\ntype: task\n---\n# Sub task\n' > "$A/tasks/001-sub.md"
printf -- '# derived view\n' > "$A/.view/digest.md"

echo "=== transitions refused from the wrong state ==="
assert_eq "$(rc w complete ws-a)" "1" "complete from active is refused"
assert_eq "$(rc w requeue ws-a)" "1" "requeue from active is refused"
assert_eq "$(rc w snooze ws-a --until 2026-13-40 --reason x)" "1" "snooze with a bad date is refused"
assert_eq "$(status_of ws-a)" "active" "refusals leave status untouched"

echo "=== close ==="
assert_eq "$(rc w close ws-a --kind done --hint full)" "0" "close active -> distill-pending"
assert_eq "$(status_of ws-a)" "distill-pending" "status is distill-pending"
assert_file_contains "$A/_workspace.md" "closed: " "closed timestamp written"
assert_file_contains "$A/_workspace.md" "distill-hint: full" "hint written"
assert_file_contains "$A/_distill.md" "## Round 1" "record starts round 1"
assert_eq "$(rc w close ws-a)" "1" "close from distill-pending is refused"
assert_eq "$(rc w requeue ws-a)" "1" "requeue from distill-pending is refused"

echo "=== record writes need an open run ==="
cat > "$WORK/analysis-a.json" <<'EOF'
{"files": [
  {"path": "001-design.md"},
  {"path": "002-notes.md", "note": "progress log only"},
  {"path": "003-mock.html"},
  {"path": "_log.md", "note": "session log; decisions live in 001"},
  {"path": "_workspace.md", "note": "MOC only"},
  {"path": "tasks/001-sub.md"}
 ],
 "candidates": [
  {"id": "L1-1", "layer": 1, "slug": "design-choice", "type": "insight", "source": "workspace/ws-a/001-design.md", "rationale": "the decision"},
  {"id": "L2-1", "layer": 2, "slug": "design-principle", "type": "insight", "source": "001-design.md", "rationale": "a principle"},
  {"id": "L2-2", "layer": 2, "slug": "mock-pattern", "type": "reference", "source": "003-mock.html", "rationale": "a layout pattern"},
  {"id": "L2-3", "layer": 2, "slug": "sub-task-finding", "type": "record", "source": "tasks/001-sub.md", "rationale": "a measured fact"}
 ]}
EOF
assert_eq "$(rc w distill analysis ws-a --file "$WORK/analysis-a.json")" "1" "analysis without begin is refused"
assert_eq "$(rc w distill outcome ws-a --cid L1-1 --status skipped --label IMPLEMENTATION_DETAIL --reason x)" "1" "outcome without begin is refused"

echo "=== lock ==="
assert_eq "$(w distill begin ws-a)" "1" "begin starts run 1"
assert_file_exists "$VAULT/.rill/state/distill/ws-a.lock" "lock file written"
assert_eq "$(rc w distill begin ws-a)" "3" "second begin with a fresh lock exits 3"
assert_eq "$(rc w reopen ws-a)" "3" "reopen while locked exits 3"

echo "=== analysis validation ==="
python3 - "$WORK/analysis-a.json" "$WORK/analysis-missing.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["files"] = [f for f in d["files"] if f["path"] != "tasks/001-sub.md"]
d["candidates"] = [c for c in d["candidates"] if c["id"] != "L2-3"]
json.dump(d, open(sys.argv[2], "w"))
EOF
o="$(out w distill analysis ws-a --file "$WORK/analysis-missing.json")"
assert_match "$o" "*not accounted for*tasks/001-sub.md*" "analysis missing a coverage file is refused"
python3 - "$WORK/analysis-a.json" "$WORK/analysis-nonote.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for f in d["files"]:
    if f["path"] == "002-notes.md":
        f.pop("note")
json.dump(d, open(sys.argv[2], "w"))
EOF
o="$(out w distill analysis ws-a --file "$WORK/analysis-nonote.json")"
assert_match "$o" "*002-notes.md: no candidates*" "file without candidates and without a note is refused"
python3 - "$WORK/analysis-a.json" "$WORK/analysis-twin.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["files"].append({"path": "001-design.html", "note": "twin"})
json.dump(d, open(sys.argv[2], "w"))
EOF
o="$(out w distill analysis ws-a --file "$WORK/analysis-twin.json")"
assert_match "$o" "*not in the coverage set*001-design.html*" "derived HTML twin is not in the coverage set"
assert_eq "$(rc w distill analysis ws-a --file "$WORK/analysis-a.json")" "0" "complete analysis is recorded"
assert_eq "$(rc w distill analysis ws-a --file "$WORK/analysis-a.json")" "1" "second analysis in the same round is refused"

echo "=== complete refused until every check passes ==="
o="$(out w complete ws-a)"
assert_match "$o" "*_summary.md is missing*" "complete reports missing _summary.md"
assert_match "$o" "*without an outcome*" "complete reports candidates without outcome"
assert_eq "$(status_of ws-a)" "distill-pending" "failed complete leaves distill-pending"

echo "=== outcomes ==="
assert_eq "$(rc w distill outcome ws-a --cid L1-1 --status created --path knowledge/notes/design-choice.md)" "1" "created with a missing note is refused"
mknote unrelated "inbox/journal/x.md"
assert_eq "$(rc w distill outcome ws-a --cid L1-1 --status created --path knowledge/notes/unrelated.md)" "1" "created note without a source in the workspace is refused"
mknote design-choice "workspace/ws-a/001-design.md"
assert_eq "$(rc w distill outcome ws-a --cid L1-1 --status created --path knowledge/notes/design-choice.md)" "0" "created outcome recorded"
assert_eq "$(rc w distill outcome ws-a --cid L1-1 --status updated --path knowledge/notes/design-choice.md)" "1" "second outcome for the same candidate is refused"
assert_eq "$(rc w distill outcome ws-a --cid NOPE --status skipped --label IMPLEMENTATION_DETAIL --reason x)" "1" "outcome for an unknown candidate is refused"
assert_eq "$(rc w distill outcome ws-a --cid L2-2 --status skipped --label IMPLEMENTATION_DETAIL --reason 'to save time')" "1" "forbidden skip reason is refused"
assert_eq "$(rc env RILL_DISTILL_UNATTENDED=1 RILL_HOME="$VAULT" RILL_SOURCE="$REPO_ROOT" "$RILL" workspace distill outcome ws-a --cid L2-2 --status skipped --label USER_DECLINED --reason 'user said no')" "1" "USER_DECLINED refused in unattended runs"
assert_eq "$(rc w distill outcome ws-a --cid L2-2 --status skipped --label NOT_A_LABEL --reason x)" "1" "unknown skip label is refused"
assert_eq "$(rc w distill outcome ws-a --cid L2-2 --status updated --path workspace/ws-a/_workspace.md)" "1" "updated path outside knowledge/notes is refused"
assert_eq "$(rc w distill outcome ws-a --cid L2-2 --status skipped --label EVERGREEN_DUPLICATE --path workspace/ws-a/002-notes.md --reason dup)" "1" "duplicate path outside knowledge/notes is refused"
assert_eq "$(rc w distill outcome ws-a --cid L2-1 --status skipped --label MERGED_INTO_OTHER --into L1-1 --reason 'same point as the decision')" "0" "merged outcome recorded"
assert_eq "$(rc w distill outcome ws-a --cid L2-2 --status skipped --label IMPLEMENTATION_DETAIL --reason 'layout specific to this mock')" "0" "skip outcome recorded"

echo "=== amend supersedes an outcome ==="
assert_eq "$(rc w distill outcome ws-a --cid L2-2 --status skipped --label IMPLEMENTATION_DETAIL --reason again)" "1" "plain second outcome is refused"
assert_eq "$(rc w distill outcome ws-a --cid L2-2 --status skipped --label INTERMEDIATE_CONCLUSION --reason 'contradicted by 002' --amend)" "0" "--amend supersedes the earlier outcome"
assert_eq "$(rc w distill outcome ws-a --cid L2-3 --status skipped --label IMPLEMENTATION_DETAIL --reason x --amend)" "1" "--amend without an earlier outcome is refused"

echo "=== run end, stale lock takeover ==="
o="$(out w distill end ws-a --run 1 --result interrupted --reason test)"
assert_match "$o" "*progress*" "end records progress"
assert_file_not_exists "$VAULT/.rill/state/distill/ws-a.lock" "end releases the lock"
assert_eq "$(w distill begin ws-a)" "2" "begin starts run 2"
python3 - "$VAULT/.rill/state/distill/ws-a.lock" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["started"] = "2020-01-01T00:00+09:00"; json.dump(d, open(p, "w"))
EOF
assert_eq "$(w distill begin ws-a)" "3" "stale lock is taken over by run 3"
assert_true "grep -q '\"result\": \"abandoned\"' '$A/_distill.md'" "abandoned run recorded"
assert_eq "$(rc w distill end ws-a --run 2 --result failed)" "1" "end from the abandoned run is refused"
assert_eq "$(rc env RILL_DISTILL_RUN=2 RILL_HOME="$VAULT" RILL_SOURCE="$REPO_ROOT" "$RILL" workspace distill outcome ws-a --cid L2-3 --status skipped --label IMPLEMENTATION_DETAIL --reason x)" "1" "a worker of the abandoned run cannot write outcomes"
assert_file_exists "$VAULT/.rill/state/distill/ws-a.lock" "the new run keeps its lock"

echo "=== complete ==="
mknote sub-task-finding "workspace/ws-a/tasks/001-sub.md"
assert_eq "$(rc w distill outcome ws-a --cid L2-3 --status updated --path knowledge/notes/sub-task-finding.md)" "0" "updated outcome recorded"
o="$(out w complete ws-a)"
assert_match "$o" "*_summary.md is missing*" "summary still required"
assert_eq "$(w distill summary ws-a)" "workspace/ws-a/_summary.md" "distill summary creates _summary.md"
assert_file_contains "$A/_summary.md" "type: summary" "summary frontmatter written"
assert_eq "$(rc w complete ws-a)" "0" "complete passes once every check holds"
assert_eq "$(status_of ws-a)" "completed" "status is completed"
assert_file_contains "$A/_workspace.md" "distilled: " "distilled timestamp written"
assert_file_contains "$A/.processed" "tasks/001-sub.md" ".processed lists coverage files"
assert_eq "$(rc w distill outcome ws-a --cid L2-2 --status skipped --label IMPLEMENTATION_DETAIL --reason late --amend)" "1" "outcome refused once the workspace is completed"
w distill end ws-a --run 3 --result completed >/dev/null
assert_eq "$(rc w verify ws-a)" "0" "verify ok after completion"

echo "=== verify catches later drift ==="
mv "$VAULT/knowledge/notes/design-choice.md" "$WORK/design-choice.md"
o="$(out w verify ws-a)"
assert_match "$o" "*note does not exist*" "verify fails when a created note disappears"
assert_eq "$(rc w check --idle-days 0)" "1" "check exits 1 on a completed box failing verify"
mv "$WORK/design-choice.md" "$VAULT/knowledge/notes/design-choice.md"
printf -- '# new\n' > "$A/004-new.md"
o="$(out w verify ws-a)"
assert_match "$o" "*did not account for*004-new.md*" "verify fails on a file added after the analysis"
rm "$A/004-new.md"

echo "=== reopen and re-close start a new round ==="
assert_eq "$(rc w reopen ws-a)" "0" "reopen completed -> active"
assert_eq "$(status_of ws-a)" "active" "status active"
assert_eq "$(rc w close ws-a)" "0" "close again"
assert_file_contains "$A/_distill.md" "## Round 2" "new round started"
o="$(out w verify ws-a)"
assert_match "$o" "*analysis did not finish*" "verify judges the latest round"

echo "=== concurrent outcome writers ==="
mkws ws-b active
B="$VAULT/workspace/ws-b"
printf -- '# big\n' > "$B/001-big.md"
w close ws-b >/dev/null
w distill begin ws-b >/dev/null
python3 - "$WORK/analysis-b.json" <<'EOF'
import json, sys
c = [{"id": "C%02d" % i, "slug": "c-%d" % i, "type": "record", "source": "001-big.md"} for i in range(1, 21)]
json.dump({"files": [{"path": "001-big.md"}, {"path": "_workspace.md", "note": "MOC"}], "candidates": c}, open(sys.argv[1], "w"))
EOF
w distill analysis ws-b --file "$WORK/analysis-b.json" >/dev/null
for i in $(seq -w 1 20); do
  w distill outcome ws-b --cid "C$i" --status skipped --label IMPLEMENTATION_DETAIL --reason "internal detail $i" >/dev/null 2>&1 &
done
wait
n="$(w distill show ws-b --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["outcomes"])')"
assert_eq "$n" "20" "all 20 concurrent outcomes landed"

echo "=== unattended run refuses USER_DECLINED without the env var ==="
mkws ws-u active
printf -- '# one\n' > "$VAULT/workspace/ws-u/001-one.md"
w close ws-u >/dev/null
w distill begin ws-u --mode unattended >/dev/null
printf '%s' '{"files":[{"path":"001-one.md"},{"path":"_workspace.md","note":"MOC"}],"candidates":[{"id":"C1","slug":"one","type":"record","source":"001-one.md"}]}' > "$WORK/analysis-u.json"
w distill analysis ws-u --file "$WORK/analysis-u.json" >/dev/null
assert_eq "$(rc w distill outcome ws-u --cid C1 --status skipped --label USER_DECLINED --reason 'user said no')" "1" "USER_DECLINED refused in a run begun with --mode unattended"

echo "=== frontmatter comments and legacy metadata ==="
mkws ws-c1 active
python3 - "$VAULT/workspace/ws-c1/_workspace.md" <<'EOF'
import sys
p = sys.argv[1]
text = open(p).read().replace("status: active\n", "status: active   # active | distill-pending | completed\n")
open(p, "w").write(text)
EOF
assert_eq "$(rc w close ws-c1)" "0" "status with an end-of-line comment is read as active"
mkdir -p "$VAULT/workspace/ws-legacy"
printf -- '---\ntype: session\nstatus: active\n---\n# Legacy\n' > "$VAULT/workspace/ws-legacy/_session.md"
assert_eq "$(rc w close ws-legacy)" "0" "legacy _session.md metadata is resolved"
assert_file_contains "$VAULT/workspace/ws-legacy/_session.md" "status: distill-pending" "status written to _session.md"
assert_file_not_exists "$VAULT/workspace/ws-legacy/_workspace.md" "legacy file is not renamed"

echo "=== legacy on-hold ==="
mkws ws-d on-hold
mkws ws-e on-hold
mkws ws-f on-hold
assert_eq "$(rc w close ws-d)" "0" "on-hold -> distill-pending via close"
assert_eq "$(rc w reopen ws-e)" "0" "on-hold -> active via reopen"
assert_eq "$(rc w complete ws-f)" "1" "complete from on-hold is refused"
assert_eq "$(rc w requeue ws-f)" "1" "requeue from on-hold is refused"

echo "=== requeue + queue order ==="
mkws ws-q1 distill-pending 2
mkws ws-q2 distill-pending 3
mkws ws-q3 completed 4
mkws ws-q4 completed 5
set_closed() {
  python3 - "$VAULT/workspace/$1/_workspace.md" "$2" <<'EOF'
import sys
p, ts = sys.argv[1], sys.argv[2]
s = open(p).read().replace("status: distill-pending\n", "status: distill-pending\nclosed: %s\n" % ts, 1)
open(p, "w").write(s)
EOF
}
set_closed ws-q1 2026-03-01T02:00+00:00
set_closed ws-q2 2026-03-01T09:00+09:00
printf -- '---\ntype: summary\n---\n# Summary\n' > "$VAULT/workspace/ws-q3/_summary.md"
assert_eq "$(rc w requeue ws-q3 --backfill)" "0" "requeue completed -> distill-pending (backfill)"
assert_eq "$(rc w requeue ws-q4 --backfill)" "0" "requeue second backfill box"
assert_file_contains "$VAULT/workspace/ws-q4/_workspace.md" "distill-queue: backfill" "backfill tier recorded"
order="$(w queue --json | python3 -c 'import json,sys; print(" ".join(e["id"] for e in json.load(sys.stdin) if e["id"].startswith("ws-q")))')"
assert_eq "$order" "ws-q2 ws-q1 ws-q4 ws-q3" "normal tier by closed time (timezone-aware), then backfill without _summary.md first"

echo "=== snooze + check ==="
mkws ws-g active
assert_eq "$(rc w snooze ws-g --until 2020-01-01 --reason 'waiting for a vendor reply')" "0" "snooze recorded"
assert_file_contains "$VAULT/workspace/ws-g/_workspace.md" "snooze-until: 2020-01-01" "snooze-until written"
o="$(out w check --idle-days 0)"
assert_match "$o" "*Snooze date reached*ws-g*" "check reports a reached snooze date"
assert_eq "$(rc w snooze ws-a --until 2030-01-01 --reason x)" "1" "snooze refused when not active"
assert_eq "$(rc w unsnooze ws-g)" "0" "unsnooze"
assert_file_not_contains "$VAULT/workspace/ws-g/_workspace.md" "snooze-until" "snooze fields removed"
mkws ws-h pilot
o="$(out w check --idle-days 0)"
assert_match "$o" "*Invalid status*ws-h (pilot)*" "check reports an invalid status value"

echo ""
report_results
