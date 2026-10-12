#!/bin/bash
# test/cli/test-fetch-tweet-exit-codes.sh — Hermetic tests for the exit-code
# contract of plugins/twitter/fetch-tweet.sh.
#
# /distill and /clip-tweet branch on the exit code: 4 (tweet unavailable) marks
# the inbox file `skipped` so it stops being re-queued, while 2 (transient
# failure) leaves it unprocessed for the next run. Getting this wrong either
# strands a dead tweet in the unprocessed queue forever or writes off a live
# one, so the boundary is frozen here.
#
# Regressions frozen here:
#   - exit 4 requires BOTH sources to explicitly deny the tweet (FixTweet code
#     404/401 AND oEmbed HTTP 404/403).
#   - a timeout, empty response, or server error on either side stays exit 2,
#     including a transfer that fails AFTER a 404/403 status line arrived
#     (curl still reports that status through -w, but exits non-zero).
#   - the oEmbed fallback still succeeds (exit 0) when FixTweet denies the
#     tweet but oEmbed returns it.
#
# curl is stubbed via PATH, so no network is used.
#
# Usage: bash test/cli/test-fetch-tweet-exit-codes.sh
# Requires: bash, jq. No claude CLI, no network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FETCH="$REPO_ROOT/plugins/twitter/fetch-tweet.sh"

# shellcheck source=test/assertions/lib.sh
source "$SCRIPT_DIR/../assertions/lib.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# --- curl stub ---------------------------------------------------------------
# Driven by env vars:
#   FAKE_FX_BODY        body returned for the FixTweet API URL
#   FAKE_FX_FAIL=1      simulate a FixTweet network failure (no body, exit 28)
#   FAKE_FX_RC          exit code after printing FAKE_FX_BODY (default 0)
#   FAKE_OEMBED_BODY    body returned for the oEmbed URL
#   FAKE_OEMBED_STATUS  HTTP status reported through -w for the oEmbed URL
#   FAKE_OEMBED_FAIL=1  simulate an oEmbed network failure (status 000, exit 28)
#   FAKE_OEMBED_RC      exit code after printing body + status (default 0)
mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<'STUB'
#!/bin/bash
url=""
want_status=0
while [ $# -gt 0 ]; do
    case "$1" in
        -w) want_status=1; shift ;;
        http*) url="$1" ;;
    esac
    shift || true
done
case "$url" in
    *api.fxtwitter.com*)
        [ "${FAKE_FX_FAIL:-0}" = "1" ] && exit 28
        printf '%s' "${FAKE_FX_BODY:-}"
        exit "${FAKE_FX_RC:-0}"
        ;;
    *publish.twitter.com*)
        if [ "${FAKE_OEMBED_FAIL:-0}" = "1" ]; then
            [ "$want_status" = "1" ] && printf '\n000'
            exit 28
        fi
        printf '%s' "${FAKE_OEMBED_BODY:-}"
        [ "$want_status" = "1" ] && printf '\n%s' "${FAKE_OEMBED_STATUS:-200}"
        exit "${FAKE_OEMBED_RC:-0}"
        ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/curl"

URL="https://x.com/example_user/status/1000000000000000001"

FX_OK='{"code":200,"message":"OK","tweet":{"author":{"screen_name":"example_user","name":"Example User","followers":10},"created_at":"Mon Jan 01 00:00:00 +0000 2024","likes":4,"retweets":1,"bookmarks":2,"views":100,"lang":"en","text":"hello world","raw_text":{"facets":[]}}}'
FX_NOT_FOUND='{"code":404,"message":"NOT_FOUND","tweet":null}'
FX_PRIVATE='{"code":401,"message":"PRIVATE_TWEET","tweet":null}'
FX_API_FAIL='{"code":500,"message":"API_FAIL","tweet":null}'
OEMBED_OK='{"html":"<blockquote><p lang=\"en\">hello from oembed</p></blockquote>","author_name":"Example User","author_url":"https://twitter.com/example_user"}'
OEMBED_HTML_404='<!DOCTYPE html><html><head><title>Not found</title></head></html>'

# run_fetch <args...> — runs the script under the stubbed curl with the FAKE_*
# variables currently exported; sets OUT (stdout), ERR (stderr), RC (exit code).
run_fetch() {
    local rc=0
    OUT="$(PATH="$WORK/bin:$PATH" bash "$FETCH" "$@" 2>"$WORK/stderr")" || rc=$?
    ERR="$(cat "$WORK/stderr")"
    RC="$rc"
}

