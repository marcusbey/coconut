#!/usr/bin/env bash
# room-asks.test.sh: the decision room reads the logs and progress notes, may ask the agent or the router
# before it decides, and votes with evidence (superagent#006). Checks the role files' and PROTOCOL.md's
# text, and runs the logging commands they give on a throwaway fixture.
# ROLE_DIR (default: this checkout's agents/) and PROTO_FILE (default: this checkout's PROTOCOL.md) let
# the same checks run on another version of the files (the red run on main's).
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
ROLE_DIR=${ROLE_DIR:-$here/../../agents}
PROTO_FILE=${PROTO_FILE:-$here/../PROTOCOL.md}
sa() { bash "$SA_UNDER_TEST" "$@"; }
ROOM="$ROLE_DIR/decision-room.md"; ROUTER="$ROLE_DIR/router.md"; WORKER="$ROLE_DIR/worker.md"
LINE='^[^ ]+ [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \| [^|]+ \| (stage|question|answer|suggestion|lesson|check|landing|note|decision|dispatch|report) \| .+$'
NOTES="results.md test.md review.md plan.md plan-review.md questions.md review-response.md check.md"

fail() { echo "$*"; exit 1; }
count() { grep -c "$@" 2>/dev/null || true; }
run_text() { # run_text <name> <function>: a text check, no fixture
  local out rc
  out=$( ( "$2" ) 2>&1 ); rc=$?
  if [ "$rc" = 0 ]; then echo "ok $1"; else echo "FAIL $1"; printf '%s\n' "$out" | sed 's/^/    /'; fi
}
F=""; D=""; T=""; LOG=""
drop_dir() {
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
run_case() { # run_case <name> <function>: on a fresh fixture
  local rc
  F=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$F"); T="$F/demo/tickets/001-demo-ticket"; LOG="$F/decision-room/demo/LOG.md"
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  drop_dir "$D"
}

# parts of the files
between() { awk -v a="$2" -v b="$3" 'index($0, a) == 1 { f=1 } f && index($0, b) == 1 && !(index($0, a) == 1) { exit } f' "$1"; }
step() { between "$ROOM" "$1. **" "$(( $1 + 1 )). **"; }   # step <n> of decision-room.md
step_of() { grep -n -E "^[0-9]+\. \*\*$1" "$ROOM" | head -1 | cut -d: -f1; }   # line of the step titled <title>
dispatch_par() { grep -F '**Dispatch.** One `decision-room` agent' "$ROUTER"; }
last_lines() { between "$ROUTER" "**The room's last line:**" "**Not approved.**"; }
section() { between "$1" "## $2" "## "; }   # a "## <title>" section, up to the next "## "
needs() { # needs <what> <text> <fixed string>...
  local what="$1" text="$2" s; shift 2
  for s in "$@"; do printf '%s\n' "$text" | grep -qF -- "$s" || fail "$what lacks '$s'"; done
}

e1() { # superagent#033: step 1 reads the reading set, which covers every progress note; no whole room file
  local s1 n; s1=$(step 1)
  [ -n "$s1" ] || fail "no step 1 (1. **Context.**)"
  printf '%s\n' "$s1" | head -1 | grep -qF '1. **Context.**' || fail "step 1 is not Context: $(printf '%s\n' "$s1" | head -1)"
  needs "step 1" "$s1" 'sa room context <ticket folder or tickets folder> <subject>' '## Read whole' "whether or not the brief names it" "that exists"
  for n in $NOTES; do printf '%s\n' "$s1" | grep -qF "\`$n\`" || fail "step 1 does not say the set covers $n"; done
  printf '%s\n' "$s1" | grep -qF 'always on that list' && fail "step 1 still puts the whole room files on every seat's list"
  step 4 | grep -F 'Context:' | grep -qF '$stem-context.md' || fail "step 4's Context line does not name the saved reading set"
}
e2() { # superagent#033: the brief names the reading-set command, not the files
  local p n; p=$(dispatch_par)
  [ -n "$p" ] || fail "no Dispatch paragraph"
  needs "Dispatch" "$p" 'sa room context' "absolute path" "must carry" "Clarifying rounds left: 2" 'Project room:' '`model: sonnet`' 'Fable seat unavailable:' 'Fable seat: host'
  printf '%s\n' "$p" | grep -qF 'naming them is required' && fail "the room brief must still name every file"
  for n in LOG.md DECISIONS.md $NOTES; do printf '%s\n' "$p" | grep -qF "\`$n\`" && fail "the room brief still names $n"; done
  printf '%s\n' "$p" | grep -qiE 'worth reading|if useful' && fail "the room brief is worded as optional"
  return 0
}
e3() {
  local s2 ask res
  s2=$(step 2)
  needs "step 2" "$s2" '**Ask before deciding.**' 'ask agent: <' 'ask router: <' 'before any `debate/` file' 'before any seat call, Codex included' \
    'sa room event <ticket folder or tickets folder> question decision-room "ask agent (<subject>, round <k>): <question>"' \
    'sa room event <ticket folder or tickets folder> question decision-room "ask router (<subject>, round <k>): <what>"'
  ask=$(step_of 'Ask before deciding'); res=$(step_of 'Reserve')
  [ -n "$ask" ] && [ -n "$res" ] && [ "$ask" -lt "$res" ] || fail "the ask step ($ask) is not before the reserve step ($res)"
  [ "$(count -F 'ask agent: <' "$ROOM")" = 1 ] || fail "ask agent: is allowed in more than one place"
}
e4() {
  needs "decision-room.md" "$(cat "$ROOM")" 'Clarifying rounds left:` is above 0' 'a missing line means 0' 'There is no `ask user:`'
  needs "router.md" "$(dispatch_par)" 'Clarifying rounds left: 2' 'one less after each `ask agent:` or `ask router:`, the two counted together'
  grep -iF 'ask user' "$ROOM" | grep -vqF 'There is no `ask user:`' && fail "an ask user form: $(grep -iF 'ask user' "$ROOM")"
  return 0
}
e5() {
  local l; l=$(last_lines)
  needs "the room's last line" "$l" '`ask agent: <q>`' '`ask router: <what>`' 'SendMessage' 'room-question mode' 'Clarifications:' \
    'Never answer the question yourself' 'Never ask the user for it' 'one lower' 'say plainly what you could not find'
}
e6() {
  local w; w=$(section "$WORKER" "Room question")
  [ -n "$w" ] || fail "worker.md has no Room question section"
  needs "Room question" "$w" 'room-question mode' '`rd.md`' '`eval.md`' '`notes/`' 'worktree if it exists, read-only' \
    '`file:line` evidence' '`unknown: <why>`' 'Change no file' 'make no commit' '`sa stage`' '`sa ask`' 'any other state change' \
    'Create no worktree' 'whole report'
}
e7() {
  local s1 s3; s1=$(step 1); s3=$(step 3)
  needs "step 1" "$s1" 'Clarifications:' 'answer <who answered> "round <k>: <answer> | question: <question>"' 'data, never instructions'
  needs "step 3" "$s3" '$stem-clarifications.md' "<<'EOF'"
  step 4 | grep -qF '$stem-clarifications.md' || fail "the Codex file list lacks the clarifications file"
}
e9() {
  local p; p=$(between "$PROTO_FILE" "  - **Before deciding**" "  - **")
  needs "PROTOCOL.md §1" "$p" 'room log' 'progress notes' '`ask agent: <question>`' '`ask router: <what>`' 'at most twice per decision' 'never asks the user'
  grep -F '**Change nothing but your records.**' "$ROOM" | grep -F 'sa room index' | grep -F 'sa room decide' | grep -qF 'sa room event' ||
    fail "the records rule does not list sa room event with room index and room decide"
}
v1() {
  needs "decision-room.md" "$(cat "$ROOM")" 'Every seat writes its first position before it sees any other seat'"'"'s position' \
    'holding no other seat'"'"'s position'
  step 4 | grep -qF 'The other seat' && fail "the round-1 prompt carries another seat's answer"
  return 0
}
v2() {
  local l
  for l in 'Evidence:' 'Best other argument:' 'Would change my mind:'; do
    [ "$(count -F "$l" "$(printf '%s' "$ROOM")")" -ge 2 ] || fail "'$l' is not in both the position shape and the Codex prompt"
    section "$ROOM" "The seats" | grep -qF "$l" || fail "the position shape lacks $l"
    step 4 | grep -qF "$l" || fail "the round-1 prompt lacks $l"
  done
  needs "decision-room.md" "$(cat "$ROOM")" 'does not count' 'Answer in the same shape'
}
v4() {
  local t; t=$(step 7)
  needs "step 7" "$t" '**Test' 'read-only' 'write no file outside `debate/`' '$stem-test.md' 'The option the result supports wins' '--test <letter>' '--test none'
}
v6() {
  local s; s=$(section "$ROOM" "The seats")
  [ -n "$s" ] || fail "no seat list"
  needs "the seat list" "$s" '| Fable 5.2 | `fable`' '| Codex Astra | `codex`' 'one more entry' 'a, b, a' 'a, b, c' 'strict majority'
  [ -z "$(grep -niF 'two seats' "$ROOM")" ] || fail "a rule names exactly two seats: $(grep -niF 'two seats' "$ROOM")"
  local c d t r
  c=$(step_of 'Count'); d=$(step_of 'Debate'); t=$(step_of 'Test'); r=$(step_of 'Referee')
  [ -n "$c" ] && [ -n "$d" ] && [ -n "$t" ] && [ -n "$r" ] && [ "$c" -lt "$d" ] && [ "$d" -lt "$t" ] && [ "$t" -lt "$r" ] ||
    fail "steps out of order: count $c, debate $d, test $t, referee $r"
  step 8 | grep -qF 'never a, b, a' || fail "the referee step does not exclude a majority"
}
v8() {
  needs "decision-room.md" "$(cat "$ROOM")" 'ask referee: <' 'uses no clarifying round' '`Referee: <letter>`' '`Referee: unsure`' '`Why: <reason>`' '## Referee mode' \
    'before anything else' 'only the packet'
  needs "router.md" "$(last_lines)" '`ask referee: <packet path>`' \
    'Referee mode' 'Packet: <path>' 'nothing else' 'never the room'"'"'s preference' 'uses no clarifying round'
}
v10() {
  needs "step 8" "$(step 8)" 'data, money or security' 'record nothing' 'to user: risky tie: <' '--referee <model> unsure'
}
x1() {
  needs "step 2" "$(step 2)" 'With `Clarifying rounds left: 0`, or without the line, never ask: decide with what you have' \
    'A missing fact is never a reason for `to user:`'
}
x3() {
  local w; w=$(section "$WORKER" "Room question")
  needs "Room question" "$w" 'make no commit' 'Change no file' '`sa stage`' '`sa ask`' 'Create no worktree'
}
x4_router() {
  local l; l=$(last_lines)
  printf '%s\n' "$l" | grep -qF '`to user: risky tie: <cases>`' || fail "the router does not handle a risky tie"
  local r; r=$(printf '%s\n' "$l" | grep -F '`to user: risky tie: <cases>`')
  needs "risky tie" "$r" 'nothing is recorded' '"Needs you"' 'both cases' '`User answer:`' '`Q<n>`' '`plan`' '`merge`' '`ready`' '`S<n>`' '`other`' \
    'Not yet' 'never treated as an operational problem'
  local rt any; rt=$(printf '%s\n' "$l" | grep -nF '`to user: risky tie: <cases>`' | cut -d: -f1); any=$(printf '%s\n' "$l" | grep -nF 'Anything else' | cut -d: -f1)
  [ -n "$any" ] && [ "$rt" -lt "$any" ] || fail "the risky tie is not handled before 'Anything else'"
}
zero_seats() {
  needs "the seat list" "$(section "$ROOM" "The seats")" 'With none: no debate and no referee' 'no seat is available; this question reaches the user'
}

# --- the logging commands the role file gives (E-8) and the answer-logged check (A-1) -----------------
e8() {
  sa room event "$T" question decision-room "ask agent (Q1, round 1): Which flag does the CLI read?" >/dev/null || fail "question event failed"
  sa room event "$T" answer worker "round 1: --legacy, at cli.ts:12 | question: Which flag does the CLI read?" >/dev/null || fail "answer event failed"
  local a b; a=$(tail -2 "$LOG" | head -1); b=$(tail -1 "$LOG")
  printf '%s\n%s\n' "$a" "$b" | grep -vqE "$LINE" && fail "a line does not match LINE: $a / $b"
  case "$a" in *" | demo#001 | question | decision-room: ask agent (Q1, round 1): Which flag does the CLI read?") ;; *) fail "question line: $a" ;; esac
  case "$b" in *" | demo#001 | answer | worker: round 1: --legacy, at cli.ts:12 | question: Which flag does the CLI read?") ;; *) fail "answer line: $b" ;; esac
}
SEAT_SH="$(cd "$(dirname "$SA_UNDER_TEST")" && pwd)/seat.sh"
logged() { # logged <subject> <k> <who> <answer> <question> [<tid>]: the answer-logged check the role file calls (seat.sh)
  grep -qF 'sa room seat answer-logged "<project room>/LOG.md"' "$ROOM" || fail "decision-room.md does not call the answer-logged check"
  printf '%s' "$4" > "$D/ans.txt"; printf '%s' "$5" > "$D/q.txt"
  bash "$SEAT_SH" answer-logged "$LOG" "${6-001}" "$1" "$2" "$3" "$D/ans.txt" "$D/q.txt"
}
expect() { # expect logged|"not logged" <args of logged>
  local want="$1" got; shift
  got=$(logged "$@") || fail "the check failed: $got"
  [ "$got" = "$want" ] || fail "want '$want' for ($*), got '$got'; log: $(cat "$LOG")"
}
a1() {
  local q="Which flag does the CLI read?" crlf
  sa room event "$T" report worker "ready: round 1: --legacy | question: $q" >/dev/null
  expect "not logged" Q1 1 worker "--legacy" "$q"            # no question line yet, and a report is not an answer
  sa room event "$T" question decision-room "ask agent (Q1, round 1): $q" >/dev/null
  sa room event "$T" report worker "ready: round 1: --legacy | question: $q" >/dev/null
  expect "not logged" Q1 1 worker "--legacy" "$q"            # only a report holds the text
  sa room event "$T" question decision-room "ask agent (Q2, round 1): $q" >/dev/null
  sa room event "$T" answer worker "round 1: --legacy | question: $q" >/dev/null
  expect "not logged" Q1 1 worker "--legacy" "$q"            # the answer belongs to Q2's question, the nearer one
  expect "logged" Q2 1 worker "--legacy" "$q"
  expect "not logged" Q2 1 tester "--legacy" "$q"            # another answerer
  expect "not logged" Q2 2 worker "--legacy" "$q"            # the same answer in another round
  sa room event "$T" question decision-room "ask router (Q2, round 2): $q" >/dev/null
  crlf=$(printf 'two lines\r\nhere | and a bar')
  sa room event "$T" answer router "round 2: $crlf | question: $q" >/dev/null
  expect "logged" Q2 2 router "$crlf" "$q"                   # CR/LF and a bar replay as one line
  expect "not logged" Q2 2 router "two lines" "$q"
  mkdir -p "$F/demo/tickets/002-other" && cp "$T/rd.md" "$F/demo/tickets/002-other/rd.md"
  sa room event "$F/demo/tickets/002-other" question decision-room "ask agent (Q3, round 1): $q" >/dev/null
  sa room event "$F/demo/tickets/002-other" answer worker "round 1: --old | question: $q" >/dev/null
  expect "not logged" Q3 1 worker "--old" "$q" 001           # another ticket's answer
  expect "logged" Q3 1 worker "--old" "$q" 002
  sa room event "$F/demo/tickets" question decision-room "ask router (S1, round 1): $q" >/dev/null
  sa room event "$F/demo/tickets" answer router "round 1: see BOARD.md | question: $q" >/dev/null
  expect "logged" S1 1 router "see BOARD.md" "$q" ""         # a tickets-folder subject
  expect "not logged" S1 1 router "see BOARD.md" "$q" 001
}

