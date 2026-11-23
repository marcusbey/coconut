#!/usr/bin/env bash
# digest.test.sh: `sa digest <ticket-dir>` writes <room>/<project>/digest/NNN.md (never a file in the ticket folder), and sa rebuilds it after each room-log line of the
# ticket (not in a project without a room, not with SA_NO_DIGEST=1). Every case runs on its own fixture.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
unset SA_ROLE SA_NO_DIGEST CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION
sa() { bash "$SA_UNDER_TEST" "$@"; }

F=""; D=""; T=""; LOG=""; G=""
fail() { echo "$*"; exit 1; }
drop_dir() {
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
run_case() { # run_case <name> <function>
  local rc
  F=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$F"); T="$F/demo/tickets/001-demo-ticket"; LOG="$F/decision-room/demo/LOG.md"; G="$F/decision-room/demo/digest/001.md"
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  drop_dir "$D"
}
size_of() { wc -c < "$1" | tr -d ' '; }
fresh() { # the Built: line names the log's current size
  grep -qE "^Built: [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} from $LOG at $(size_of "$LOG") bytes\$" "$G" ||
    fail "freshness: $(grep '^Built:' "$G") vs log $(size_of "$LOG") bytes"
}

c_built() {
  local o
  sa room note "$T" clerk "first note" >/dev/null || fail "note"
  rm -f "$G"
  o=$(sa digest "$T") || fail "digest failed: $o"
  [ "$o" = "$G" ] || fail "want the path printed: $o"
  [ ! -e "$T/notes" ] || fail "the digest touched the ticket folder: $(ls "$T/notes")"
  [ "$(head -1 "$G")" = '# Digest: demo#001 Demo ticket' ] || fail "title: $(head -1 "$G")"
  sed -n 3p "$G" | grep -qx 'Status: ready | Stage: -' || fail "status: $(sed -n 3p "$G")"
  fresh
  grep -q '^## Last log lines of demo#001 (1)' "$G" && grep -qF 'clerk: first note' "$G" || fail "log lines: $(cat "$G")"
  grep -q '^## Decisions on demo#001' "$G" && grep -q '^## Open questions on demo#001' "$G" || fail "sections: $(cat "$G")"
  grep -qE '^- rd\.md \([0-9]+ bytes\)$' "$G" && grep -qE '^- eval\.md \([0-9]+ bytes\)$' "$G" || fail "files: $(cat "$G")"
  ! grep -qF 'digest.md' "$G" || fail "the digest lists itself"
  [ "$(size_of "$G")" -le 3500 ] || fail "too big: $(size_of "$G")"
  ls "$T/notes" | grep -q '\.sa\.' && fail "a temp file was left: $(ls "$T/notes")"
  true
}
c_refreshed_after_stage() {
  local i
  sa stage "$T" research "start" >/dev/null || fail "stage"
  [ -f "$G" ] || fail "no digest after sa stage"
  fresh
  sed -n 3p "$G" | grep -qx 'Status: in-progress | Stage: research' || fail "status: $(sed -n 3p "$G")"
  sa stage "$T" plan "planning" >/dev/null || fail "stage 2"
  fresh
  grep -qF 'in-progress/research -> in-progress/plan: planning' "$G" || fail "the new line is missing: $(cat "$G")"
  for i in $(seq 1 14); do sa room note "$T" worker "n$i" >/dev/null; done
  grep -q '^## Last log lines of demo#001 (16, the last 12 shown)' "$G" || fail "cap: $(grep '^## Last' "$G")"
  [ "$(grep -c ' | demo#001 | ' "$G")" = 12 ] || fail "want 12 lines"
  # a line of another ticket or of the project does not touch this digest
  cp "$G" "$D/before"
  sa room note "$F/demo/tickets" clerk "project note" >/dev/null || fail "project note"
  cmp -s "$G" "$D/before" || fail "a project line rebuilt the ticket's digest"
}
c_refreshed_by_hook() {
  mkdir -p "$D/st"
  perl -MJSON::PP -e 'local $/; open my $h, "<", $ARGV[0] or die; my $d = decode_json(<$h>);
    $d->{cwd} = $ARGV[1]; $d->{tool_input}{subagent_type} = "worker"; $d->{tool_input}{model} = "sonnet";
    $d->{tool_input}{prompt} = "Ticket folder: $ARGV[2]\nStage: build"; print encode_json($d)' "$here/hooks/agent-pre.json" "$F" "$T" > "$D/p.json"
  SA_HOOK_STATE="$D/st" bash "$SA_UNDER_TEST" room hook pre < "$D/p.json" > "$D/o" 2>&1 || fail "hook exit $?"
  [ ! -s "$D/o" ] || fail "hook printed: $(cat "$D/o")"
  grep -qF 'worker: started by router: stage build' "$G" || fail "the dispatch line is not in the digest: $(cat "$G" 2>/dev/null)"
  fresh
}
c_no_room() {
  local o OT="$D/outside/tickets/001-demo-ticket"
  sa stage "$OT" research "x" >/dev/null || fail "stage"
  [ -z "$(find "$D" -name digest -type d 2>/dev/null)" ] && [ ! -e "$OT/notes" ] || fail "a digest was written without a room"
  o=$(sa digest "$OT") || fail "digest failed: $o"
  case "$o" in "no decision room"*) ;; *) fail "output: $o" ;; esac
  [ -z "$(find "$D" -name digest -type d 2>/dev/null)" ] && [ ! -e "$OT/notes" ] || fail "sa digest wrote one without a room"
}
c_no_digest_env() {
  SA_NO_DIGEST=1 sa stage "$T" research "x" >/dev/null || fail "stage"
  [ ! -e "$G" ] || fail "SA_NO_DIGEST=1 still wrote a digest"
  grep -qF 'ready/- -> in-progress/research' "$LOG" || fail "the log line is missing"
  ! grep -qF 'digest' "$LOG" || fail "the digest wrote a log line"
}
c_never_fails_the_caller() {
  local o
  mkdir -p "$T/notes"; : > "$G"; chmod a-w "$T/notes"
  o=$(sa stage "$T" research "x") || fail "the stage failed when the digest could not be written: $o"
  [ "$o" = '001 demo-ticket: ready/- -> in-progress/research' ] || fail "output changed: $o"
  chmod u+w "$T/notes"
}

run_case "sa digest builds the digest in the room, with its freshness mark" c_built
run_case "the digest is rebuilt after sa stage and room lines of its ticket" c_refreshed_after_stage
run_case "the router's dispatch hook rebuilds the digest" c_refreshed_by_hook
run_case "a project without a room gets no digest" c_no_room
run_case "SA_NO_DIGEST=1 switches the refresh off" c_no_digest_env
run_case "a digest that cannot be written never fails the caller" c_never_fails_the_caller
