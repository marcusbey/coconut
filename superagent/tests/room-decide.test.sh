#!/usr/bin/env bash
# room-decide.test.sh: `sa room decide`, the decision record of the decision room (superagent#002).
# Every case runs on its own throwaway fixture (fixture.sh), never on a real workspace.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
sa() { bash "$SA_UNDER_TEST" "$@"; }
B='(🧭|🏛️|✍️|🔨|🤝|🐞|🧪|🔍|🔀|🌐|🐶|👤|❔)'   # the badge of the agent role behind a line (superagent#007)
LINE='^'"$B"' [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \| [^|]+ \| decision \| .+$'
Q='Use A or B?'

F=""; D=""; T=""; R=""; LOG=""; DEC=""
fail() { echo "$*"; exit 1; }
count() { grep -c "$@" 2>/dev/null || true; }
drop_dir() {
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
run_case() { # run_case <name> <function>
  local rc
  F=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$F"); T="$F/demo/tickets/001-demo-ticket"; R="$F/decision-room/demo"; LOG="$R/LOG.md"; DEC="$R/DECISIONS.md"
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  drop_dir "$D"
}

state() { local f; for f in "$DEC" "$LOG"; do if [ -e "$f" ]; then cksum < "$f"; else echo absent; fi; done; }
# refuses "<text>" <args of room decide>: exit 1, prints "refused: <text>", and neither record changed
refuses() {
  local want="$1" before out rc; shift
  before=$(state)
  out=$(sa room decide "$@" 2>&1); rc=$?
  [ "$rc" = 1 ] || fail "want exit 1 for '$want', got $rc: $out"
  printf '%s\n' "$out" | grep -qF "refused: $want" || fail "want 'refused: $want', got: $out"
  [ "$(state)" = "$before" ] || fail "a refusal ('$want') changed DECISIONS.md or LOG.md"
}
control() { # a valid decision on the same fixture must now be D<n>
  local out
  out=$(sa room decide "$T" Q1 "$Q" --option "use A" --option "use B" --fable a "keeps it" --codex a "reversible") || fail "control call failed: $out"
  case "$out" in "D$1: (a) use A; decided by both") ;; *) fail "control call: want D$1, got: $out" ;; esac
}
block() { awk -v h="## D$1" '$0==h {f=1; next} /^## /{f=0} f' "$DEC"; }
has() { block "$1" | grep -qxF -- "$2" || fail "D$1 lacks the line '$2': $(block "$1")"; }

c_agree() {
  local out
  [ ! -e "$F/decision-room" ] || fail "fixture already has a room"
  out=$(sa room decide "$T" Q1 "$Q" --option "use A" --option "use B" --fable a "A keeps the layout" --codex a "A is reversible") || fail "exit $?: $out"
  [ "$out" = "D1: (a) use A; decided by both" ] || fail "printed: $out"
  [ "$(count '^## D' "$DEC")" = 1 ] || fail "want one block"
  block 1 | grep -qE '^Date: [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$' || fail "no Date"
  has 1 "Ticket: demo#001"; has 1 "Subject: Q1"; has 1 "Question: Use A or B?"; has 1 "Options:"
  has 1 "(a) use A"; has 1 "(b) use B"
  has 1 "🟣 Fable 5.2: a: A keeps the layout"; has 1 "🟢 Codex Astra: a: A is reversible"
  has 1 "Decision: (a) use A"; has 1 "Decided by: both"
  [ "$(count ' | decision | ' "$LOG")" = 1 ] || fail "want one decision line: $(cat "$LOG" 2>/dev/null)"
  grep -E "$LINE" "$LOG" | grep -qF ' | demo#001 | decision | D1 (Q1): Use A or B? -> (a) use A; decided by both' || fail "decision line wrong: $(cat "$LOG")"
}

c_fable_alone() {
  local out
  out=$(sa room decide "$T" Q1 "$Q" --option "use A" --option "use B" --fable b "B is simpler" --codex-unavailable "usage limit until Nov 15") || fail "exit $?: $out"
  [ "$out" = "D1: (b) use B; decided by fable alone (codex unavailable: usage limit until Nov 15)" ] || fail "printed: $out"
  has 1 "🟣 Fable 5.2: b: B is simpler"; has 1 "🟢 Codex Astra: unavailable: usage limit until Nov 15"
  has 1 "Decision: (b) use B"; has 1 "Decided by: fable alone (codex unavailable: usage limit until Nov 15)"
}