reset_fakes() {
    unset FAKE_FX_BODY FAKE_FX_FAIL FAKE_FX_RC
    unset FAKE_OEMBED_BODY FAKE_OEMBED_STATUS FAKE_OEMBED_FAIL FAKE_OEMBED_RC
}

echo "=== exit 0: FixTweet success ==="
reset_fakes
export FAKE_FX_BODY="$FX_OK"
run_fetch "$URL"
assert_eq "$RC" "0" "FixTweet 200 exits 0"
assert_true '[[ "$OUT" == *"tweet-author: \"@example_user\""* ]]' "YAML carries the author"
assert_true '[[ "$OUT" == *"source: fxtwitter"* ]]' "YAML is marked as fxtwitter-sourced"

echo "=== exit 0: oEmbed fallback still works when FixTweet denies ==="
reset_fakes
export FAKE_FX_BODY="$FX_NOT_FOUND" FAKE_OEMBED_BODY="$OEMBED_OK" FAKE_OEMBED_STATUS="200"
run_fetch "$URL"
assert_eq "$RC" "0" "FixTweet 404 + oEmbed 200 exits 0"
assert_true '[[ "$OUT" == *"source: oembed"* ]]' "YAML is marked as oembed-sourced"
assert_true '[[ "$OUT" == *"hello from oembed"* ]]' "oEmbed text survives the status-line split"

echo "=== exit 4: both sources deny the tweet ==="
reset_fakes
export FAKE_FX_BODY="$FX_NOT_FOUND" FAKE_OEMBED_BODY="$OEMBED_HTML_404" FAKE_OEMBED_STATUS="404"
run_fetch "$URL"
assert_eq "$RC" "4" "deleted tweet (FixTweet 404 + oEmbed 404) exits 4"
assert_eq "$OUT" "" "no YAML on stdout for an unavailable tweet"
assert_true '[[ "$ERR" == *"Tweet unavailable"* ]]' "stderr names the unavailable condition"

reset_fakes
export FAKE_FX_BODY="$FX_PRIVATE" FAKE_OEMBED_BODY="" FAKE_OEMBED_STATUS="403"
run_fetch "$URL"
assert_eq "$RC" "4" "private tweet (FixTweet 401 + oEmbed 403) exits 4"

echo "=== exit 2: transient failures are never written off ==="
reset_fakes
export FAKE_FX_FAIL=1 FAKE_OEMBED_FAIL=1
run_fetch "$URL"
assert_eq "$RC" "2" "both sources unreachable exits 2"

reset_fakes
export FAKE_FX_BODY="$FX_NOT_FOUND" FAKE_OEMBED_FAIL=1
run_fetch "$URL"
assert_eq "$RC" "2" "FixTweet 404 alone (oEmbed unreachable) exits 2"

reset_fakes
export FAKE_FX_FAIL=1 FAKE_OEMBED_BODY="$OEMBED_HTML_404" FAKE_OEMBED_STATUS="404"
run_fetch "$URL"
assert_eq "$RC" "2" "oEmbed 404 alone (FixTweet unreachable) exits 2"

reset_fakes
export FAKE_FX_BODY="$FX_API_FAIL" FAKE_OEMBED_BODY="$OEMBED_HTML_404" FAKE_OEMBED_STATUS="404"
run_fetch "$URL"
assert_eq "$RC" "2" "FixTweet 500 + oEmbed 404 exits 2"

reset_fakes
export FAKE_FX_BODY="$FX_NOT_FOUND" FAKE_OEMBED_BODY="" FAKE_OEMBED_STATUS="503"
run_fetch "$URL"
assert_eq "$RC" "2" "FixTweet 404 + oEmbed 503 exits 2"
assert_true '[[ "$ERR" != *"Tweet unavailable"* ]]' "transient failure is not reported as unavailable"

reset_fakes
export FAKE_FX_BODY="$FX_NOT_FOUND" FAKE_OEMBED_BODY="" FAKE_OEMBED_STATUS="404" FAKE_OEMBED_RC=28
run_fetch "$URL"
assert_eq "$RC" "2" "oEmbed 404 status on a timed-out transfer exits 2"

reset_fakes
export FAKE_FX_BODY="$FX_NOT_FOUND" FAKE_FX_RC=28 FAKE_OEMBED_BODY="$OEMBED_HTML_404" FAKE_OEMBED_STATUS="404"
run_fetch "$URL"
assert_eq "$RC" "2" "FixTweet 404 body on a failed transfer exits 2"

echo "=== exit 1: bad arguments ==="
reset_fakes
run_fetch "https://example.com/not-a-tweet"
assert_eq "$RC" "1" "non-tweet URL exits 1"

echo ""
report_results
