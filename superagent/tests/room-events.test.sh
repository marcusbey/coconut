#!/usr/bin/env bash
# room-events.test.sh: the room log shows every question, every agent interaction and every final
# decision (superagent#005): sa ask's options, sa answer's question and --by, sa room event, and the
# question in sa room decide's line. Every case runs on its own throwaway fixture (fixture.sh).
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
sa() { bash "$SA_UNDER_TEST" "$@"; }   # through bash: a copy from `git show` is not executable
B='(🧭|🏛️|✍️|🔨|🤝|🐞|🧪|🔍|🔀|🌐|🐶|👤|❔)'   # the badge of the agent role behind a line (superagent#007)
LINE='^'"$B"' [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \| [^|]+ \| (stage|question|answer|suggestion|lesson|check|landing|note|decision|dispatch|report) \| .+$'

F=""; D=""; T=""; LOG=""
fail() { echo "$*"; exit 1; }
count() { grep -c "$@" 2>/dev/null || true; }
lines() { if [ -f "$1" ]; then grep -vc '^# ' "$1" || true; else echo 0; fi; }   # entries: the legend line (# ...) is not one
text() { sed 's/^[^|]*|[^|]*|[^|]*| //' ; }   # the text of a log line: everything after the third " | "
drop_dir() { # only a fixture folder, made writable again first (a case may have locked it)
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
run_case() { # run_case <name> <function>
  local rc
  F=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$F"); T="$F/demo/tickets/001-demo-ticket"; LOG="$F/decision-room/demo/LOG.md"
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  drop_dir "$D"
}
one_more() { # one_more <lines before> <kind>: the log grew by exactly one line of that kind, in the format
  [ "$(lines "$LOG")" = $(($1 + 1)) ] || fail "want exactly one new line, log went from $1 to $(lines "$LOG"): $(cat "$LOG" 2>/dev/null)"
  tail -1 "$LOG" | grep -qE "$LINE" || fail "line breaks the format: $(tail -1 "$LOG")"
  tail -1 "$LOG" | grep -qF " | $2 | " || fail "want kind $2: $(tail -1 "$LOG")"
}

c_e1_question() {
  local n
  sa ask "$T" worker "Keep the old flag?" "Keep it" "Drop it" "Rename it" >/dev/null || fail "ask failed"
  one_more 0 question
  tail -1 "$LOG" | text | grep -qxF 'ready/- -> blocked/-: Q1 from worker: Keep the old flag? | options: (a) Keep it (recommended); (b) Drop it; (c) Rename it' ||
    fail "question line wrong: $(tail -1 "$LOG")"
  n=$(lines "$LOG")
  sa ask "$T" tester "Which version?" "Use v2 (Recommended)" "Use v1" >/dev/null || fail "second ask failed"
  one_more "$n" question
  tail -1 "$LOG" | text | grep -qxF 'blocked/- -> blocked/-: Q2 from tester: Which version? | options: (a) Use v2 (Recommended); (b) Use v1' ||
    fail "second question line wrong (doubled or missing marker?): $(tail -1 "$LOG")"
}

c_e1_access() {
  sa ask "$T" merger --access "tried the browser; the login page asked for 2FA" "Can you sign in?" "I signed in" "Stop" >/dev/null || fail "ask failed"
  tail -1 "$LOG" | grep -qF 'Q1 from merger: Can you sign in? | options: (a) I signed in (recommended); (b) Stop' || fail "access question line wrong: $(tail -1 "$LOG")"
}

c_e2_answer() {
  local n before
  sa ask "$T" worker "Keep the old flag?" "Keep it" "Drop it" "Rename it" >/dev/null
  n=$(lines "$LOG")
  sa answer "$T" Q1 "Drop it" >/dev/null || fail "answer failed"
  one_more "$n" answer
  tail -1 "$LOG" | text | grep -qxF 'Q1 answered by the user: Drop it | question: Keep the old flag?' || fail "answer line wrong: $(tail -1 "$LOG")"
  grep -qxE 'Answer: Drop it \([0-9]{4}-[0-9]{2}-[0-9]{2}\)' "$T/notes/questions.md" || fail "questions.md Answer line changed: $(cat "$T/notes/questions.md")"
  sa ask "$T" worker "Ship on Friday?" "yes" "no" >/dev/null
  n=$(lines "$LOG")
  sa answer "$T" Q2 "b" --by "decision room (D7)" >/dev/null || fail "answer --by failed"
  one_more "$n" answer
  tail -1 "$LOG" | text | grep -qxF 'Q2 answered by decision room (D7): b | question: Ship on Friday?' || fail "--by answer line wrong: $(tail -1 "$LOG")"
  grep -qxE 'Answer: b \([0-9]{4}-[0-9]{2}-[0-9]{2}\)' "$T/notes/questions.md" || fail "--by reached questions.md: $(cat "$T/notes/questions.md")"
  grep -q -- '--by\|D7' "$T/notes/questions.md" && fail "--by text inside questions.md"
  # --by with no name is refused before anything changes
  sa ask "$T" worker "Third?" "x" "y" >/dev/null
  n=$(lines "$LOG"); before=$(cksum < "$T/notes/questions.md")
  sa answer "$T" Q3 "x" --by >/dev/null 2>&1 && fail "--by without a name was accepted"
  [ "$(lines "$LOG")" = "$n" ] && [ "$(cksum < "$T/notes/questions.md")" = "$before" ] || fail "a refused --by changed something"
  return 0
}

c_e2_output_same() { # the printed output and exit code of sa answer do not depend on --by
  local a b
  sa ask "$T" worker "q1" "x" "y" >/dev/null; sa ask "$T" worker "q2" "x" "y" >/dev/null
  a=$(sa answer "$T" Q1 "x"; echo "rc=$?"); b=$(sa answer "$T" Q2 "x" --by "decision room (D1)"; echo "rc=$?")
  [ "$a" = "Q1 answered; open questions left: 1
rc=0" ] || fail "plain answer printed: $a"
  [ "$b" = "Q2 answered; open questions left: 0
rc=0" ] || fail "--by answer printed: $b"
}

c_e3_event() {
  local k n
  for k in dispatch report question answer; do
    n=$(lines "$LOG")
    sa room event "$T" "$k" worker "text with | a pipe" >/dev/null || fail "$k: exit $?"
    one_more "$n" "$k"
    tail -1 "$LOG" | grep -qF " | demo#001 | $k | worker: text with | a pipe" || fail "$k line wrong: $(tail -1 "$LOG")"
    tail -1 "$LOG" | grep -qE " \| demo#001 \| $k \| worker: text with \| a pipe$" || fail "$k line has more: $(tail -1 "$LOG")"
  done
  n=$(lines "$LOG")
  sa room event "$F/demo/tickets" report watchdog "demo#001 has had no activity for 3 hours" >/dev/null || fail "tickets-folder event failed"
  one_more "$n" report
  tail -1 "$LOG" | grep -qE ' \| demo \| report \| watchdog: demo#001 has had no activity for 3 hours$' || fail "tickets-folder ref wrong: $(tail -1 "$LOG")"
}

c_e8_decision() {
  local out
  out=$(sa room decide "$T" Q1 "Keep the old flag?" --option "Keep it" --option "Drop it" --fable b "why" --codex b "why") || fail "decide failed: $out"
  [ "$out" = "D1: (b) Drop it; decided by both" ] || fail "printed output changed: $out"
  tail -1 "$LOG" | grep -qE "$LINE" || fail "format: $(tail -1 "$LOG")"
  tail -1 "$LOG" | text | grep -qxF 'D1 (Q1): Keep the old flag? -> (b) Drop it; decided by both' || fail "decision line wrong: $(tail -1 "$LOG")"
  out=$(sa room decide "$T" Q1 "Keep the old flag?" --option "Keep it" --option "Drop it" --fable b "why" --codex-unavailable "limit") || fail "second decide failed: $out"
  tail -1 "$LOG" | text | grep -qxF 'D2 (Q1): Keep the old flag? -> (b) Drop it; decided by fable alone (codex unavailable: limit)' || fail "D2 line wrong: $(tail -1 "$LOG")"
  grep -qx 'Question: Keep the old flag?' "$F/decision-room/demo/DECISIONS.md" || fail "DECISIONS.md changed shape"
}

c_x1_hostile() {
  local n
  sa stage "$T" research a >/dev/null; n=$(lines "$LOG")
  sa ask "$T" worker "q" "$(printf 'line1\nline2')" "has | pipe" >/dev/null || fail "ask failed"
  one_more "$n" question
  tail -1 "$LOG" | grep -qF ': Q1 from worker: q | options: (a) line1 line2 (recommended); (b) has | pipe' || fail "hostile options line wrong: $(tail -1 "$LOG")"
}

c_x2_unknown_answer() {
  local base out want rc wrc n
  git -C "$here" show main:superagent/sa > "$D/sa-base" || fail "no main:superagent/sa"
  sa ask "$T" worker "q" "x" "y" >/dev/null
  n=$(lines "$LOG")
  out=$(sa answer "$T" Q9 "x" 2>&1); rc=$?
  want=$(bash "$D/sa-base" answer "$T" Q9 "x" 2>&1); wrc=$?
  [ "$rc" = "$wrc" ] && [ "$out" = "$want" ] || fail "differs from the base sa: rc $rc '$out', want rc $wrc '$want'"
  [ "$(lines "$LOG")" = "$n" ] || fail "an unknown question wrote a line: $(tail -1 "$LOG")"
}

c_x3_refused() {
  local n out
  sa stage "$T" research a >/dev/null; n=$(lines "$LOG")
  refused() { local out rc; out=$(sa room event "$T" "$@" 2>&1); rc=$?
    [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^refused: ' || fail "'$*': want refused: and exit 1, got $rc: $out"; }
  refused stage worker "x"
  refused bogus worker "x"
  refused dispatch worker ""
  refused dispatch worker "   "
  refused dispatch "" "x"
  refused dispatch worker
  refused dispatch
  out=$(sa room event "$F/no-such-folder" dispatch worker "x" 2>&1); [ $? = 1 ] || fail "a missing folder was accepted: $out"
  [ "$(lines "$LOG")" = "$n" ] || fail "a refused event wrote a line: $(tail -1 "$LOG")"
}

c_x4_unwritable() {
  local out rc
  sa stage "$T" research a >/dev/null
  chmod 555 "$F/decision-room/demo"; chmod 444 "$LOG"
  out=$(sa room event "$T" dispatch worker "x" 2>&1); rc=$?
  chmod 755 "$F/decision-room/demo"; chmod 644 "$LOG"
  [ "$rc" = 0 ] || fail "exit $rc: $out"
  [ "$out" = "note: could not write the decision-room log" ] || fail "printed: '$out'"
}

c_x4_midwrite() { # a write that fails half way is taken back: the log keeps only whole lines (review round 1, finding 4)
  local before out rc big
  sa stage "$T" research a >/dev/null
  before=$(cksum < "$LOG")
  big=$(head -c 3000 /dev/zero | tr '\0' 'y')
  # a file size limit of 1024 bytes stops the append part way, as a full disk would
  out=$( trap '' XFSZ; ulimit -f 1; sa room event "$T" dispatch worker "$big" 2>&1 ); rc=$?
  [ "$rc" = 0 ] || fail "exit $rc: $out"
  [ "$out" = "note: could not write the decision-room log" ] || fail "printed: '$out'"
  [ "$(cksum < "$LOG")" = "$before" ] || fail "a half-written line stayed: $(tail -c 80 "$LOG")"
  sa room event "$T" report worker "ready: after the failure" >/dev/null || fail "next event failed"
  [ "$(count -vE "$LINE|^# " "$LOG")" = 0 ] && [ "$(lines "$LOG")" = 2 ] || fail "log broke after the failure: $(cat "$LOG")"
}

c_unreadable_log() { # a log that can be written but not read: its length is unknown, so nothing is appended (round 2, finding 2)
  local before out rc
  sa stage "$T" research a >/dev/null
  before=$(cksum < "$LOG")
  chmod 222 "$LOG"
  out=$(sa room event "$T" dispatch worker "x" 2>&1); rc=$?
  chmod 644 "$LOG"
  [ "$rc" = 0 ] || fail "exit $rc: $out"
  printf '%s\n' "$out" | grep -qx 'note: could not write the decision-room log' || fail "silent: '$out'"
  [ "$(cksum < "$LOG")" = "$before" ] || fail "the log changed: $(cat "$LOG")"
}

held() { # held <lock file>: is the flock on it taken by someone?
  perl -MFcntl=:flock -e 'open(my $fh, ">>", $ARGV[0]) or exit 2; exit(flock($fh, LOCK_EX | LOCK_NB) ? 1 : 0)' "$1"
}
hold() { # hold <lock file>: a background process takes the log's flock and keeps it; prints its pid once it holds
  perl -MFcntl=:flock -e 'open(my $fh, ">>", $ARGV[0]) or exit 2; flock($fh, LOCK_EX) or exit 1; sleep 60' "$1" >/dev/null 2>&1 &   # not on the caller's $(...) pipe
  local p=$! i=0
  until held "$1"; do i=$((i + 1)); [ "$i" -lt 100 ] || fail "the holder never took the lock"; sleep 0.1; done
  echo "$p"
}
shared_room() { # the outside project's Room: line names demo's log: another tickets folder, so another tickets lock
  printf 'Room: %s\n' "$F/decision-room" >> "$D/outside/tickets/PROJECT.md"
  sed -i.bak 's/^# Project: outside$/# Project: demo/' "$D/outside/tickets/PROJECT.md"
}

c_log_lock() { # every writer of one log waits for its lock, whatever its tickets folder (round 2, finding 1)
  local O="$D/outside" L="$LOG" holder pid n
  shared_room
  sa room event "$T" dispatch worker "first" >/dev/null || fail "first event"
  sa room event "$O/tickets" report watchdog "waiting: router: shared" >/dev/null || fail "outside event"
  [ "$(lines "$L")" = 2 ] || fail "the two projects do not share the log: $(cat "$L")"
  holder=$(hold "$L.lock")
  sa room event "$O/tickets" report watchdog "waiting: router: after the lock" >/dev/null & pid=$!
  sleep 1
  n=$(lines "$L")
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
  wait "$pid" || fail "the waiting event failed"
  [ "$n" = 2 ] || fail "an event wrote while another writer held the log's lock"
  [ "$(lines "$L")" = 3 ] || fail "the event did not write once the holder was gone: $(cat "$L")"
  held "$L.lock" && fail "the log lock is still held after every writer exited"
  [ "$(count -vE "$LINE|^# " "$L")" = 0 ] || fail "malformed: $(cat "$L")"
}

c_killed_holder() { # a holder killed with -9 frees the lock at once; two waiters then take turns (round 3, finding 1)
  local L="$LOG" holder a b n
  shared_room
  sa room event "$T" dispatch worker "first" >/dev/null || fail "first event"
  holder=$(hold "$L.lock")
  sa room event "$T" report worker "ready: from demo" >/dev/null & a=$!
  sa room event "$D/outside/tickets" report watchdog "waiting: router: from outside" >/dev/null & b=$!
  sleep 1
  n=$(lines "$L")
  kill -9 "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
  wait "$a" || fail "waiter a failed"; wait "$b" || fail "waiter b failed"
  [ "$n" = 1 ] || fail "a waiter wrote while the holder was alive"
  [ "$(lines "$L")" = 3 ] && [ "$(count -vE "$LINE|^# " "$L")" = 0 ] || fail "want 3 whole lines: $(cat "$L")"
  grep -qF 'worker: ready: from demo' "$L" && grep -qF 'watchdog: waiting: router: from outside' "$L" || fail "a waiter's line is missing: $(cat "$L")"
}

c_lock_setup_fails() { # the lock file cannot be made: nothing written, a note; once it can, logging works again (round 3, finding 2)
  local out rc R="$F/decision-room/demo"
  sa stage "$T" research a >/dev/null
  [ ! -e "$LOG.lock" ] || command mv -f "$LOG.lock" "$D/old-lock"   # the lock file does not exist yet
  chmod 555 "$R"   # the folder refuses the lock file; LOG.md itself stays writable
  out=$(sa room event "$T" dispatch worker "x" 2>&1); rc=$?
  chmod 755 "$R"
  [ "$rc" = 0 ] && [ "$out" = "note: could not write the decision-room log" ] || fail "rc $rc, printed: '$out'"
  [ "$(lines "$LOG")" = 1 ] || fail "a line was written without the lock: $(cat "$LOG")"
  sa room event "$T" dispatch worker "y" >/dev/null || fail "the next event failed"
  [ "$(lines "$LOG")" = 2 ] || fail "logging stayed jammed after the failure: $(cat "$LOG")"
  : > "$D/empty"; command cp "$D/empty" "$LOG.lock"   # a leftover lock file, as after a crash, blocks nothing
  sa room event "$T" report worker "ready: z" >/dev/null && [ "$(lines "$LOG")" = 3 ] || fail "a leftover lock file blocked the log"
}

c_bootstrap() { # a new project: a tickets folder with no BOARD.md yet, and a draft ticket in it (review round 1, finding 2)
  local P="$F/newp/tickets" L="$F/decision-room/newp/LOG.md"
  mkdir -p "$P" || fail "setup"
  sa room event "$P" dispatch ticket-writer "started by router: stage writing tickets, model sonnet, effort unknown" >/dev/null || fail "dispatch on a board-less folder refused"
  mkdir -p "$P/001-first" && printf '# 001: First\n\nStatus: draft\n' > "$P/001-first/rd.md"
  sa room event "$P/001-first" question ticket-writer "Q1: Keep it? | options: (a) yes (recommended); (b) no" >/dev/null || fail "question on a draft with no board refused"
  [ "$(lines "$L")" = 2 ] && [ "$(count -vE "$LINE|^# " "$L")" = 0 ] || fail "want 2 lines in the new project's log: $(cat "$L" 2>/dev/null)"
  grep -v '^# ' "$L" | sed -n 1p | grep -qE ' \| newp \| dispatch \| ticket-writer: started by router: stage writing tickets' || fail "dispatch line wrong: $(grep -v '^# ' "$L" | sed -n 1p)"
  grep -v '^# ' "$L" | sed -n 2p | grep -qE ' \| newp#001 \| question \| ticket-writer: Q1: Keep it\? \| options: ' || fail "question line wrong: $(grep -v '^# ' "$L" | sed -n 2p)"
  [ ! -e "$P/BOARD.md" ] || fail "room event created a board"
}

c_x5_no_room() {
  local out rc
  out=$(sa room event "$D/outside/tickets/001-demo-ticket" report worker "ready: x" 2>&1); rc=$?
  [ "$rc" = 0 ] && [ "$out" = "no decision room for this project; nothing written" ] || fail "rc $rc, '$out'"
  [ -z "$(find "$D" -name decision-room)" ] || fail "a decision-room folder appeared"
}

c_n1_format() { # every E and X write on one fixture, after old-format lines: all lines match, index still reads it
  mkdir -p "$F/decision-room/demo"
  cat > "$LOG" <<'EOF'
2026-11-13 09:12 | demo#001 | stage | ready/- -> in-progress/build: worker starts
2026-11-13 09:40 | demo#001 | question | in-progress/build -> blocked/build: Q1 from worker: Use A or B?
2026-11-13 10:02 | demo#001 | answer | Q1 answered: use A
2026-11-13 10:05 | demo | decision | D1 (Q1): (a) use A; decided by both
2026-11-13 10:06 | demo#001 | note | clerk: carried out D1
EOF
  command cp "$LOG" "$D/old"
  sa ask "$T" worker "Keep?" "Keep it" "$(printf 'a\nb')" "c | d" >/dev/null
  sa answer "$T" Q1 "Keep it" --by "decision room (D2)" >/dev/null
  sa room decide "$T" Q1 "Keep?" --option "Keep it" --option "Drop it" --fable a "w" --codex a "w" >/dev/null
  sa room event "$T" dispatch worker "started by router: stage build, model opus, effort high" >/dev/null
  sa room event "$T" report worker "ready: done" >/dev/null
  # the five old lines stay as they were (the diff below); every line the new sa wrote after them has the badge
  [ "$(tail -n +6 "$LOG" | grep -vcE "$LINE" || true)" = 0 ] || fail "new lines out of format: $(tail -n +6 "$LOG" | grep -vE "$LINE")"
  head -n 5 "$LOG" | diff - "$D/old" || fail "old lines were rewritten"
  sa room index "$F" >/dev/null || fail "index failed on a mixed log"
  grep -qx '## demo' "$F/decision-room/INDEX.md" || fail "index lost the demo project"
}

c_e9_help() {
  sa help | grep -q 'room event' || fail "help lacks room event"
  sa help | grep -q -- '--by' || fail "help lacks --by"
}

run_case "E-1 a question line carries asker, all options and the recommended one" c_e1_question
run_case "E-1 an access question carries its options too" c_e1_access
run_case "E-2 an answer line carries the question and who answered" c_e2_answer
run_case "E-2 sa answer prints the same with and without --by" c_e2_output_same
run_case "E-3 room event writes one line per allowed kind" c_e3_event
run_case "E-8 a decision line carries the question, the choice and who decided" c_e8_decision
run_case "E-9 help lists room event and --by" c_e9_help
run_case "X-1 hostile option text stays one line" c_x1_hostile
run_case "X-2 an unknown question answers as the base sa and logs nothing" c_x2_unknown_answer
run_case "X-3 unknown or missing kind, who or text is refused" c_x3_refused
run_case "X-4 an unwritable log never fails room event" c_x4_unwritable
run_case "X-4 a half-written line is taken back" c_x4_midwrite
run_case "X-5 room event in a project without a room" c_x5_no_room
run_case "a new project logs before its board exists" c_bootstrap
run_case "a log that cannot be read gets nothing appended" c_unreadable_log
run_case "writers of one log from two tickets folders take turns" c_log_lock
run_case "a killed holder frees the lock; two waiters take turns" c_killed_holder
run_case "a lock that cannot be set up writes nothing and jams nothing" c_lock_setup_fails
run_case "N-1 old and new lines together stay in the format" c_n1_format