c_codex_alone() {
  local out
  out=$(sa room decide "$T" Q1 "$Q" --option "use A" --option "use B" --fable-unavailable "overloaded" --codex a "A is reversible") || fail "exit $?: $out"
  [ "$out" = "D1: (a) use A; decided by codex alone (fable unavailable: overloaded)" ] || fail "printed: $out"
  has 1 "🟣 Fable 5.2: unavailable: overloaded"; has 1 "🟢 Codex Astra: a: A is reversible"
  has 1 "Decided by: codex alone (fable unavailable: overloaded)"
}

c_safer() {
  local out
  out=$(sa room decide "$T" Q1 "$Q" --option "use A" --option "use B" --fable a "keeps the layout" --codex b "cleaner" --safer a "A deletes nothing and can be changed later") || fail "exit $?: $out"
  [ "$out" = "D1: (a) use A; decided by safer-option tie-break (A deletes nothing and can be changed later)" ] || fail "printed: $out"
  has 1 "🟣 Fable 5.2: a: keeps the layout"; has 1 "🟢 Codex Astra: b: cleaner"
  has 1 "Decision: (a) use A"; has 1 "Decided by: safer-option tie-break (A deletes nothing and can be changed later)"
}

c_numbering() {
  local out
  control 1
  out=$(sa room decide "$F/demo/tickets" plan "Plan or not?" --option "yes" --option "no" --option "later" --fable c "wait" --codex c "wait too") || fail "exit $?: $out"
  [ "$out" = "D2: (c) later; decided by both" ] || fail "printed: $out"
  has 2 "Ticket: demo"; has 2 "Subject: plan"; has 2 "(c) later"
  [ "$(count ' | demo | decision | D2 (plan)' "$LOG")" = 1 ] || fail "tickets-folder log line wrong: $(cat "$LOG")"
}

c_none() {
  refuses "no seat is available; this question reaches the user" "$T" Q1 "$Q" --option "use A" --option "use B" --fable-unavailable "overloaded" --codex-unavailable "usage limit"
  [ ! -e "$DEC" ] || fail "DECISIONS.md written"
  control 1
}

c_bad_safer() {
  local a=("$T" Q1 "$Q" --option "use A" --option "use B" --option "use C" --fable a "keeps" --codex b "cleaner")
  refuses "the seats differ (a, b); --safer must name one of them, with why" "${a[@]}"
  refuses "the seats differ (a, b); --safer must name one of them, with why" "${a[@]}" --safer c "x"
  refuses "the seats differ (a, b); --safer must name one of them, with why" "${a[@]}" --safer a ""
  [ ! -e "$DEC" ] || fail "a block was added: $(cat "$DEC")"
  control 1
}

c_incomplete() {
  local ok=(--fable a "x" --codex a "y")
  refuses "a decision needs at least two options" "$T" Q1 "$Q" --option "use A" "${ok[@]}"
  refuses "fable's position 'z' is not one of the options (a-b)" "$T" Q1 "$Q" --option "use A" --option "use B" --fable z "x" --codex a "y"
  refuses "fable's position needs its reasoning" "$T" Q1 "$Q" --option "use A" --option "use B" --fable a "" --codex a "y"
  refuses "codex unavailable needs its reason" "$T" Q1 "$Q" --option "use A" --option "use B" --fable a "x" --codex-unavailable ""
  refuses "option b is empty" "$T" Q1 "$Q" --option "use A" --option "" "${ok[@]}"
  refuses "the question is empty" "$T" Q1 "" --option "use A" --option "use B" "${ok[@]}"
  refuses "subject must be Q<n>, ready, plan, merge, S<n> or other (got 'Q')" "$T" Q "$Q" --option "use A" --option "use B" "${ok[@]}"
  refuses "the fable seat is given twice" "$T" Q1 "$Q" --option "use A" --option "use B" --fable a "x" --fable-unavailable "y" --codex a "y"
  refuses "the codex seat is missing" "$T" Q1 "$Q" --option "use A" --option "use B" --fable a "x"
  refuses "unknown option '--bogus'" "$T" Q1 "$Q" --option "use A" --option "use B" "${ok[@]}" --bogus
  refuses "no decision room for this project; nothing written" "$D/outside/tickets/001-demo-ticket" Q1 "$Q" --option "use A" --option "use B" "${ok[@]}"
  [ -z "$(find "$D" -name DECISIONS.md)" ] || fail "a DECISIONS.md exists: $(find "$D" -name DECISIONS.md)"
  [ -z "$(find "$D/outside" -name decision-room)" ] || fail "a room appeared for outside"
  control 1
}