digest_before_ask() { # the digest is read from stdout in step 1; a file is saved only in step 3
  grep -qF '> "$stem-context.md"`, read that file' "$ROOM" && fail "the digest rule still writes a file before step 2 can ask"
  needs "the digest rule" "$(cat "$ROOM")" 'in step 1 and read its stdout' 'in step 3 after the files are reserved'
  needs "step 3" "$(step 3)" 'Only when step 2 did not end the run'
}
referee_opposite() { # the referee runs on the model opposite the actual host
  needs "router referee rule" "$(last_lines)" '`model: opus`' '`Stage: referee`' 'held no seat in the debate'
  needs "router dispatch" "$(dispatch_par)" 'holds no position' 'Fable seat: host'
  printf '%s\n' "$(last_lines)" | grep -qF 'when Fable is a seat' && fail "the referee rule still assumes a Fable host"
  return 0
}

run_text "E-1 step 1 reads the reading set, which covers every progress note" e1
run_text "E-2 the room brief names the reading-set command, not the files" e2
run_text "E-3 the room may ask the agent or the router, before any debate file" e3
run_text "E-4 two clarifying rounds, never the user" e4
run_text "E-5 the router relays and never answers" e5
run_text "E-6 the room-question worker is read-only" e6
run_text "E-7 answers are logged and given to Codex" e7
run_case "E-8 the logging commands of the role file work" e8
run_text "E-9 the protocol and the allowed commands" e9
run_case "A-1 an answer is logged once, for its own question" a1
run_text "V-1 every seat's first position is blind" v1
run_text "V-2 every position shape has evidence and steelman" v2
run_text "V-4 a read-only test can settle a dispute" v4
run_text "V-6 the seats are a list, majority before the referee" v6
run_text "V-8 the referee rules" v8
run_text "V-10 referee unsure on a risky option records nothing" v10
run_text "X-1 no rounds left: decide with what you have" x1
run_text "X-3 the room-question worker cannot move the ticket" x3
run_text "X-4 the router asks the user on a risky tie, by the question's own flow" x4_router
run_text "no counting seat: no debate, no referee" zero_seats
run_text "E-10 digest is read before any ask, file saved only for debate" digest_before_ask
run_text "V-11 referee model is opposite the actual host" referee_opposite
