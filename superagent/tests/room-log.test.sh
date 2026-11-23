#!/usr/bin/env bash
# room-log.test.sh: the decision-room log written by sa (superagent#001).
# Every case runs on its own throwaway fixture (fixture.sh), never on a real workspace.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
sa() { bash "$SA_UNDER_TEST" "$@"; }   # through bash: a copy from `git show` is not executable
B='(🧭|🏛️|✍️|🔨|🤝|🐞|🧪|🔍|🔀|🌐|🐶|👤|❔)'   # the badge of the agent role behind a line (superagent#007)
LINE='^'"$B"' [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \| [^|]+ \| (stage|question|answer|suggestion|lesson|check|landing|note) \| .+$'

F=""; D=""; T=""; LOG=""
fail() { echo "$*"; exit 1; }
count() { grep -c "$@" 2>/dev/null || true; }
lines() { if [ -f "$1" ]; then grep -vc '^# ' "$1" || true; else echo 0; fi; }   # entries: the legend line (# ...) is not one
drop_dir() { # only a fixture folder, made writable again first (a case may have locked it)
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
new_fixture() { bash "$here/fixture.sh"; }
section() { awk -v h="## $2" '$0==h {f=1; next} /^## /{f=0} f' "$1"; }

run_case() { # run_case <name> <function>
  local rc
  F=$(new_fixture) || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$F"); T="$F/demo/tickets/001-demo-ticket"; LOG="$F/decision-room/demo/LOG.md"
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  drop_dir "$D"
}

e2_steps() { # e2_steps <runner> <project folder>: steps 1-7 of eval E-2, each followed by its exit code
  local r="$1" p="$2" t="$2/tickets/001-demo-ticket"
  $r ask "$t" worker "Use A or B?" "use A" "use B"; echo "rc=$?"
  $r answer "$t" Q1 "use A"; echo "rc=$?"
  $r suggest "$p/tickets" "demo#001 worker" "Add a retry" "seen in x.sh:3" small; echo "rc=$?"
  $r suggest-close "$p/tickets" S1 dismissed "not now"; echo "rc=$?"
  $r learn "$p/tickets" "demo#001 worker" "the flaky test needs TZ=UTC"; echo "rc=$?"
  $r qa "$t" "open the app -> it starts"; echo "rc=$?"
  $r qa-pass "$t"; echo "rc=$?"
}

c_stage() {
  sa stage "$T" research "start" >/dev/null || fail "stage failed"
  [ "$(lines "$LOG")" = 1 ] || fail "room log has $(lines "$LOG") lines, want 1"
  [ "$(count -E "$LINE" "$LOG")" = 1 ] || fail "line does not match the format: $(cat "$LOG")"
  grep -q ' | demo#001 | stage | ready/- -> in-progress/research: start$' "$LOG" || fail "wrong stage line: $(cat "$LOG")"
  tail -1 "$F/demo/tickets/LOG.md" | grep -qE '^'"$B"' [0-9-]+ [0-9:]+ \| 001 \| ready/- -> in-progress/research \| start$' || fail "tickets LOG.md changed shape"
}

c_kinds() {
  e2_steps sa "$F/demo" >/dev/null
  local want k n
  for want in question:1 answer:1 suggestion:2 lesson:1 check:2; do
    k=${want%%:*}; n=$(count " | $k | " "$LOG")
    [ "$n" = "${want#*:}" ] || fail "$k: $n lines, want ${want#*:}"
  done
  [ "$(count -vE "$LINE|^# " "$LOG")" = 0 ] || fail "malformed lines: $(grep -vE "$LINE|^# " "$LOG")"
  # seven commands, exactly one line each (ask's move to blocked is inside its question line)
  [ "$(lines "$LOG")" = 7 ] || fail "want 7 lines in all, got $(lines "$LOG"): $(cat "$LOG")"
  [ "$(count ' | stage | ' "$LOG")" = 0 ] || fail "ask must not write a separate stage line"
  grep ' | question | ' "$LOG" | grep 'Q1' | grep 'worker' | grep -qF 'Use A or B?' || fail "question line lacks Q1, worker or the question"
  grep ' | answer | ' "$LOG" | grep 'Q1' | grep -q 'use A' || fail "answer line lacks Q1 or the answer"
  grep -q ' | demo | lesson | ' "$LOG" || fail "a tickets-folder command must log the ref 'demo'"
}

c_land() {
  local h m
  git -C "$F/demo" worktree add -q "$D/wt" -b ticket/001-demo-ticket main || fail "worktree"
  echo x > "$D/wt/feature.txt"
  git -C "$D/wt" add feature.txt && git -C "$D/wt" commit -q -m "feat: x" || fail "commit"
  h=$(git -C "$D/wt" rev-parse HEAD)
  mkdir -p "$T/notes"
  printf -- '--- Round 1, 2026-01-01\nTested commit: %s\nBase: main @ x\nResult: pass\n' "$h" > "$T/notes/test.md"
  printf -- '--- Round 1, 2026-01-01, reviewer: codex (fixture)\nSecond review, reviewer: claude (fixture)\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\n' "$h" > "$T/notes/review.md"
  sa land "$T" "$D/wt" main || fail "sa land failed"
  m=$(git -C "$F/demo" rev-parse main)
  [ "$(count ' | landing | ' "$LOG")" = 1 ] || fail "want one landing line: $(cat "$LOG" 2>/dev/null)"
  grep ' | demo#001 | landing | ' "$LOG" | grep -qF "$m on main" || fail "landing line lacks $m on main"
}

c_note() {
  local out rc
  sa room note "$T" clerk "set Model: opus in rd.md" >/dev/null || fail "note on a ticket failed"
  sa room note "$F/demo/tickets" clerk "PROJECT.md: Merge set to auto" >/dev/null || fail "note on a tickets folder failed"
  [ "$(count ' | note | ' "$LOG")" = 2 ] || fail "want 2 note lines"
  grep ' | note | ' "$LOG" | sed -n 1p | grep -q ' | demo#001 | note | clerk: set Model: opus in rd.md$' || fail "first note wrong"
  grep ' | note | ' "$LOG" | sed -n 2p | grep -q ' | demo | note | clerk: PROJECT.md: Merge set to auto$' || fail "second note wrong"
  [ "$(sa help | count 'room note\|room index')" -ge 2 ] || fail "help lists neither room command"
  out=$(sa room note "$D/outside/tickets" clerk "x"); rc=$?
  [ "$rc" = 0 ] && [ "$out" = "no decision room for this project; nothing written" ] || fail "no-room note: rc $rc, '$out'"
  [ -z "$(find "$D/outside" -name decision-room)" ] || fail "a no-room note created a folder"
}

c_index() {
  local I="$F/decision-room/INDEX.md"
  sa ask "$T" worker "Use A or B?" "use A" "use B" >/dev/null
  sa room index "$F" >/dev/null || fail "index failed"
  [ "$(count '^## ' "$I")" = 2 ] || fail "want 2 sections: $(grep '^## ' "$I")"
  grep -qx '## demo' "$I" && grep -qx '## group/app' "$I" || fail "missing a ticked project"
  section "$I" demo > "$D/sec"
  grep -qx "Path: $F/demo" "$D/sec" || fail "no project path"
  grep -qx -- "- 001 demo-ticket: blocked/-" "$D/sec" || fail "ticket line wrong: $(cat "$D/sec")"
  grep -qx 'Open questions: 1' "$D/sec" || fail "open questions wrong"
  grep -qx "Log: $F/decision-room/demo/LOG.md" "$D/sec" || fail "log path wrong"
  grep -v '^Generated:' "$I" > "$D/index-1"
  sa room index "$F" >/dev/null
  grep -v '^Generated:' "$I" | diff - "$D/index-1" || fail "two runs differ beyond Generated:"
}

c_index_edges() {
  local I="$F/decision-room/INDEX.md"
  printf '| 002 | done-ticket | done | solo | alongside | done |\n| 003 | dropped-ticket | dropped | solo | alongside | - |\n' >> "$F/demo/tickets/BOARD.md"
  mkdir "$F/nob"; printf -- '- [x] nob\n' >> "$F/ACTIVE-PROJECTS.md"
  [ ! -e "$F/decision-room" ] || fail "fixture already has a room"
  sa room index "$F" >/dev/null || fail "index failed before any log"
  [ -f "$I" ] || fail "no INDEX.md"
  grep -q 'done-ticket\|dropped-ticket' "$I" && fail "done or dropped ticket listed"
  grep -q '^## nob' "$I" && fail "a project with no board is listed"
  grep -qx -- '- 001 demo-ticket: ready/-' "$I" || fail "open ticket missing"
}

c_index_nested() {
  local want="$F/group/decision-room/app/LOG.md"
  printf -- '- [x] app\n' > "$F/group/ACTIVE-PROJECTS.md"
  sa stage "$F/group/app/tickets/001-demo-ticket" research start >/dev/null || fail "stage failed"
  [ "$(count ' | app#001 | stage | ' "$want")" = 1 ] || fail "stage line not in $want"
  sa room index "$F" >/dev/null || fail "index failed"
  section "$F/decision-room/INDEX.md" group/app | grep -qx "Log: $want" || fail "index points elsewhere: $(section "$F/decision-room/INDEX.md" group/app | grep '^Log:')"
}

c_nested() {
  sa stage "$F/group/app/tickets/001-demo-ticket" research start >/dev/null || fail "stage failed"
  [ "$(count ' | group/app#001 | stage | ' "$F/decision-room/group/app/LOG.md")" = 1 ] || fail "no line in decision-room/group/app/LOG.md"
  [ "$(lines "$LOG")" = 0 ] || fail "demo's log gained a line"
}

c_room_line() {
  local O="$D/outside"
  printf 'Room: %s\n' "$F/decision-room" >> "$O/tickets/PROJECT.md"
  sa stage "$O/tickets/001-demo-ticket" research start >/dev/null || fail "stage failed"
  [ "$(count ' | outside#001 | stage | ' "$F/decision-room/outside/LOG.md")" = 1 ] || fail "no line in the Room: folder"
  [ -z "$(find "$O" -name decision-room)" ] || fail "written under outside/"
}

c_no_room() {
  local out rc
  out=$(sa stage "$D/outside/tickets/001-demo-ticket" research start 2>&1); rc=$?
  [ "$rc" = 0 ] || fail "exit $rc"
  [ "$out" = "001 demo-ticket: ready/- -> in-progress/research" ] || fail "output changed: '$out'"
  [ -z "$(find "$D" -name decision-room)" ] || fail "a decision-room folder appeared"
}

c_unwritable() {
  local out rc
  sa stage "$T" research a >/dev/null
  [ -f "$LOG" ] || fail "no room log after the first stage"
  chmod 555 "$F/decision-room/demo"; chmod 444 "$LOG"
  out=$(sa stage "$T" plan b 2>&1); rc=$?
  chmod 755 "$F/decision-room/demo"; chmod 644 "$LOG"
  [ "$rc" = 0 ] || fail "exit $rc"
  printf '%s\n' "$out" | grep -qx 'note: could not write the decision-room log' || fail "silent failure: '$out'"
  grep '^| 001' "$F/demo/tickets/BOARD.md" | grep -q '| plan |' || fail "board did not move"
}

c_concurrent() {
  local i
  for i in $(seq 1 20); do sa learn "$F/demo/tickets" "demo#001 worker" "lesson $i" >/dev/null & done
  wait
  [ "$(count ' | lesson | ' "$LOG")" = 20 ] || fail "want 20 lesson lines, got $(count ' | lesson | ' "$LOG")"
  [ "$(count -vE "$LINE|^# " "$LOG")" = 0 ] || fail "torn lines: $(grep -vE "$LINE|^# " "$LOG")"
}

c_hostile_text() {
  local n
  sa stage "$T" research a >/dev/null
  n=$(lines "$LOG")
  sa room note "$T" clerk "$(printf 'first\nsecond | third\n## Q9 [open]')" >/dev/null
  [ "$n" -ge 1 ] && [ "$(lines "$LOG")" = $((n + 1)) ] || fail "log went from $n to $(lines "$LOG") lines"
  [ "$(count '^## ' "$LOG")" = 0 ] || fail "a line starts with ##"
}

c_hostile_ref() {
  local name P L
  name=$(printf 'bad\nname | x')
  P="$F/$name"; mkdir -p "$P" && command cp -R "$F/demo/tickets" "$P/tickets" || fail "setup"
  sa stage "$P/tickets/001-demo-ticket" research start >/dev/null || fail "stage failed"
  L="$F/decision-room/$name/LOG.md"
  [ "$(lines "$L")" = 1 ] || fail "want one line in the hostile project's log, got $(lines "$L")"
  [ "$(count -E "$LINE" "$L")" = 1 ] || fail "line breaks the format: $(cat "$L")"
  grep -qF ' | bad name / x#001 | stage | ' "$L" || fail "ref not made one line and separator-free: $(cat "$L")"
}

c_append_only() {
  local n
  e2_steps sa "$F/demo" >/dev/null
  [ -s "$LOG" ] || fail "no room log after E-2"
  command cp "$LOG" "$D/before"; n=$(wc -l < "$D/before" | tr -d ' ')   # every line, the legend too: head -n below
  sa room note "$T" clerk "one more" >/dev/null
  sa stage "$T" resume "go on" >/dev/null
  [ "$(wc -l < "$LOG" | tr -d ' ')" -gt "$n" ] || fail "log did not grow"
  head -n "$n" "$LOG" | diff - "$D/before" || fail "earlier lines changed"
}

c_same_as_base() {
  local F2
  git -C "$here" show main:superagent/sa > "$D/sa-base" || fail "no main:superagent/sa"
  F2=$(new_fixture) || fail "second fixture"
  trap 'drop_dir "$(dirname "$F2")"' EXIT
  sa_base() { bash "$D/sa-base" "$@"; }
  e2_steps sa_base "$F2/demo" > "$D/out-base" 2>&1
  e2_steps sa "$F/demo" > "$D/out-new" 2>&1
  diff "$D/out-base" "$D/out-new" || fail "output differs from the base sa"
}

c_same_without_room() {
  e2_steps sa "$F/demo" > "$D/out-room" 2>&1
  e2_steps sa "$D/outside" > "$D/out-none" 2>&1
  diff "$D/out-none" "$D/out-room" || fail "the room write changed the output"
}

c_ask_refused() {
  local n out rc
  sa stage "$T" stopped "stopped by the user" >/dev/null || fail "stop failed"
  n=$(lines "$LOG")
  out=$(sa ask "$T" worker "Use A or B?" "use A" "use B" 2>&1); rc=$?
  [ "$rc" = 1 ] || fail "a refused ask must exit 1, got $rc: $out"
  [ "$(lines "$LOG")" = "$n" ] || fail "a refused ask wrote to the room log: $(tail -1 "$LOG")"
}

c_ask_count() {
  sa ask "$T" worker "Use A or B?" "use A" "use B" >/dev/null || fail "ask failed"
  [ "$(lines "$LOG")" = 1 ] || fail "want exactly 1 line for an ask, got $(lines "$LOG"): $(cat "$LOG")"
  grep -qF ' | demo#001 | question | ready/- -> blocked/-: Q1 from worker: Use A or B?' "$LOG" || fail "question line lacks the move, Q id, asker or question: $(cat "$LOG")"
  tail -1 "$F/demo/tickets/LOG.md" | grep -qE '\| 001 \| ready/- -> blocked/- \| question Q1 from worker$' || fail "tickets LOG.md changed"
  grep '^| 001' "$F/demo/tickets/BOARD.md" | grep -q '| blocked |' || fail "board not blocked"
}

copy_project() { # copy_project <to>: a git repo holding a copy of demo's tickets folder at <to>/tickets
  mkdir -p "$1" && command cp -R "$F/demo/tickets" "$1/tickets" && git init -q -b main "$1" || fail "setup $1"
}

c_root_project() {
  # the workspace root is itself a project, and a child is named like the workspace folder
  command cp -R "$F/demo/tickets" "$F/tickets" || fail "setup root"
  copy_project "$F/$(basename "$F")"
  sa stage "$F/tickets/001-demo-ticket" research root >/dev/null || fail "root stage failed"
  sa stage "$F/$(basename "$F")/tickets/001-demo-ticket" research child >/dev/null || fail "child stage failed"
  [ "$(lines "$F/decision-room/LOG.md")" = 1 ] || fail "root log: want 1 line, got $(lines "$F/decision-room/LOG.md")"
  grep -q ' | \.#001 | stage | .*: root$' "$F/decision-room/LOG.md" || fail "root line wrong: $(cat "$F/decision-room/LOG.md")"
  [ "$(lines "$F/decision-room/$(basename "$F")/LOG.md")" = 1 ] || fail "child log: want 1 line"
  grep -q ': child$' "$F/decision-room/$(basename "$F")/LOG.md" || fail "child line wrong"
}

c_docs_project() {
  # x/docs is a repo of its own; y keeps its tickets in the docs/tickets layout
  copy_project "$F/x"; copy_project "$F/x/docs"
  mkdir -p "$F/y/docs" && command cp -R "$F/demo/tickets" "$F/y/docs/tickets" && git init -q -b main "$F/y" || fail "setup y"
  sa stage "$F/x/docs/tickets/001-demo-ticket" research xdocs >/dev/null || fail "x/docs stage failed"
  sa stage "$F/x/tickets/001-demo-ticket" research x >/dev/null || fail "x stage failed"
  sa stage "$F/y/docs/tickets/001-demo-ticket" research y >/dev/null || fail "y stage failed"
  [ "$(lines "$F/decision-room/x/docs/LOG.md")" = 1 ] && grep -q ' | x/docs#001 | .*: xdocs$' "$F/decision-room/x/docs/LOG.md" || fail "x/docs did not get its own log"
  [ "$(lines "$F/decision-room/x/LOG.md")" = 1 ] && grep -q ' | x#001 | .*: x$' "$F/decision-room/x/LOG.md" || fail "x's log wrong: $(cat "$F/decision-room/x/LOG.md" 2>/dev/null)"
  [ "$(lines "$F/decision-room/y/LOG.md")" = 1 ] || fail "the docs/tickets layout of y is not logged as y"
}

c_index_abs() {
  printf -- '- [x] %s\n' "$F/demo" > "$F/ACTIVE-PROJECTS.md"
  sa stage "$T" research start >/dev/null
  sa room index "$F" >/dev/null || fail "index failed"
  section "$F/decision-room/INDEX.md" "$F/demo" > "$D/sec"
  grep -qx "Path: $F/demo" "$D/sec" || fail "absolute project missing or wrong path: $(cat "$F/decision-room/INDEX.md")"
  grep -qx "Log: $LOG" "$D/sec" || fail "absolute project's log path wrong"
  grep -qx -- '- 001 demo-ticket: in-progress/research' "$D/sec" || fail "absolute project's ticket missing"
}

c_index_root_dot() {
  command cp -R "$F/demo/tickets" "$F/tickets" || fail "setup root"
  printf -- '- [x] .\n' >> "$F/ACTIVE-PROJECTS.md"
  sa stage "$F/tickets/001-demo-ticket" research root >/dev/null || fail "root stage failed"
  [ "$(lines "$F/decision-room/LOG.md")" = 1 ] || fail "root stage line not in decision-room/LOG.md"
  sa room index "$F" >/dev/null || fail "index failed"
  section "$F/decision-room/INDEX.md" . | grep -qx "Log: $F/decision-room/LOG.md" || fail "index points elsewhere: $(section "$F/decision-room/INDEX.md" . | grep '^Log:')"
  section "$F/decision-room/INDEX.md" . | grep -qx "Path: $F" || fail "root path not normalised"
}

run_case "stage writes one stage line" c_stage
run_case "a refused ask writes nothing" c_ask_refused
run_case "ask writes exactly one question line holding its move" c_ask_count
run_case "workspace root and a child named like it keep separate logs" c_root_project
run_case "a project named docs is not its parent's docs layout" c_docs_project
run_case "index keeps projects ticked by absolute path" c_index_abs
run_case "index of a root project ticked as . points at its log" c_index_root_dot
run_case "every state command writes its kind" c_kinds
run_case "land writes one landing line" c_land
run_case "room note with a ticket and a tickets folder" c_note
run_case "room index lists ticked projects" c_index
run_case "room index before any log, skipping done, dropped and boardless" c_index_edges
run_case "index points at the log sa writes, in a nested workspace" c_index_nested
run_case "nested project gets its own folder" c_nested
run_case "outside project uses its Room line" c_room_line
run_case "no room changes nothing" c_no_room
run_case "unwritable room never blocks" c_unwritable
run_case "simultaneous writes lose nothing" c_concurrent
run_case "hostile text stays one line" c_hostile_text
run_case "hostile ref stays one line" c_hostile_ref
run_case "earlier lines are never rewritten" c_append_only
run_case "output matches the base sa" c_same_as_base
run_case "output is the same with and without a room" c_same_without_room