c_no_ticket_change() {
  local out
  ( cd "$F/demo" && git add -A && { git commit -qm fixture >/dev/null || true; } )   # fixture.sh has already committed it
  [ -z "$(git -C "$F/demo" status --porcelain)" ] || fail "fixture not clean before the decision"
  out=$(sa room decide "$T" Q1 "$Q" --option "use A" --option "use B" --fable a "A keeps the layout" --codex a "A is reversible")
  case "$out" in "D1: "*) ;; *) fail "no D1 printed: $out" ;; esac
  [ -z "$(git -C "$F/demo" status --porcelain)" ] || fail "the project changed: $(git -C "$F/demo" status --porcelain)"
}

c_hostile() {
  local nl
  nl=$(printf 'line one\n## D9\nline three')
  sa room decide "$T" Q1 "$nl" --option "$nl" --option "use B" --fable a "$nl" --codex a "x | y" >/dev/null || fail "decide failed"
  [ "$(count '^## ' "$DEC")" = 1 ] || fail "hostile text opened a heading: $(grep '^## ' "$DEC")"
  has 1 "Question: line one ## D9 line three"
  [ "$(count ' | decision | ' "$LOG")" = 1 ] && [ "$(count -vE '^# |^'"$B"' [0-9]{4}-' "$LOG")" = 0 ] || fail "log broke: $(cat "$LOG")"
}

c_concurrent() {
  local i
  for i in 1 2 3 4 5; do sa room decide "$T" "Q$i" "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y" >/dev/null & done
  wait
  for i in 1 2 3 4 5; do [ "$(count -x "## D$i" "$DEC")" = 1 ] || fail "D$i appears $(count -x "## D$i" "$DEC") times"; done
  [ "$(count '^## D' "$DEC")" = 5 ] || fail "want 5 blocks"
  [ "$(count ' | decision | ' "$LOG")" = 5 ] || fail "want 5 decision lines"
}

c_room_line() {
  local O="$D/outside" out
  printf 'Room: %s\n' "$F/decision-room" >> "$O/tickets/PROJECT.md"
  out=$(sa room decide "$O/tickets/001-demo-ticket" Q1 "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y") || fail "exit $?: $out"
  [ "$(count -x '## D1' "$F/decision-room/outside/DECISIONS.md")" = 1 ] || fail "no D1 in the Room: folder"
  grep -qxF 'Ticket: outside#001' "$F/decision-room/outside/DECISIONS.md" || fail "ref wrong"
  [ -z "$(find "$O" -name DECISIONS.md)" ] || fail "written under outside/"
}

c_index_log_dir() {
  local p t log
  command cp -R "$F/demo/tickets" "$F/tickets" || fail "setup root"
  printf -- '- [x] .\n' >> "$F/ACTIVE-PROJECTS.md"
  for t in "$F/demo/tickets/001-demo-ticket" "$F/group/app/tickets/001-demo-ticket" "$F/tickets/001-demo-ticket"; do
    sa room decide "$t" Q1 "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y" >/dev/null || fail "decide failed for $t"
  done
  sa room index "$F" >/dev/null || fail "index failed"
  for p in demo group/app .; do
    log=$(awk -v h="## $p" '$0==h {f=1; next} /^## /{f=0} f && /^Log: /{print substr($0,6)}' "$F/decision-room/INDEX.md")
    [ -n "$log" ] || fail "no Log: line for $p"
    [ "$(count -x '## D1' "$(dirname "$log")/DECISIONS.md")" = 1 ] || fail "$p: no DECISIONS.md next to $log"
  done
}

c_room_uncreatable() {
  printf 'not a folder\n' > "$F/decision-room"
  refuses "could not create the room folder" "$T" Q1 "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y"
  [ "$(cat "$F/decision-room")" = "not a folder" ] || fail "the file changed"
}

c_unreadable_decisions() {
  local before out rc
  control 1
  before=$(state); chmod 000 "$DEC"
  out=$(sa room decide "$T" Q2 "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y" 2>&1); rc=$?
  chmod 644 "$DEC"
  [ "$rc" = 1 ] || fail "exit $rc: $out"
  printf '%s\n' "$out" | grep -qF 'refused: could not prepare DECISIONS.md; nothing written' || fail "wrong refusal: $out"
  [ "$(state)" = "$before" ] || fail "records changed"
  ls "$R" | grep -q '\.sa\.' && fail "temp files left: $(ls "$R")"
  return 0
}

c_unwritable_room() {
  local before out rc
  control 1
  before=$(state); chmod 555 "$R"
  out=$(sa room decide "$T" Q2 "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y" 2>&1); rc=$?
  chmod 755 "$R"
  [ "$rc" = 1 ] || fail "exit $rc: $out"
  printf '%s\n' "$out" | grep -qE 'refused: could not (prepare|write) DECISIONS.md; nothing written' || fail "wrong refusal: $out"
  [ "$(state)" = "$before" ] || fail "records changed"
}

c_unwritable_log() {
  mkdir -p "$R" && printf '2026-01-01 00:00 | demo#001 | note | before\n' > "$LOG" && chmod 444 "$LOG"
  refuses "could not write the decision-room log; the decision was not recorded" "$T" Q1 "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y"
  [ ! -e "$DEC" ] || fail "DECISIONS.md left behind"
  chmod 644 "$LOG"; control 1; chmod 444 "$LOG"
  refuses "could not write the decision-room log; the decision was not recorded" "$T" Q2 "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y"
  [ "$(count '^## D' "$DEC")" = 1 ] || fail "D2 left behind"
  ls "$R" | grep -q '\.sa\.' && fail "temp files left: $(ls "$R")"
  return 0
}

c_partial_log() {
  local before out rc
  control 1
  before=$(state)
  # only the decision line of the room log is cut in half, then the write fails
  out=$(
    printf() {
      if [ "${1:-}" = '%s | %s | %s | %s\n' ] && [ "${4:-}" = decision ]; then builtin printf '%s' "${2:-} | half a li"; return 1; fi
      builtin printf "$@"
    }
    export -f printf
    sa room decide "$T" Q2 "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y" 2>&1
  ); rc=$?
  [ "$rc" = 1 ] || fail "exit $rc: $out"
  printf '%s\n' "$out" | grep -qF 'refused: could not write the decision-room log; the decision was not recorded' || fail "wrong refusal: $out"
  [ "$(state)" = "$before" ] || fail "records changed: $(tail -2 "$LOG")"
  grep -q 'half a li' "$LOG" && fail "the half line stayed"
  out=$(sa room decide "$T" Q2 "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y") || fail "next call failed"
  [ "$out" = "D2: (a) use A; decided by both" ] || fail "next call: $out"
}

c_failed_option_write() {
  local before out rc
  control 1
  before=$(state)
  # the write of option (a), not the last write of the block, fails
  out=$(
    printf() {
      if [ "${1:-}" = '(%s) %s\n' ] && [ "${2:-}" = a ]; then return 1; fi
      builtin printf "$@"
    }
    export -f printf
    sa room decide "$T" Q2 "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y" 2>&1
  ); rc=$?
  [ "$rc" = 1 ] || fail "exit $rc: $out"
  printf '%s\n' "$out" | grep -qF 'refused: could not prepare DECISIONS.md; nothing written' || fail "wrong refusal: $out"
  [ "$(state)" = "$before" ] || fail "records changed: $(tail -2 "$LOG")"
  out=$(sa room decide "$T" Q2 "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y") || fail "next call failed"
  [ "$out" = "D2: (a) use A; decided by both" ] || fail "next call: $out"
}

c_help() {
  sa help | grep -q 'room decide' || fail "help lacks room decide"
}

run_case "both seats agree" c_agree
run_case "fable decides alone" c_fable_alone
run_case "codex decides alone" c_codex_alone
run_case "a disagreement goes to the safer option" c_safer
run_case "numbers count up, a tickets folder records the project" c_numbering
run_case "both seats unavailable decides nothing" c_none
run_case "a disagreement without a valid safer option is refused" c_bad_safer
run_case "an incomplete decision is refused" c_incomplete
run_case "recording a decision changes no ticket" c_no_ticket_change
run_case "hostile text stays in its field" c_hostile
run_case "simultaneous decisions get distinct numbers" c_concurrent
run_case "a Room: project records in its room" c_room_line
run_case "DECISIONS.md sits next to the index's Log: line" c_index_log_dir
run_case "a room folder that cannot be made is refused" c_room_uncreatable
run_case "an unreadable DECISIONS.md is never replaced" c_unreadable_decisions
run_case "a read-only room changes nothing" c_unwritable_room
run_case "a log that cannot be written takes the record back" c_unwritable_log
run_case "a half-written log line is taken back" c_partial_log
run_case "a failed option write is refused before anything is replaced" c_failed_option_write
run_case "help lists room decide" c_help
